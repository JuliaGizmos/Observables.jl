mutable struct Unwrap <: AbstractObservable{AbstractObservable}
    o::AbstractObservable
    obs_inner::Observable{AbstractObservable}
    pair::Union{ObservablePair, Nothing}
    function Unwrap(o, obs_inner=Observable{AbstractObservable}(inner_observable(o)))
        n = new(o, obs_inner, nothing)
        recursive_connect!(o, n)
        n
    end
end

observe(o::Unwrap) = o.obs_inner

function Base.iterate(u::Unwrap, i = u.o)
    i isa AbstractObservable ? (i, i[]) : nothing
end

function inner_observable(o::AbstractObservable)
    while (x = o[]) isa AbstractObservable
        o = x
    end
    o
end

recursive_connect!(i, f::Unwrap) = nothing
function recursive_connect!(i::AbstractObservable, f::Unwrap)
    on(i) do val
        if val isa AbstractObservable && i in f
            inner = inner_observable(val)
            (obsid(inner) != obsid(f[])) && (f[] = inner)
            recursive_connect!(val, f)
        end
    end
end

flatten(x) = x
flatten(obs::AbstractObservable) = flatten(Unwrap(obs))
function flatten(u::Unwrap)
    obs1 = u[]
    obs2 = Observable{Any}(obs1[])
    u.pair = ObservablePair(obs1, obs2)
    on(u) do val
        off(u.pair)
        obs2[] = val[]
        u.pair = ObservablePair(val, obs2)
    end
    obs2
end
