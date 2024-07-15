using JuliaFormatter

function run_formatter(files)
    okay = true
    for file in files
        okay &= format(file; verbose = false)
    end
    okay
end

function collect_files()
    mapreduce(append!, ["src", "test", "."]) do dir
        filter(s -> endswith(s, ".jl"), readdir(dir; join = true))
    end
end

okay = run_formatter(collect_files())
@assert okay "all files formatted"
