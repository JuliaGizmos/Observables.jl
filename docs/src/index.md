# Observables

Observables are like `Ref`s:

```@repl manual
using Observables

observable = Observable(0)

observable[]
```

But unlike `Ref`s,  but you can listen for changes:

```@repl manual
obs_func = on(observable) do val
    println("Got an update: ", val)
end

observable[] = 42
```

To remove a handler use `off` with the return value of `on`:

```@repl manual
off(obs_func)
```

### Weak Connections

If you use `on` with `weak = true`, the connection will be removed when
the return value of `on` is garbage collected.
This can make it easier to clean up connections that are not used anymore.


```julia
obs_func = on(observable, weak = true) do val
    println("Got an update: ", val)
end
# as long as obs_func is reachable the connection will stay

obs_func = nothing
# now garbage collection can at any time clear the connection
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

### Extensions of Base methods or internal methods

```@autodocs
Modules = [Observables]
Public = false
```
