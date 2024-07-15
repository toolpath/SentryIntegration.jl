module TestBasics

using Test
using Pkg
import SentryIntegration as Sentry

@testset "version" begin
    project_toml = joinpath(pkgdir(Sentry), "Project.toml")
    project = Pkg.Types.read_project(project_toml)
    @test Sentry.VERSION == project.version
end

@testset "generate_uuid4" begin
    for _ in 1:1000
        id = Sentry.generate_uuid4()
        @test id isa String
        @test length(id) == 32
        @test all(char in "0123456789abcdef" for char in id)
    end
end

end
