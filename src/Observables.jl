module Observables

export Observable, on, off, onany, connect!

if isdefined(Base, :Iterators) && isdefined(Base.Iterators, :filter)
    import Base.Iterators.filter
else
    import Base.filter
end

"""
Like a `Ref` but updates can be watched by adding a handler using `on`.
"""
type Observable{T}
    val::T
    listeners::Vector
end
(::Type{Observable{T}}){T}(val) = Observable{T}(val, Any[])
Observable{T}(val::T) = Observable{T}(val)

"""
    on(f, o::Observable)

Adds function `f` as listener to `o`. Whenever `o`'s value
is set via `o[] = val` `f` is called with `val`.
"""
function on(f, o::Observable)
    push!(o.listeners, f)
    f
end

"""
    off(o::Observable, f)

Removes `f` from listeners of `o`.
"""
function off(o::Observable, f)
    for i in 1:length(o.listeners)
        if f === o.listeners[i]
            deleteat!(o.listeners, i)
            return
        end
    end
    throw(KeyError(f))
end

"""
    o[] = val

Updates the value of an `Observable` to `val` and call its listeners.
"""
function Base.setindex!(o::Observable, val)
    o.val = val
    for f in o.listeners
        f(val)
    end
end

function setexcludinghandlers(o::Observable, val, pred=x->true)
    o.val = val
    for f in o.listeners
        if pred(f)
            f(val)
        end
    end
end

"""
    o[]

Returns the current value of `o`.
"""
Base.getindex(o::Observable) = o.val


### Utilities

_val(o::Observable) = o[]
_val(x) = x

"""
    onany(f, args...)

Calls `f` on updates to any oservable refs in `args`.
`args` may contain any number of `Observable` ojects.
`f` will be passed the values contained in the refs as the respective argument.
All other ojects in `args` are passed as-is.
"""
function onany(f, os...)
    oservs = filter(x->isa(x, Observable), os)
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
function Base.map!(f, o::Observable, os...)
    onany(os...) do val...
        o[] = f(val...)
    end
    o
end

"""
    connect!(o1::Observable, o2::Observable)

Forward all updates to `o1` to `o2`
"""
connect!(o1::Observable, o2::Observable) = map!(identity, o2, o1)

"""
    map(f, o::Observable, args...)

Creates a new oservable ref which contains the result of `f` applied to
values extracted from args. The second argument `o` must be an oservable ref for
dispatch reasons. `args` may contain any number of `Observable` ojects.
`f` will be passed the values contained in the refs as the respective argument.
All other ojects in `args` are passed as-is.
"""
function Base.map(f, o::Observable, os...; init=f(o[], map(_val, os)...))
    map!(f, Observable(init), o, os...)
end

Base.eltype{T}(::Observable{T}) = T

# TODO: overload broadcast on v0.6

end # module
