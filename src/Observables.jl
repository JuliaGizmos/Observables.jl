__precompile__()

module Observables

export Observable, on, off, onany, connect!, obsid, async_latest, throttle

import Base.Iterators.filter

const addhandler_callbacks = []
const removehandler_callbacks = []

abstract type AbstractObservable{T}; end

function observe(::S) where {S<:AbstractObservable}
    error("observe not defined for AbstractObservable $S")
end

"""
Like a `Ref` but updates can be watched by adding a handler using `on`.
"""
mutable struct Observable{T} <: AbstractObservable{T}
    id::String
    val::T
    listeners::Vector
end
Observable{T}(val) where {T} = Observable{T}(newid(), val, Any[])
Observable(val::T) where {T} = Observable{T}(val)

observe(x::Observable) = x

let count=0
    global newid
    function newid(prefix="ob_")
        string(prefix, lpad(count += 1, 2, "0"))
    end
end

function Base.show(io::IO, x::Observable{T}) where T
    println(io, "Observable{$T} with $(length(x.listeners)) listeners. Value:")
    show(io, x.val)
end

Base.show(io::IO, ::MIME"application/prs.juno.inline", x::Observable) = x

"""
    on(f, o::AbstractObservable)

Adds function `f` as listener to `o`. Whenever `o`'s value
is set via `o[] = val` `f` is called with `val`.
"""
function on(f, o::AbstractObservable)
    push!(listeners(o), f)
    for g in addhandler_callbacks
        g(f, o)
    end
    f
end

"""
    off(o::AbstractObservable, f)

Removes `f` from listeners of `o`.
"""
function off(o::AbstractObservable, f)
    for i in 1:length(listeners(o))
        if f === listeners(o)[i]
            deleteat!(listeners(o), i)
            for g in removehandler_callbacks
                g(o, f)
            end
            return
        end
    end
    throw(KeyError(f))
end

"""
    o[] = val

Updates the value of an `Observable` to `val` and call its listeners.
"""
function Base.setindex!(o::Observable, val; notify=x->true)
    o.val = val
    for f in listeners(o)
        if notify(f)
            try
                f(val)
            catch e
                # As weird as it is, Julia does seem to have problems with errors
                # encountered in f(val) - it might stack overflow or just silently freeze
                # the try catch and manual error display seems to solve this
                Base.showerror(stderr, e)
                Base.show_backtrace(stderr, catch_backtrace())
                rethrow(e)
            end
        end
    end
end

Base.setindex!(o::AbstractObservable, val; notify=x->true) =
    Base.setindex!(observe(o), val; notify=notify)

setexcludinghandlers(o::AbstractObservable, val, pred=x->true) =
    setindex!(o, val; notify=pred)

"""
    o[]

Returns the current value of `o`.
"""
Base.getindex(o::Observable) = o.val

Base.getindex(o::AbstractObservable) = getindex(observe(o))

### Utilities

_val(o::AbstractObservable) = o[]
_val(x) = x

obsid(o::Observable) = o.id
obsid(o::AbstractObservable) = obsid(observe(o))

listeners(o::Observable) = o.listeners
listeners(o::AbstractObservable) = listeners(observe(o))

"""
    onany(f, args...)

Calls `f` on updates to any oservable refs in `args`.
`args` may contain any number of `Observable` ojects.
`f` will be passed the values contained in the refs as the respective argument.
All other ojects in `args` are passed as-is.
"""
function onany(f, os...)
    oservs = filter(x->isa(x, AbstractObservable), os)
    g(_) = f(map(_val, os)...)
    for o in oservs
        on(g, o)
    end
end

"""
    map!(f, o::Observable, args...)

Updates `o` with the result of calling `f` with values extracted from args.
`args` may contain any number of `Observable` ojects.
`f` will be passed the values contained in the refs as the respective argument.
All other ojects in `args` are passed as-is.
"""
function Base.map!(f, o::AbstractObservable, os...)
    onany(os...) do val...
        o[] = f(val...)
    end
    o
end

"""
    connect!(o1::Observable, o2::Observable)

Forward all updates to `o1` to `o2`
"""
connect!(o1::AbstractObservable, o2::AbstractObservable) = map!(identity, o2, o1)

"""
    map(f, o::Observable, args...)

Creates a new oservable ref which contains the result of `f` applied to
values extracted from args. The second argument `o` must be an oservable ref for
dispatch reasons. `args` may contain any number of `Observable` ojects.
`f` will be passed the values contained in the refs as the respective argument.
All other ojects in `args` are passed as-is.
"""
function Base.map(f, o::AbstractObservable, os...; init=f(o[], map(_val, os)...))
    map!(f, Observable{Any}(init), o, os...)
end

Base.eltype(::AbstractObservable{T}) where {T} = T

"""
`async_latest(o::AbstractObservable, n=1)`

Returns an `Observable` which drops all but
the last `n` updates to `o` if processing the updates
takes longer than the interval between updates.

This is useful if you want to pass the updates from,
say, a slider to a plotting function that takes a while to
compute. The plot will directly compute the last frame
skipping the intermediate ones.

# Example:
```
o = Observable(0)
function compute_something(x)
    for i=1:10^8 rand() end # simulate something expensive
    println("updated with \$x")
end
o_latest = async_latest(o, 1)
on(compute_something, o_latest) # compute something on the latest update

for i=1:5
    o[] = i
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
