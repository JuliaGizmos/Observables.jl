"""
`throttle(dt, input::AbstractObservable)`

Throttle a signal to update at most once every `dt` seconds. The throttled signal holds
the last update of the `input` signal during each `dt` second time window.
"""
function throttle(dt, obs::AbstractObservable{T}) where {T}
    throttled = Observable{T}(obs[])
    updatable = Observable(true)
    set_throttled(val) = (throttled[] != val) && (throttled[] = val; updatable[] = false)
    on(updatable) do val
        val ? set_throttled(obs[]) : Timer(t -> updatable[] = true, dt)
    end
    on(obs) do val
        updatable[] && set_throttled(val)
    end
    throttled
end
