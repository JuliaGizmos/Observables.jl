module Observables

export Observable, on, off, onany, connect!, obsid, async_latest, throttle

import Base.Iterators.filter

const addhandler_callbacks = []
const removehandler_callbacks = []

abstract type AbstractObservable{T} end

# Internal function that doesn't need invokelatest!
abstract type InternalFunction <: Function end

function observe(::S) where {S<:AbstractObservable}
    error("observe not defined for AbstractObservable $S")
end

"""
Like a `Ref` but updates can be watched by adding a handler using `on`.
"""
mutable struct Observable{T} <: AbstractObservable{T}
    listeners::Vector{Any}
    val::T
    Observable{T}() where {T} = new{T}([])
    Observable{T}(val) where {T} = new{T}([], val)
end

function Base.copy(observable::Observable{T}) where T
    result = Observable{T}(observable[])
    on(observable) do value
        result[] = value
    end
    return result
end

Observable(val::T) where {T} = Observable{T}(val)

observe(x::Observable) = x

Base.convert(::Type{Observable}, x::AbstractObservable) = x
Base.convert(::Type{Observable{T}}, x::AbstractObservable{T}) where {T} = x

function Base.convert(::Type{Observable{T}}, x::AbstractObservable) where {T}
    result = Observable{T}(convert(T, x[]))
    on(x) do value
        result[] = convert(T, value)
    end
    return result
end

Base.convert(::Type{T}, x) where {T<:Observable} = T(x)

function Base.getproperty(obs::Observable, field::Symbol)
    if field === :val
        return getfield(obs, field)
    elseif field === :listeners
        return getfield(obs, field)
    elseif field === :id
        return obsid(obs)
    else
        error("Field $(field) not found")
    end
end

"""
    notify!(observable::AbstractObservable)

Pushes an updates to all listeners of `observable`
"""
function notify!(observable::AbstractObservable)
    observable[] = observable[]
    return
end

function Base.show(io::IO, x::Observable{T}) where T
    println(io, "Observable{$T} with $(length(x.listeners)) listeners. Value:")
    if isdefined(x, :val)
        show(io, x.val)
    else
        println(io, "not assigned yet!")
    end
end

Base.show(io::IO, ::MIME"application/prs.juno.inline", x::Observable) = x

"""
    on(f, observable::AbstractObservable)

Adds function `f` as listener to `observable`. Whenever `observable`'s value
is set via `observable[] = val` `f` is called with `val`.
"""
function on(f, observable::AbstractObservable)
    push!(listeners(observable), f)
    for g in addhandler_callbacks
        g(f, observable)
    end
    return f
end

"""
    off(observable::AbstractObservable, f)

Removes `f` from listeners of `observable`.
"""
function off(observable::AbstractObservable, f)
    callbacks = listeners(observable)
    for (i, f2) in enumerate(callbacks)
        if f === f2
            deleteat!(callbacks, i)
            for g in removehandler_callbacks
                g(observable, f)
            end
            return
        end
    end
    throw(KeyError(f))
end

"""
    observable[] = val

Updates the value of an `Observable` to `val` and call its listeners.
"""
function Base.setindex!(observable::Observable, val; notify=(x)->true)
    observable.val = val
    for f in listeners(observable)
        if notify(f)
            if f isa InternalFunction
                f(val)
            else
                Base.invokelatest(f, val)
            end
        end
    end
end

####################################################
# tasks & channel api

Observable(val::Channel{T}) where {T} = Observable{T}(val)
Observable(val::Task) = Observable{Any}(val)
function Observable{T}(val::Union{Task, Channel}) where {T}
    observable = Observable{T}()
    observable[] = val
    return observable
end

function Base.setindex!(observable::Observable, val_async::Task; notify=x->true)
    return @async begin
        try
            val = fetch(val_async)
            setindex!(observable, val, notify=notify)
        catch e
            Base.showerror(stderr, e)
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end
end

function Base.setindex!(observable::Observable, channel::Channel; notify=x->true)
    return @async begin
        try
            for val in channel
                setindex!(observable, val, notify=notify)
                yield()
            end
        catch e
            Base.showerror(stderr, e)
            Base.show_backtrace(stderr, catch_backtrace())
        end
    end
end

function Base.setindex!(observable::AbstractObservable, val; notify=x->true)
    Base.setindex!(observe(observable), val; notify=notify)
end

