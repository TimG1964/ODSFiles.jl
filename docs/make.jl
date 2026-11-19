using Documenter, ODSFiles

makedocs(
    sitename = "ODSFiles.jl",
    authors = "Tim Gebbels",
    modules = [ODSFiles],
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://TimG1964.github.io/ODSFiles.jl/stable/",
    ),
    pages = [
        "Home" => "index.md",
        "Getting started" => "tutorial.md",
        "Guide" => Any[
            "Cell values and types" => "guide/values.md",
            "References and names" => "guide/references.md",
            "Formulas" => "guide/formulas.md",
            "Formatting" => "guide/formatting.md",
            "Saving and writing" => "guide/saving.md",
        ],
        "Coming from XLSX.jl" => "xlsx.md",
        "API reference" => "api.md",
    ],
    checkdocs = :public,
    # External links are checked only when asked, as they depend on other sites being up:
    # the CI job "Documentation links" sets DOCUMENTER_LINKCHECK=true.
    linkcheck = get(ENV, "DOCUMENTER_LINKCHECK", "false") == "true",
    linkcheck_ignore = [r"^https://github\.com/TimG1964/ODSFiles\.jl/(blob|tree)/"],
)

deploydocs(
    repo = "github.com/TimG1964/ODSFiles.jl.git",
    devbranch = "master",
    target = "build",
    versions = [
        "stable" => "v^",
        "dev" => "dev",
    ],
)
