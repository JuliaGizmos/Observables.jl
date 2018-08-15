function parse_function_call(x)
    syms = Dict()
    res = parse_function_call!(syms, x)
    func = Expr(:(->), Expr(:tuple, values(syms)...), res)
    return func, syms
end

function parse_function_call!(syms, x::Expr)
    if x.head == :& && length(x.args) == 1
        get!(syms, x.args[1], gensym())
    else
        Expr(x.head, (parse_function_call!(syms, arg) for arg in x.args)...)
    end
end

parse_function_call!(syms, x) = x

function map_helper(expr)
    func, syms = parse_function_call(expr)
    Expr(:call, :map, func, keys(syms)...)
end

"""
`@map(expr)`

Wrap `AbstractObservables` in `&` to compute expression `expr` using their value. The expression will be
computed when `@map` is called and  every time the `AbstractObservables` are updated.

## Examples

```jldoctest mapmacro
julia> a = Observable(2);

julia> b = Observable(3);

julia> c = Observables.@map &a + &b;

julia> c[]
5

julia> a[] = 100
100

julia> c[]
103
```
"""
macro map(expr)
    esc(map_helper(expr))
end

function map!_helper(d, expr)
    func, syms = parse_function_call(expr)
    Expr(:call, :map!, func, d, keys(syms)...)
end

"""
`@map!(d, expr)`

Wrap `AbstractObservables` in `&` to compute expression `expr` using their value: the expression will be
computed every time the `AbstractObservables` are updated and `d` will be set to match that value.

## Examples

```jldoctest mapmacro
julia> a = Observable(2);

julia> b = Observable(3);

julia> c = Observable(10);

julia> Observables.@map! c &a + &b;

julia> c[]
10

julia> a[] = 100
100

julia> c[]
103
```
"""
macro map!(d, expr)
    esc(map!_helper(d, expr))
end

function on_helper(expr)
    func, syms = parse_function_call(expr)
    Expr(:call, :(Observables.onany), func, keys(syms)...)
end

"""
`@on(expr)`

Wrap `AbstractObservables` in `&` to execute expression `expr` using their value. The expression will be
computed every time the `AbstractObservables` are updated.

## Examples

```jldoctest onmacro
julia> a = Observable(2);

julia> b = Observable(3);

julia> Observables.@on println("The sum of a+b is \$(&a + &b)");

julia> a[] = 100;
The sum of a+b is 103
```
"""
macro on(expr)
    esc(on_helper(expr))
end
