module Observables

export Observable, on, off, onany, connect!, obsid, async_latest, throttle
export Consume, ChangeObservable, ObserverFunction, AbstractObservable

import Base.Iterators.filter

# @nospecialize "blocks" codegen but not necessarily inference. This forces inference
# to drop specific information about an argument.
if isdefined(Base, :inferencebarrier)
    const inferencebarrier = Base.inferencebarrier
else
    inferencebarrier(x) = Ref{Any}(x)[]
end

const addhandler_callbacks = []
const removehandler_callbacks = []

abstract type AbstractObservable{T} end

function observe(::S) where {S<:AbstractObservable}
    error("observe not defined for AbstractObservable $S")
end

"""
    obs = Observable(val)
    obs = Observable{T}(val)

Like a `Ref`, but updates can be watched by adding a handler using [`on`](@ref) or [`map`](@ref).
"""
mutable struct Observable{T} <: AbstractObservable{T}

    listeners::Vector{Pair{Int, Any}}
    inputs::Vector{Any}  # for map!ed Observables
    ignore_equal_values::Bool
    val::T

    function Observable{T}(; ignore_equal_values::Bool=false) where {T}
        return new{T}(Pair{Int, Any}[], [], ignore_equal_values)
    end
    function Observable{T}(val; ignore_equal_values::Bool=false) where {T}
        return new{T}(Pair{Int, Any}[], [], ignore_equal_values, val)
    end
    # Construct an Observable{Any} without runtime dispatch
    function Observable{Any}(@nospecialize(val); ignore_equal_values::Bool=false)
        return new{Any}(Pair{Int, Any}[], [], ignore_equal_values, val)
    end
end

ignore_equal_values(obs::Observable) = obs.ignore_equal_values
ignore_equal_values(obs::AbstractObservable) = false

function Base.copy(observable::Observable{T}) where T
    result = Observable{T}(observable[])
    on(observable) do value
        result[] = value
    end
    return result
end

Observable(val::T) where {T} = Observable{T}(val)


"""
    obs = ChangeObservable(value)

Returns an `Observable` which updates with the value of `arg` whenever the new value
differs from the current value of `obs` according to the equality (==).

# Example:
```
julia> obs = ChangeObservable(0);
julia> on(obs) do o
           println("obs_change[] == \$o")
       end;
julia> obs[] = 0;
julia> obs[] = 1;
obs_change[] == 1
julia> obs[] = 1;
```
"""
function ChangeObservable(val::T) where T
    return Observable{T}(val; ignore_equal_values=true)
end

Base.eltype(::AbstractObservable{T}) where {T} = T

observe(x::Observable) = x

function Base.convert(::Type{Observable{T}}, x::AbstractObservable) where {T}
    result = Observable{T}(convert(T, x[]))
    on(x) do value
        result[] = convert(T, value)
    end
    return result
end

Base.convert(::Type{T}, x::T) where {T<:Observable} = x  # resolves ambiguity with convert(::Type{T}, x::T) in base/essentials.jl
Base.convert(::Type{T}, x) where {T<:Observable} = T(x)

struct Consume
    x::Bool
end
Consume() = Consume(true)
Consume(x::Consume) = Consume(x.x) # for safety in selection_point etc

"""
    notify(observable::AbstractObservable)

Update all listeners of `observable`.
"""
function Base.notify(@nospecialize(observable::AbstractObservable))
    val = observable[]
    for (prio, f) in listeners(observable)
        result = Base.invokelatest(f, val)
        if result isa Consume && result.x
            # stop calling callbacks if event got consumed
            return true
        end
    end
    return false
end

function Base.show(io::IO, x::Observable{T}) where T
    println(io, "Observable{$T} with $(length(x.listeners)) listeners. Value:")
    if isdefined(x, :val)
        show(io, x.val)
    else
        print(io, "not assigned yet!")
    end
end

Base.show(io::IO, ::MIME"application/prs.juno.inline", x::Observable) = x

"""
    mutable struct ObserverFunction <: Function

Fields:

    f::Function
    observable::AbstractObservable
    weak::Bool

`ObserverFunction` is intended as the return value for `on` because
we can remove the created closure from `obsfunc.observable`'s listener vectors when
ObserverFunction goes out of scope - as long as the `weak` flag is set.
If the `weak` flag is not set, nothing happens
when the ObserverFunction goes out of scope and it can be safely ignored.
It can still be useful because it is easier to call `off(obsfunc)` instead of `off(observable, f)`
to release the connection later.
"""
mutable struct ObserverFunction <: Function
    f
    observable::AbstractObservable
    weak::Bool

    function ObserverFunction(@nospecialize(f), observable::AbstractObservable, weak)
        obsfunc = new(f, observable, weak)

        # If the weak flag is set, deregister the function f from the observable
        # storing it in its listeners once the ObserverFunction is garbage collected.
        # This should free all resources associated with f unless there
        # is another reference to it somewhere else.
        if weak
            finalizer(off, obsfunc)
        end

        obsfunc
    end
