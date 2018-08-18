mutable struct Flatten <: AbstractObservable{Any}
    o::AbstractObservable
    inner_id::String
    output::Observable{Any}
    pair::ObservablePair
    function Flatten(o)
        inner_obs = inner_observable(o)
        inner_id = obsid(inner_obs)
        output = Observable{Any}(inner_obs[])
        p = ObservablePair(inner_obs, output)
        n = new(o, inner_id, output, p)
        recursive_connect!(o, n)
        n
    end
end

observe(o::Flatten) = o.output

function Base.iterate(u::Flatten, i = u.o)
    i isa AbstractObservable ? (i, i[]) : nothing
end

function inner_observable(o::AbstractObservable)
    while (x = o[]) isa AbstractObservable
        o = x
    end
    o
end

recursive_connect!(i, f::Flatten) = nothing
function recursive_connect!(i::AbstractObservable, f::Flatten)
    on(i) do val
        if val isa AbstractObservable && i in f
            inner_obs = inner_observable(val)
            if obsid(inner_obs) != f.inner_id
                off(f.pair)
                f[] = inner_obs[]
                f.pair = ObservablePair(inner_obs, f.output)
                f.inner_id = obsid(inner_obs)
            end
            recursive_connect!(val, f)
        end
    end
end

flatten(x) = x
flatten(obs::AbstractObservable) = Flatten(obs)
