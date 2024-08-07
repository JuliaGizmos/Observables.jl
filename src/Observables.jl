module Observables

export Observable, on, off, onany, connect!, obsid, async_latest, throttle
export Consume, ObserverFunction, AbstractObservable

import Base.Iterators.filter

if isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@optlevel"))
    @eval Base.Experimental.@optlevel 0
end

# @nospecialize "blocks" codegen but not necessarily inference. This forces inference
# to drop specific information about an argument.
if isdefined(Base, :inferencebarrier)
    const inferencebarrier = Base.inferencebarrier
else
    inferencebarrier(x) = Ref{Any}(x)[]
end

abstract type AbstractObservable{T} end

const addhandler_callbacks = []
const removehandler_callbacks = []

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
    f::Any
    observable::AbstractObservable
    weak::Bool

    function ObserverFunction(@nospecialize(f), @nospecialize(observable::AbstractObservable), weak::Bool)
        obsfunc = new(f, observable, weak)
        # If the weak flag is set, deregister the function f from the observable
        # storing it in its listeners once the ObserverFunction is garbage collected.
        # This should free all resources associated with f unless there
        # is another reference to it somewhere else.
        weak && finalizer(off, obsfunc)
        return obsfunc
    end
end


const OBSID_COUNTER = Base.Threads.Atomic{UInt64}(UInt64(0))

"""
    obs = Observable(val; ignore_equal_values=false)
    obs = Observable{T}(val; ignore_equal_values=false)

Like a `Ref`, but updates can be watched by adding a handler using [`on`](@ref) or [`map`](@ref).
Set `ignore_equal_values=true` to not trigger an event for `observable[] = new_value` if `isequal(observable[], new_value)`.
"""
mutable struct Observable{T} <: AbstractObservable{T}
    listeners::Vector{Pair{Int, Any}}
    inputs::Vector{ObserverFunction}  # for map!ed Observables
    ignore_equal_values::Bool
    id::UInt64
    val::T
    function Observable{T}(; ignore_equal_values::Bool=false) where {T}
        Base.Threads.atomic_add!(OBSID_COUNTER, UInt64(1))
        return new{T}(Pair{Int,Any}[], [], ignore_equal_values, OBSID_COUNTER[])
    end
    function Observable{T}(@nospecialize(val); ignore_equal_values::Bool=false) where {T}
        Base.Threads.atomic_add!(OBSID_COUNTER, UInt64(1))
        return new{T}(Pair{Int,Any}[], [], ignore_equal_values, OBSID_COUNTER[], val)
    end
end

"""
    obsid(observable::Observable)

Gets a unique id for an observable.
"""
obsid(observable::Observable) = string(getfield(observable, :id))
obsid(obs::AbstractObservable) = obsid(observe(obs))

function Base.getproperty(obs::Observable, field::Symbol)
    if field === :id
        return obsid(obs)
    else
        return getfield(obs, field)
    end
end

Observable(val::T; ignore_equal_values::Bool=false) where {T} = Observable{T}(val; ignore_equal_values)

Base.eltype(::AbstractObservable{T}) where {T} = T

function observe(obs::AbstractObservable)
    error("observe not defined for AbstractObservable $(typeof(obs))")
end
observe(x::Observable) = x
Base.getindex(obs::AbstractObservable) = getindex(observe(obs))
Base.setindex!(obs::AbstractObservable, val) = setindex!(observe(obs), val)
listeners(obs::AbstractObservable) = listeners(observe(obs))
listeners(observable::Observable) = observable.listeners

"""
    observable[] = val

Updates the value of an `Observable` to `val` and call its listeners.
"""
function Base.setindex!(@nospecialize(observable::Observable), @nospecialize(val))
    if observable.ignore_equal_values
        isequal(observable.val, val) && return
    end
    observable.val = val
    return notify(observable)
end

# For external packages that don't want to access an internal field
setexcludinghandlers!(obs::AbstractObservable, val) = observe(obs).val = val

"""
    observable[]

Returns the current value of `observable`.
"""
Base.getindex(observable::Observable) = observable.val

### Utilities

"""
    to_value(x::Union{Any, AbstractObservable})
Extracts the value of an observable, and returns the object if it's not an observable!
"""
to_value(x) = isa(x, AbstractObservable) ? x[] : x  # noninferrable dispatch is faster if there is only one Method

struct SetindexCallback
    obs::Observable
end

(sc::SetindexCallback)(@nospecialize(x)) = (sc.obs[] = x)