end

Base.precompile(obsf::ObserverFunction) = precompile(obsf.f, (eltype(obsf.observable),))
function Base.precompile(observable::Observable)
    tf = true
    T = eltype(observable)
    for f in observable.listeners
        precompile(f, (T,))
    end
    if isdefined(observable, :inputs)
        for obsf in observable.inputs
            tf &= precompile(obsf)
        end
    end
    return tf
end

"""
    on(f, observable::AbstractObservable; weak = false)

Adds function `f` as listener to `observable`. Whenever `observable`'s value
is set via `observable[] = val`, `f` is called with `val`.

Returns an [`ObserverFunction`](@ref) that wraps `f` and `observable` and allows to
disconnect easily by calling `off(observerfunction)` instead of `off(f, observable)`.
If instead you want to compute a new `Observable` from an old one, use [`map(f, ::Observable)`](@ref).

If `weak = true` is set, the new connection will be removed as soon as the returned `ObserverFunction`
is not referenced anywhere and is garbage collected. This is useful if some parent object
makes connections to outside observables and stores the resulting `ObserverFunction` instances.
Then, once that parent object is garbage collected, the weak
observable connections are removed automatically.

# Example

```jldoctest; setup=:(using Observables)
julia> obs = Observable(0)
Observable{$Int} with 0 listeners. Value:
0

julia> on(obs) do val
           println("current value is ", val)
       end
(::Observables.ObserverFunction) (generic function with 0 methods)

julia> obs[] = 5;
current value is 5
```
"""
function on(@nospecialize(f), @nospecialize(observable::AbstractObservable); weak::Bool = false, priority = 0, update = false)
    ls = listeners(observable)
    idx = searchsortedlast(ls, priority; by=first, rev=true)
    insert!(ls, idx + 1, priority => f)
    for g in addhandler_callbacks
        g(f, observable)
    end
    if update
        f(observable[])
    end
    # Return a ObserverFunction so that the caller is responsible
    # to keep a reference to it around as long as they want the connection to
    # persist. If the ObserverFunction is garbage collected, f will be released from
    # observable's listeners as well.
    return ObserverFunction(f, observable, weak)
end

"""
    off(observable::AbstractObservable, f)

Removes `f` from listeners of `observable`.

Returns `true` if `f` could be removed, otherwise `false`.
"""
function off(observable::AbstractObservable, @nospecialize(f))
    callbacks = listeners(observable)
    for (i, (prio, f2)) in enumerate(callbacks)
        if f === f2
            deleteat!(callbacks, i)
            for g in removehandler_callbacks
                g(observable, f)
            end
            return true
        end
    end
    return false
end


function off(observable::AbstractObservable, obsfunc::ObserverFunction)
    f = obsfunc.f
    # remove the function inside obsfunc as usual
    off(observable, f)
end

"""
    off(obsfunc::ObserverFunction)

Remove the listener function `obsfunc.f` from the listeners of `obsfunc.observable`.
Once `obsfunc` goes out of scope, this should allow `obsfunc.f` and all the values
it might have closed over to be garbage collected (unless there
are other references to it).
"""
function off(obsfunc::ObserverFunction)
    off(obsfunc.observable, obsfunc)
end

"""
    observable[] = val

Updates the value of an `Observable` to `val` and call its listeners.
"""
function Base.setindex!(observable::Observable, val)
    if ignore_equal_values(observable)
        isequal(observable.val, val) && return
    end
    observable.val = val
    return notify(observable)
end

function Base.setindex!(observable::AbstractObservable, val)
    Base.setindex!(observe(observable), val)
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
to_value(x) = isa(x, AbstractObservable) ? x[] : x  # noninferrable dispatch is faster if there is only one Method

"""
    obsid(observable::Observable)

Gets a unique id for an observable.
"""
obsid(observable::Observable) = string(objectid(observable))
obsid(observable::AbstractObservable) = obsid(observe(observable))

listeners(observable::Observable) = observable.listeners
listeners(observable::AbstractObservable) = listeners(observe(observable))

