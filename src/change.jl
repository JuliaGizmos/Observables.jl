
"""
    obs = ChangeObservable(val)
    obs = ChangeObservable{T}(val)

Like an `Observable`, but only updates watchers when the value changes
"""
struct ChangeObservable{T} <: AbstractObservable{T}
    obs::AbstractObservable{T}
    change::AbstractObservable{T}
    function ChangeObservable{T}(x) where {T}
        obs = Observable{T}(x)
        change = observe_changes(obs)
        return new{T}(obs, change)
    end
end
ChangeObservable(val::T) where {T} = ChangeObservable{T}(val)

Base.close(co::ChangeObservable) = empty!(listeners(co.change))

# Functions on the input side that use the value observable
Base.setindex!(co::ChangeObservable, val) = Base.setindex!(co.obs, val)
appendinputs!(co::ChangeObservable, obsfuncs) = appendinputs!(co.obs, obsfuncs)

# Functions on the change side that use the change observable
Base.getindex(co::ChangeObservable) = Base.getindex(co.change)
to_value(co::ChangeObservable) = to_value(co.change)
observe(co::ChangeObservable) = observe(co.change)
listeners(co::ChangeObservable) = listeners(co.change)
on(@nospecialize(f), co::ChangeObservable; kwargs...) = on(f, co.change; kwargs...)
off(co::ChangeObservable, @nospecialize(f)) = off(co.change, f)
off(co::ChangeObservable, f::ObserverFunction) = off(co.change, f)

