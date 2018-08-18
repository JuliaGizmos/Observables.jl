struct ObservablePair{S, T} <: AbstractObservable{T}
    first::AbstractObservable{S}
    second::AbstractObservable{T}
    f
    g
    excluded::Vector{Function}
    function ObservablePair(first::AbstractObservable{S}, second::AbstractObservable{T}; f = identity, g = identity) where {S, T}
        excluded = Function[]
        first2second = on(first) do val
            setindex!(second, f(val), notify = !in(excluded))
        end
        push!(excluded, first2second)
        second2first = on(second) do val
            setindex!(first, g(val), notify = !in(excluded))
        end
        push!(excluded, second2first)
        new{S, T}(first, second, f, g, excluded)
    end
end

ObservablePair(first::AbstractObservable; f = identity, g = identity) =
    ObservablePair(first, Observable{Any}(f(first[])); f = f, g = g)

observe(o::ObservablePair) = o.second

function off(o::ObservablePair)
    for i in 1:2
        off(o[i], o.excluded[i])
    end
end

Base.iterate(p::ObservablePair, i=1) = i > 2 ? nothing : (getfield(p, i), i + 1)
Base.getindex(p::ObservablePair, i::Int) = getfield(p, i)
Base.firstindex(p::ObservablePair) = 1
Base.lastindex(p::ObservablePair) = 2
Base.length(p::ObservablePair) = 2
Base.first(p::ObservablePair) = p.first
Base.last(p::ObservablePair) = p.second