# Optimized version of Base.searchsortedlast (optimized for our use case of pairs)
function pair_searchsortedlast(values::Vector{Pair{Int, Any}}, prio::Int)::Int
    u = 1
    lo = 0
    hi = length(values) + u
    @inbounds while lo < hi - u
        m = lo + ((hi - lo) >>> 0x01) # Base.midpoint, not available in 1.6
        if isless(values[m][1], prio)
            hi = m
        else
            lo = m
        end
    end
    return lo
end

function register_callback(@nospecialize(observable), priority::Int, @nospecialize(f))
    ls = listeners(observable)::Vector{Pair{Int, Any}}
    idx = pair_searchsortedlast(ls, priority)
    p = Pair{Int, Any}(priority, f) # faster than priority => f because of convert
    insert!(ls, idx + 1, p)
    return
end

function Base.convert(::Type{P}, observable::AbstractObservable) where P <: Observable
    result = P(observable[])
    register_callback(observable, 0, SetindexCallback(result))
    return result
end

function Base.copy(observable::Observable{T}) where T
    result = Observable{T}(observable[])
    register_callback(observable, 0, SetindexCallback(result))
    return result
end

Base.convert(::Type{T}, x::T) where {T<:Observable} = x  # resolves ambiguity with convert(::Type{T}, x::T) in base/essentials.jl
Base.convert(::Type{T}, x) where {T<:Observable} = T(x)
Base.convert(::Type{Observable{Any}}, x::AbstractObservable{Any}) = x
Base.convert(::Type{Observables.Observable{Any}}, x::Observables.Observable{Any}) = x

struct Consume
    x::Bool
end
Consume() = Consume(true)

"""
    notify(observable::AbstractObservable)

Update all listeners of `observable`.
Returns true if an event got consumed before notifying every listener.
"""
function Base.notify(@nospecialize(observable::AbstractObservable))
    val = observable[]
    for (_, f) in listeners(observable)::Vector{Pair{Int, Any}}
        result = Base.invokelatest(f, val)
        if result isa Consume && result.x
            # stop calling callbacks if event got consumed
            return true
        end
    end
    return false
end

function print_value(io::IO, x::Observable{T}; print_listeners=false) where T
    print(io, "Observable")
    real_eltype = T
    if isdefined(x, :val)
        real_eltype = typeof(x[])
        if T === typeof(x[])
            # eltype isn't special and matches observable type so no need to print it
            print(io, "(")
        else
            print(io, "{$T}(")
        end
        show(io, x.val)
    else
        print(io, "{$T}(#undef")
    end
    print(io, ")")
    if print_listeners
        ls = listeners(x)
        max_listeners = 20
        println(io)
        # Truncation of too many listeners:
        if length(ls) <= max_listeners # we show the whole thing
            for (prio, callback) in ls
                print(io, "    ", prio, " => ")
                show_callback(io, callback, Tuple{real_eltype})
                println(io)
            end
        else # we cut out the middle if we have too many listeners
            half = max_listeners ÷ 2
            for (prio, callback) in view(ls, 1:half)
                print(io, "    ", prio, " => ")
                show_callback(io, callback, Tuple{real_eltype})
                println(io)
            end
            println(io, "\n    ...")
            last_n = length(ls) - half
            for (prio, callback) in view(ls, last_n:length(ls))
                print(io, "    ", prio, " => ")
                show_callback(io, callback, Tuple{real_eltype})
                println(io)
            end
        end
    end
end

function Base.show(io::IO, x::Observable{T}) where T
    print_value(io, x)
end

function Base.show(io::IO, ::MIME"text/plain", x::Observable{T}) where T
    print_value(io, x; print_listeners=!get(io, :compact, false))
    return
end

function show_callback(io::IO, @nospecialize(f), @nospecialize(arg_types))
    meths = methods(f, arg_types)
    if isempty(meths)
        show(io, f)
    else
        m = first(methods(f, arg_types))
        show(io, m)
    end
    return
end

Base.show(io::IO, ::MIME"application/prs.juno.inline", x::Observable) = x


