module Signals

export Signal, connect!, disconnect!, emit

if isdefined(Base, :Iterators) && isdefined(Base.Iterators, :filter)
    import Base.Iterators.filter
else
    import Base.filter
end

"""
Signal with N arguments
"""
struct Signal{N}
    listeners::Vector
    (::Type{Signal{T}}){T}() = new{T}(Any[])
end

function emit{N}(signal::Signal{N}, args::Vararg{Any,N})
  for f in signal.listeners
    f(args...)
  end
end

function connect!(signal::Signal, f)
  push!(signal.listeners,f)
  return signal
end

end # module
