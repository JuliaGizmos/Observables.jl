using Documenter, Observables

makedocs(
    modules = [Observables],
    clean = false,
    format = Documenter.HTML(),
    sitename = "Observables.jl",
    authors = "JuliaGizmos",
    pages = Any["Home" => "index.md"],
)

deploydocs(
    julia = "nightly",
    repo = "github.com/JuliaGizmos/Observables.jl.git",
    target = "build",
    deps = nothing,
    make = nothing,
)
