var documenterSearchIndex = {"docs": [

{
    "location": "index.html#",
    "page": "Home",
    "title": "Home",
    "category": "page",
    "text": ""
},

{
    "location": "index.html#Observables-1",
    "page": "Home",
    "title": "Observables",
    "category": "section",
    "text": "Observables are like Refs but you can listen to changes.observable = Observable(0)\n\nh = on(observable) do val\n    println(\"Got an update: \", val)\nend\n\nobservable[] = 42To get the value of an observable index it with no argumentsobservable[]To remove a handler use off with the return value of on:off(observable, h)"
},

{
    "location": "index.html#How-is-it-different-from-Reactive.jl?-1",
    "page": "Home",
    "title": "How is it different from Reactive.jl?",
    "category": "section",
    "text": "The main difference is Signals are manipulated mostly by converting one signal to another. For example, with signals, you can construct a changing UI by creating a Signal of UI objects and rendering them as the signal changes. On the other hand, you can use an Observable both as an input and an output. You can arbitrarily attach outputs to inputs allowing structuring code in a signals-and-slots kind of pattern.Another difference is Observables are synchronous, Signals are asynchronous. Observables may be better suited for an imperative style of programming."
},

{
    "location": "index.html#Observables.Observable",
    "page": "Home",
    "title": "Observables.Observable",
    "category": "Type",
    "text": "Like a Ref but updates can be watched by adding a handler using on.\n\n\n\n"
},

{
    "location": "index.html#Observables.on-Tuple{Any,Observables.Observable}",
    "page": "Home",
    "title": "Observables.on",
    "category": "Method",
    "text": "on(f, o::Observable)\n\nAdds function f as listener to o. Whenever o's value is set via o[] = val f is called with val.\n\n\n\n"
},

{
    "location": "index.html#Observables.off-Tuple{Observables.Observable,Any}",
    "page": "Home",
    "title": "Observables.off",
    "category": "Method",
    "text": "off(o::Observable, f)\n\nRemoves f from listeners of o.\n\n\n\n"
},

{
    "location": "index.html#Base.setindex!-Tuple{Observables.Observable,Any}",
    "page": "Home",
    "title": "Base.setindex!",
    "category": "Method",
    "text": "o[] = val\n\nUpdates the value of an Observable to val and call its listeners.\n\n\n\n"
},

{
    "location": "index.html#Base.getindex-Tuple{Observables.Observable}",
    "page": "Home",
    "title": "Base.getindex",
    "category": "Method",
    "text": "o[]\n\nReturns the current value of o.\n\n\n\n"
},

{
    "location": "index.html#Observables.onany-Tuple{Any,Vararg{Any,N} where N}",
    "page": "Home",
    "title": "Observables.onany",
    "category": "Method",
    "text": "onany(f, args...)\n\nCalls f on updates to any oservable refs in args. args may contain any number of Observable ojects. f will be passed the values contained in the refs as the respective argument. All other ojects in args are passed as-is.\n\n\n\n"
},

{
    "location": "index.html#Base.map!-Tuple{Any,Observables.Observable,Vararg{Any,N} where N}",
    "page": "Home",
    "title": "Base.map!",
    "category": "Method",
    "text": "map!(f, o::Observable, args...)\n\nUpdates o with the result of calling f with values extracted from args. args may contain any number of Observable ojects. f will be passed the values contained in the refs as the respective argument. All other ojects in args are passed as-is.\n\n\n\n"
},

{
    "location": "index.html#Observables.connect!-Tuple{Observables.Observable,Observables.Observable}",
    "page": "Home",
    "title": "Observables.connect!",
    "category": "Method",
    "text": "connect!(o1::Observable, o2::Observable)\n\nForward all updates to o1 to o2\n\n\n\n"
},

{
    "location": "index.html#Base.map-Tuple{Any,Observables.Observable,Vararg{Any,N} where N}",
    "page": "Home",
    "title": "Base.map",
    "category": "Method",
    "text": "map(f, o::Observable, args...)\n\nCreates a new oservable ref which contains the result of f applied to values extracted from args. The second argument o must be an oservable ref for dispatch reasons. args may contain any number of Observable ojects. f will be passed the values contained in the refs as the respective argument. All other ojects in args are passed as-is.\n\n\n\n"
},

{
    "location": "index.html#API-1",
    "page": "Home",
    "title": "API",
    "category": "section",
    "text": "Observable{T}\non(f, o::Observable)\noff(o::Observable, f)\nBase.setindex!(o::Observable, val)\nBase.getindex(o::Observable)\nonany(f, os...)\nBase.map!(f, o::Observable, os...)\nconnect!(o1::Observable, o2::Observable)\nBase.map(f, o::Observable, os...; init)"
},

]}
