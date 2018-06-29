module Observables

export Observable, on, off, onany, connect!, obsid, async_latest

if isdefined(Base, :Iterators) && isdefined(Base.Iterators, :filter)
    import Base.Iterators.filter
else
    import Base.filter
end

const addhandler_callbacks = []
const removehandler_callbacks = []

"""
Like a `Ref` but updates can be watched by adding a handler using `on`.
"""
type Observable{T}
    id::String
    val::T
    listeners::Vector
end
(::Type{Observable{T}}){T}(val) = Observable{T}(newid(), val, Any[])
Observable{T}(val::T) = Observable{T}(val)

let count=0
    global newid
    function newid(prefix="ob_")
        string(prefix, lpad(count += 1, 2, "0"))
    end
end

"""
    on(f, o::Observable)

Adds function `f` as listener to `o`. Whenever `o`'s value
is set via `o[] = val` `f` is called with `val`.
"""
function on(f, o::Observable)
    push!(o.listeners, f)
    for g in addhandler_callbacks
        g(f, o)
    end
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

obsid(o::Observable) = o.id

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

"""
`async_latest(o::Observable, n=1)`

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
function async_latest(input::Observable{T}, n=1) where T
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
            unshift!(buffer, val)
        end
        unlock(lck)
        notify(cond)
    end

    output
end

# TODO: overload broadcast on v0.6

end # module
