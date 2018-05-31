"""
`throttle(dt, input::Observable)`

Throttle a signal to update at most once every `dt` seconds. The throttled signal holds
the last update of the `input` signal during each `dt` second time window.
"""
function throttle(dt, obs::Observable{T}) where {T}
    throttled = Observable{T}(obs[])
    @async while true
        sleep(dt)
        (obs[] != throttled[]) && (throttled[] = obs[])
    end
    throttled
end
