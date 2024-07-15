module TestBasics

using Test
import SentryIntegration as Sentry

@testset "generate_uuid4" begin
    for _ in 1:1000
        id = Sentry.generate_uuid4()
        @test id isa String
        @test length(id) == 32
        @test all(char in "0123456789abcdef" for char in id)
    end
end

end