function setexcludinghandlers(observable::AbstractObservable, val, pred=x->true)
    setindex!(observable, val; notify=pred)
end

"""
    observable[]

Returns the current value of `observable`.
"""
Base.getindex(observable::Observable) = observable.val

Base.getindex(observable::AbstractObservable) = getindex(observe(observable))

### Utilities

"""
    to_value(x::Union{Any, AbstractObservable})
Extracts the value of an observable, and returns the object if it's not an observable!
"""
to_value(observable::AbstractObservable) = observable[]
to_value(x) = x


"""
    obsid(observable::Observable)

Gets a unique id for an observable!
"""
obsid(observable::Observable) = string(objectid(observable))
obsid(observable::AbstractObservable) = obsid(observe(observable))

listeners(observable::Observable) = observable.listeners
listeners(observable::AbstractObservable) = listeners(observe(observable))

struct OnUpdate{F, Args} <: InternalFunction
    f::F
    args::Args
end

(ou::OnUpdate)(_) = ou.f(map(to_value, ou.args)...)

"""
    onany(f, args...)

Calls `f` on updates to any oservable refs in `args`.
`args` may contain any number of `Observable` objects.
`f` will be passed the values contained in the refs as the respective argument.
All other objects in `args` are passed as-is.
"""
function onany(f, args...)
    callback = OnUpdate(f, args)
    for observable in args
        (observable isa AbstractObservable) && on(callback, observable)
    end
end

struct MapUpdater{F, T} <: InternalFunction
    f::F
    observable::Observable{T}
end

function (mu::MapUpdater)(args...)
    mu.observable[] = mu.f(args...)
end

"""
    map!(f, observable::AbstractObservable, args...)

Updates `observable` with the result of calling `f` with values extracted from args.
`args` may contain any number of `Observable` objects.
`f` will be passed the values contained in the refs as the respective argument.
All other objects in `args` are passed as-is.
"""
function Base.map!(f, observable::AbstractObservable, os...)
    onany(MapUpdater(f, observable), os...)
    return observable
end

"""
    connect!(o1::AbstractObservable, o2::AbstractObservable)

Forwards all updates from `o2` to `o1`
"""
connect!(o1::AbstractObservable, o2::AbstractObservable) = map!(identity, o2, o1)

"""
    map(f, observable::AbstractObservable, args...)

Creates a new observable ref which contains the result of `f` applied to
values extracted from args. The second argument `observable` must be an observable ref for
dispatch reasons. `args` may contain any number of `Observable` objects.
`f` will be passed the values contained in the refs as the respective argument.
All other objects in `args` are passed as-is.
"""
function Base.map(f, observable::AbstractObservable, os...;
                  init=f(observable[], map(to_value, os)...))
    map!(f, Observable{Any}(init), observable, os...)
end

Base.eltype(::AbstractObservable{T}) where {T} = T

"""
    async_latest(observable::AbstractObservable, n=1)

Returns an `Observable` which drops all but
the last `n` updates to `observable` if processing the updates
takes longer than the interval between updates.

This is useful if you want to pass the updates from,
say, a slider to a plotting function that takes a while to
compute. The plot will directly compute the last frame
skipping the intermediate ones.

# Example:
```
observable = Observable(0)
function compute_something(x)
    for i=1:10^8 rand() end # simulate something expensive
    println("updated with \$x")
end
o_latest = async_latest(observable, 1)
on(compute_something, o_latest) # compute something on the latest update

for i=1:5
    observable[] = i
end
```
"""
function async_latest(input::AbstractObservable{T}, n=1) where T
    buffer = T[]
    cond = Condition()
    lck  = ReentrantLock() # advisory lock for access to buffer
    output = Observable{T}(input[]) # output

    @async while true
        while true # while !isempty(buffer) but with a lock
            # transact a pop
            lock(lck)
            if isempty(buffer)
                unlock(lck)
                break
            end
            upd = pop!(buffer)
            unlock(lck)

            output[] = upd
        end
        wait(cond)
    end

    on(input) do val
        lock(lck)
        if length(buffer) < n
            push!(buffer, val)
        else
            while length(buffer) >= n
                pop!(buffer)
            end
            pushfirst!(buffer, val)
        end
        unlock(lck)
        notify(cond)
    end

    output
end

# TODO: overload broadcast on v0.6
include("observablepair.jl")
include("flatten.jl")
include("time.jl")
include("macros.jl")

end # module
