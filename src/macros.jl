function parse_function_call(x)
    syms = OrderedDict()
    res = parse_function_call!(syms, expr)
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

macro map(expr)
    esc(map_helper(expr))
end

function map!_helper(d, expr)
    func, syms = parse_function_call(expr)
    Expr(:call, :map!, func, d, keys(syms)...)
end

macro map!(d, expr)
    esc(map!_helper(d, expr))
end

function on_helper(expr)
    func, syms = parse_function_call(expr)
    Expr(:call, :(Observables.on), func, keys(syms)...)
end

macro on(expr)
    esc(on_helper(expr))
end
