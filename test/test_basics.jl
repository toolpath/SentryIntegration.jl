module TestBasics

using Test
using Pkg
import SentryIntegration as Sentry

@testset "version" begin
    @test Sentry.VERSION == Sentry.get_version()
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
