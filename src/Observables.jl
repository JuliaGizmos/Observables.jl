module Observables

export Observable, on, off, onany

"""
Like a `Ref` but updates can be watched by adding a handler using `on`.

# Example:

```julia
x = Observable(0)

# handle changes:
on(println, x)

# set the value:
x[] = 2

# get the value:
x[]
```
"""
type Observable{T}
    val::T
    listeners::Vector
end
(::Type{Observable{T}}){T}(val) = Observable{T}(val, Any[])
Observable{T}(val::T) = Observable{T}(val)

"""
    on(f, oref::Observable)

Adds function `f` as listener to `oref`. Whenever `oref`'s value
is set via `oref[] = val` `f` is called with `val`.
"""
function on(f, ob::Observable)
    push!(ob.listeners, f)
    nothing
end

"""
    off(oref::Observable, f)

Removes `f` from listeners of `oref`.
"""
function off(ob::Observable, f)
    for i in 1:length(ob.listeners)
        if f === ob.listeners[i]
            deleteat!(ob.listeners, i)
            return
        end
    end
    throw(KeyError(f))
end

"""
    oref[] = val

Updates the value of an `Observable` to `val` and call its listeners.
"""
function Base.setindex!(ob::Observable, val)
    ob.val = val
    for f in ob.listeners
        f(val)
    end
end

"""
    oref[]

Returns the current value of `oref`.
"""
Base.getindex(ob::Observable) = ob.val


### Utilities

_val(x::Observable) = x[]
_val(x) = x

"""
    onany(f, args...)

Calls `f` on updates to any observable refs in `args`.
`args` may contain any number of `Observable` objects.
`f` will be passed the values contained in the refs as the respective argument.
All other objects in `args` are passed as-is.
"""
function onany(f, objs...)
    observs = filter(x->isa(x, Observable), objs)
    g(_) = f(map(_val, objs)...)
    for o in observs
        on(g, o)
    end
end

"""
    map!(f, ob::Observable, args...)

Updates `ob` with the result of calling `f` with values extracted from args.
`args` may contain any number of `Observable` objects.
`f` will be passed the values contained in the refs as the respective argument.
All other objects in `args` are passed as-is.
"""
function Base.map!(f, ob::Observable, obs...)
    onany(obs...) do val...
        ob[] = f(val...)
    end
    ob
end

"""
    map(f, ob::Observable, args...)

Creates a new observable ref which contains the result of `f` applied to
values extracted from args. The second argument `ob` must be an observable ref for
dispatch reasons. `args` may contain any number of `Observable` objects.
`f` will be passed the values contained in the refs as the respective argument.
All other objects in `args` are passed as-is.
"""
function Base.map(f, ob::Observable, obs...; init=f(ob[], map(_val, obs)...))
    map!(f, Observable(init), ob, obs...)
end

# TODO: overload broadcast on v0.6

end # module