"""
    onany(f, args...)

Calls `f` on updates to any observable refs in `args`.
`args` may contain any number of `Observable` objects.
`f` will be passed the values contained in the refs as the respective argument.
All other objects in `args` are passed as-is.

See also: [`on`](@ref).
"""
function onany(@nospecialize(f), args...; weak::Bool = false)
    ff = (_) -> f(to_value.(args)...)
    _onany(inferencebarrier(ff), args, weak)
end

@noinline function _onany(@nospecialize(callback), args, weak::Bool)
    # store all returned ObserverFunctions
    obsfuncs = ObserverFunction[]
    for observable in args
        if observable isa AbstractObservable
            obsfunc = on(callback, observable, weak = weak)
            push!(obsfuncs, obsfunc)
        end
    end
    # same principle as with `on`, this collection needs to be
    # stored by the caller or the connections made will be cut
    obsfuncs
end

"""
    map!(f, observable::AbstractObservable, args...; update::Bool=true)

Updates `observable` with the result of calling `f` with values extracted from args.
`args` may contain any number of `Observable` objects.
`f` will be passed the values contained in the refs as the respective argument.
All other objects in `args` are passed as-is.

By default `observable` gets updated immediately, but this can be suppressed by specifying `update=false`.

# Example

We'll create an observable that can hold an arbitrary number:

```jldoctest map!; setup=:(using Observables)
julia> obs = Observable{Number}(3)
Observable{Number} with 0 listeners. Value:
3
```

Now,

```jldoctest map!
julia> obsrt1 = map(sqrt, obs)
Observable{Float64} with 0 listeners. Value:
1.7320508075688772
```

creates an `Observable{Float64}`, which will fail to update if we set `obs[] = 3+4im`.
However,

```jldoctest map!
julia> obsrt2 = map!(sqrt, Observable{Number}(), obs)
Observable{Number} with 0 listeners. Value:
1.7320508075688772
```

can handle any number type for which `sqrt` is defined.
"""
@inline function Base.map!(@nospecialize(f), observable::AbstractObservable, os...; update::Bool=true)
    # note: the @inline prevents de-specialization due to the splatting
    obsfuncs = onany(os...) do args...
        observable[] = Base.invokelatest(f, args...)
    end
    appendinputs!(observable, obsfuncs)
    if update
        observable[] = f(map(to_value, os)...)
    end
    return observable
end

function appendinputs!(observable, obsfuncs)  # latency: separating this from map! allows dropping the specialization on `f`
    if !isdefined(observable, :inputs)
        observable.inputs = obsfuncs
    else
        append!(observable.inputs, obsfuncs)
    end
    return observable
end

"""
    connect!(o1::AbstractObservable, o2::AbstractObservable)

Forwards all updates from `o2` to `o1`.

See also [`Observables.ObservablePair`](@ref).
"""
connect!(o1::AbstractObservable, o2::AbstractObservable) = map!(identity, o1, o2)

"""
    obs = map(f, arg1::AbstractObservable, args...)

Creates a new observable ref `obs` which contains the result of `f` applied to values
extracted from `arg1` and `args` (i.e., `f(arg1[], ...)`.
`arg1` must be an observable ref for dispatch reasons. `args` may contain any number of `Observable` objects.
`f` will be passed the values contained in the refs as the respective argument.
All other objects in `args` are passed as-is.

If you don't need the value of `obs`, and just want to run `f` whenever the
arguments update, use [`on`](@ref) or [`onany`](@ref) instead.

# Example

```jldoctest; setup=:(using Observables)
julia> obs = Observable([1,2,3]);

julia> map(length, obs)
Observable{$Int} with 0 listeners. Value:
3
```
"""
@inline function Base.map(f::F, arg1::AbstractObservable, args...; change_observable=false) where F
    # note: the @inline prevents de-specialization due to the splatting
    obs = Observable(f(arg1[], map(to_value, args)...))
    obs.ignore_equal_values = change_observable
    map!(f, obs, arg1, args...; update=false)
    return obs
end


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

# Look up the source location of `do` block Observable MethodInstances
function methodlist(@nospecialize(ft::Type))
    return Base.MethodList(ft.name.mt)
end

methodlist(mi::Core.MethodInstance) = methodlist(Base.unwrap_unionall(mi.specTypes).parameters[1])
methodlist(obsf::ObserverFunction) = methodlist(obsf.f)
methodlist(@nospecialize(f::Function)) = methodlist(typeof(f))

@deprecate notify! notify

end # module