function Base.show(io::IO, obsf::ObserverFunction)
    io = IOContext(io, :compact => true)
    showdflt(io, @nospecialize(f), obs) = print(io, "ObserverFunction `", f, "` operating on ", obs)

    nm = string(obsf.f) # 1.6 doesn't support nameof(some_struct), and also nameof(f) == Symbol(string(f))?

    if !occursin('#', nm)
        showdflt(io, obsf.f, obsf.observable)
    else
        mths = methods(obsf.f)
        if length(mths) == 1
            m = first(mths)
            print(io, "ObserverFunction defined at ", m.file, ":", m.line, " operating on ", obsf.observable)
        else
            showdflt(io, obsf.f, obsf.observable)
        end
    end
end
Base.show(io::IO, ::MIME"text/plain", obsf::ObserverFunction) = show(io, obsf)
Base.print(io::IO, obsf::ObserverFunction) = show(io, obsf)   # Base.print is specialized for ::Function


"""
    on(f, observable::AbstractObservable; weak = false, priority=0, update=false)::ObserverFunction

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

```julia
julia> obs = Observable(0)
Observable(0)

julia> on(obs) do val
           println("current value is ", val)
       end
ObserverFunction defined at REPL[17]:2 operating on Observable(0)
julia> obs[] = 5;
current value is 5
```

One can also give the callback a priority, to enable always calling a specific callback before/after others, independent of the order of registration.
The callback with the highest priority gets called first, the default is zero, and the whole range of Int can be used.
So one can do:

```julia
julia> obs = Observable(0)
julia> on(obs; priority=-1) do x
           println("Hi from first added")
       end
julia> on(obs) do x
           println("Hi from second added")
       end
julia> obs[] = 2
Hi from second added
Hi from first added
```

If you set `update=true`, on will call f(obs[]) immediately:
```julia
julia> on(Observable(1); update=true) do x
    println("hi")
end
hi
```

"""
function on(@nospecialize(f), @nospecialize(observable::AbstractObservable); weak::Bool = false, priority::Int = 0, update::Bool = false)::ObserverFunction
    register_callback(observable, priority, f)
    #
    for g in addhandler_callbacks
        g(f, observable)
    end

    update && f(observable[])
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
function off(@nospecialize(observable::AbstractObservable), @nospecialize(f))
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

function off(@nospecialize(observable::AbstractObservable), obsfunc::ObserverFunction)
    # remove the function inside obsfunc as usual
    off(observable, obsfunc.f)
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

struct OnAny <: Function
    f::Any
    args::Any
end

function (onany::OnAny)(@nospecialize(value))
    return Base.invokelatest(onany.f, map(to_value, onany.args)...)
end

function show_callback(io::IO, onany::OnAny, @nospecialize(argtype))
    print(io, "onany(")
    show_callback(io, onany.f, eltype.(onany.args))
    print(io, ")")
end

struct MapCallback <: Function
    f::Any
    result::Observable
    args::Any
end

function (mc::MapCallback)(@nospecialize(value))
    mc.result[] = Base.invokelatest(mc.f, map(to_value, mc.args)...)
    return
end

function show_callback(io::IO, mc::MapCallback, @nospecialize(argtype))
    print(io, "map(")
    show_callback(io, mc.f, typeof(mc.args))
    print(io, ")")
end


"""
    clear(obs::Observable)

Empties all listeners and clears all inputs, removing the observable from all interactions with it's parent.
"""
function clear(@nospecialize(obs::Observable))
    for input in obs.inputs
        off(input)
    end
    empty!(obs.listeners)
end

"""
    onany(f, args...; weak::Bool = false, priority::Int = 0, update::Bool = false)

Calls `f` on updates to any observable refs in `args`.
`args` may contain any number of `Observable` objects.
`f` will be passed the values contained in the refs as the respective argument.
All other objects in `args` are passed as-is.

See also: [`on`](@ref).
"""
function onany(f, args...; weak::Bool=false, priority::Int=0, update::Bool = false)
    callback = OnAny(f, args)
    obsfuncs = ObserverFunction[]
    for observable in args
        if observable isa AbstractObservable
            obsfunc = on(callback, observable; weak=weak, priority=priority)
            push!(obsfuncs, obsfunc)
        end
    end
    update && callback(nothing)
    return obsfuncs
end

