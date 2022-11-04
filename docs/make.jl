using Documenter, Observables

makedocs(
    modules = [Observables],
    format = Documenter.HTML(),
    sitename = "Observables.jl",
    authors = "JuliaGizmos",
    strict=true, # make docs fail
    pages = Any["Home" => "index.md"],
)

deploydocs(repo = "github.com/JuliaGizmos/Observables.jl.git", push_preview=true)
