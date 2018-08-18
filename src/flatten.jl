struct Nested{T}
    o::T
end

Base.iterate(u::Nested, i = u.o) = i isa AbstractObservable ? (i, i[]) : nothing

mutable struct Flatten <: AbstractObservable{Any}
    o::AbstractObservable
    list::Vector{Tuple{AbstractObservable, Function}}
    inner_id::String
    output::Observable{Any}
    pair::ObservablePair
    function Flatten(o)
        inner_obs = foldl((x,y)->y, Nested(o))
        inner_id = obsid(inner_obs)
        output = Observable{Any}(inner_obs[])
        p = ObservablePair(inner_obs, output)
        n = new(o, Tuple{AbstractObservable, Function}[], inner_id, output, p)
        for i in Nested(o)
            f = updater(i, n)
            on(f, i)
            push!(n.list, (i, f))
        end
        n
    end
end

flatten(x) = x
flatten(obs::AbstractObservable) = observe(Flatten(obs))

observe(o::Flatten) = o.output

function updater(i, f::Flatten)
    function (val)
        ind = findfirst(t -> obsid(t[1]) == obsid(i), f.list)
        if ind !== nothing
            for ii in length(f.list):-1:(ind+1)
                obs, func = pop!(f.list)
                off(obs, func)
            end
            for outer i in Nested(val)
                func = updater(i, f)
                on(func, i)
                push!(f.list, (i, func))
            end
            if obsid(i) != f.inner_id
                off(f.pair)
                f[] = i[]
                f.pair = ObservablePair(i, f.output)
                f.inner_id = obsid(i)
            end
        end
    end
end
