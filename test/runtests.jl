using Test

function is_test_file(path)
    isfile(path) && startswith(basename(path), "test_") && endswith(path, ".jl")
end

for path in readdir(@__DIR__, join = true)
    is_test_file(path) || continue
    @testset "$(basename(path))" begin
        include(path)
    end
end