"""
    map!(f, result::AbstractObservable, args...; update::Bool=true)

Updates `result` with the result of calling `f` with values extracted from args.
`args` may contain any number of `Observable` objects.
`f` will be passed the values contained in the refs as the respective argument.
All other objects in `args` are passed as-is.

By default `result` gets updated immediately, but this can be suppressed by specifying `update=false`.

# Example

We'll create an observable that can hold an arbitrary number:

```jldoctest map!; setup=:(using Observables)
julia> obs = Observable{Number}(3)
Observable{Number}(3)
```

Now,

```jldoctest map!
julia> obsrt1 = map(sqrt, obs)
Observable(1.7320508075688772)
```

creates an `Observable{Float64}`, which will fail to update if we set `obs[] = 3+4im`.
However,

```jldoctest map!
julia> obsrt2 = map!(sqrt, Observable{Number}(), obs)
Observable{Number}(1.7320508075688772)
```

can handle any number type for which `sqrt` is defined.
"""
@inline function Base.map!(@nospecialize(f), result::AbstractObservable, os...; update::Bool=true, priority::Int = 0)
    # note: the @inline prevents de-specialization due to the splatting
    callback = MapCallback(f, result, os)
    obsfuncs = ObserverFunction[]
    for o in os
        if o isa AbstractObservable
            obsfunc = on(callback, o, priority = priority)
            push!(obsfuncs, obsfunc)
        end
    end
    appendinputs!(result, obsfuncs)
    update && callback(nothing)
    return result
end

function appendinputs!(@nospecialize(observable), obsfuncs::Vector{ObserverFunction})  # latency: separating this from map! allows dropping the specialization on `f`
    append!(observable.inputs, obsfuncs)
    return observable
end

"""
    connect!(o1::AbstractObservable, o2::AbstractObservable)

Forwards all updates from `o2` to `o1`.

See also [`Observables.ObservablePair`](@ref).
"""
connect!(o1::AbstractObservable, o2::AbstractObservable) = on(x-> o1[] = x, o2; update=true)

"""
    obs = map(f, arg1::AbstractObservable, args...; ignore_equal_values=false, out_type=:first_eval)

Creates a new observable `obs` which contains the result of `f` applied to values
extracted from `arg1` and `args` (i.e., `f(arg1[], ...)`.
`arg1` must be an observable for dispatch reasons. `args` may contain any number of `Observable` objects.
`f` will be passed the values contained in the observables as the respective argument.
All other objects in `args` are passed as-is.

If you don't need the value of `obs`, and just want to run `f` whenever the
arguments update, use [`on`](@ref) or [`onany`](@ref) instead.

# Example

```jldoctest; setup=:(using Observables)
julia> obs = Observable([1,2,3]);

julia> map(length, obs)
Observable(3)
```

# Specifying the element type

The element type (eltype) of the new observable `obs` is determined by the `out_type` kwarg. If
`out_type = :first_eval` (default), then it'll be whatever type is returned the first time `f` is
called.

```jldoctest; setup=:(using Observables)
julia> o1 = Observable{Union{Int, Float64}}(1);

julia> eltype(map(x -> x + 1, o1))
Int
```

If `out_type = :infer`, we'll use type inference to determine the eltype:
```jldoctest; setup=:(using Observables; o1 = Observable{Union{Int, Float64}}(1))
julia> eltype(map(x -> x + 1, o1; out_type=:infer))
Union{Int, Float64}
```

If you use the `:infer` option, then the eltype of `obs` should be considered an implementation
detail that cannot be relied upon and may end up returning `Any` depending on opaque compiler
heuristics.

Finally, if `out_type` isa `Type`, then that type is the unconditional `eltype` of `obs`

```jldoctest setup=:(using Observables; o1 = Observable{Union{Int, Float64}}(1))
julia> eltype(map(x -> x + 1, o1; out_type=Real))
Real
```
"""
@inline function Base.map(f::F, arg1::AbstractObservable, args...; ignore_equal_values::Bool=false, priority::Int = 0, out_type=:first_eval) where F
    if out_type === :first_eval
        Obs = Observable
    elseif out_type === :infer
        RT = Core.Compiler.return_type(f, Tuple{eltype(arg1), eltype.(args)...})
        Obs = Observable{RT}
    elseif out_type isa Type
        Obs = Observable{out_type}
    else
        msg = "Got an invalid input for the out_type keyword argument, expected either a type, `:first_eval`, or `:infer`, got " * repr(out_type)
        error(ArgumentError(msg))
    end
    # note: the @inline prevents de-specialization due to the splatting
    obs = Obs(f(arg1[], map(to_value, args)...); ignore_equal_values=ignore_equal_values)
    map!(f, obs, arg1, args...; update=false, priority = priority)
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

precompile(Core.convert, (Type{Observable{Any}}, Observable{Any}))
precompile(Base.copy, (Type{Observable{Any}},))

end # module
