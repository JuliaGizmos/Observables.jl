# Observables

Observables are like `Ref`s:

```@repl manual
using Observables

observable = Observable(0)

observable[]
```

But unlike `Ref`s, you can listen for changes:

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

### Priority

One can also give the callback a priority, to enable always calling a specific callback before/after others, independent of the order of registration.
So one can do:

```julia
obs = Observable(0)
on(obs; priority=-1) do x
    println("Hi from first added")
end
on(obs) do x
    println("Hi from second added")
end
obs[] = 2
Hi from second added
Hi from first added
```
Without the priority, the printing order would be the other way around.
One can also return `Consume(true/false)`, to consume an event and stop any later callback from getting called.

```julia
obs = Observable(0)
on(obs) do x
    if x == 1
        println("stop calling callbacks after me!")
        return Consume(true)
    else
        println("Do not consume!")
    end
end
on(obs) do x
    println("I get called")
end
obs[] = 2
Do not consume!
I get called
obs[] = 1
stop calling callbacks after me!
```

The first one could of course also be written as:
```julia
on(obs) do x
    return Consume(x == 1)
end
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
