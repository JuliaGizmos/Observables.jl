# Observables

Observables are like `Ref`s but you can listen to changes.

```@repl manual
using Observables

observable = Observable(0)

h = on(observable) do val
    println("Got an update: ", val)
end

observable[] = 42
```

To get the value of an observable index it with no arguments
```@repl manual
observable[]
```

To remove a handler use `off` with the return value of `on`:

```@repl manual
off(observable, h)
```

### Async operations

#### Delay an update
```julia
x = Observable(1)
y = map(x) do val
    @async begin
        sleep(0.5)
        return val + 1
    end
end
```

#### Multiply updates
If you want to fire several events on an update (e.g. for interpolating animations), you can use a channel:
```julia
x = Observable(1)
y = map(x) do val
    Channel() do channel
        for i in 1:10
            put!(channel, i + val)
        end
    end
end
```

#### The same works for constructing observables

```julia
Observable(@async begin
    sleep(0.5)
    return 1 + 1
end)
Observable(Channel() do channel
    for i in 1:10
        put!(channel, i + 1)
    end
end)
```

### How is it different from Reactive.jl?

The main difference is `Signal`s are manipulated mostly by converting one signal to another. For example, with signals, you can construct a changing UI by creating a `Signal` of UI objects and rendering them as the signal changes. On the other hand, you can use an Observable both as an input and an output. You can arbitrarily attach outputs to inputs allowing structuring code in a [signals-and-slots](http://doc.qt.io/qt-4.8/signalsandslots.html) kind of pattern.

Another difference is Observables are synchronous, Signals are asynchronous. Observables may be better suited for an imperative style of programming.

## API

### Public

```@autodocs
Modules = [Observables]
Private = false
```

### Internal

```@autodocs
Modules = [Observables]
Public = false
```
