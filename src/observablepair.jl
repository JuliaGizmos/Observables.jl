"""
    ObservablePair(first, second)

Two observables trigger each other, but only in one direction
as otherwise there will be an infinite loop of updates
"""
struct ObservablePair{S, T} <: AbstractObservable{T}
    first::AbstractObservable{S}
    second::AbstractObservable{T}
    f
    g
    links::Tuple{ObserverFunction,ObserverFunction}

    function ObservablePair(first::AbstractObservable{S}, second::AbstractObservable{T}; f = identity, g = identity) where {S, T}

        # the two observables should trigger each other, but only in one direction
        # as otherwise there will be an infinite loop of updates
        done = Ref(false)
        link1 = on(first) do val
            if !done[]
                done[] = true
                second[] = f(val)
                done[] = false
            end
        end
        link2 = on(second) do val
            if !done[]
                done[] = true
                first[] = g(val)
                done[] = false
            end
        end

        new{S, T}(first, second, f, g, (link1, link2))
    end
end

ObservablePair(first::AbstractObservable; f = identity, g = identity) =
    ObservablePair(first, Observable{Any}(f(first[])); f = f, g = g)

observe(o::ObservablePair) = o.second

function off(o::ObservablePair)
    for i in 1:2
        off(o[i], o.links[i])
    end
end

Base.iterate(p::ObservablePair, i=1) = i > 2 ? nothing : (getfield(p, i), i + 1)
Base.getindex(p::ObservablePair, i::Int) = getfield(p, i)
Base.firstindex(p::ObservablePair) = 1
Base.lastindex(p::ObservablePair) = 2
Base.length(p::ObservablePair) = 2
Base.first(p::ObservablePair) = p.first
Base.last(p::ObservablePair) = p.second
