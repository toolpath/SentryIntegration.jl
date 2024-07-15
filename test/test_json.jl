module TestJSON

using Test
using JSON3
using Dates

using SentryIntegration
using SentryIntegration: Event, prepare_body

SentryIntegration.init("fake", debug=false, traces_sample_rate=1.0)

@testset "Event (error)" begin
    event_time = now(UTC)
    event = Event(;
        event_id = "0",
        timestamp = string(event_time, "Z"),
        exception = (;
            values = [
                Dict(
                    :type => "typename",
                    :module => "modulename",
                    :value => "message",
                    :stacktrace => (;
                        frames = [
                            Dict(:filename => "file.jl", :function => "f", :lineno => 128),
                            Dict(:filename => "file.jl", :function => "g", :lineno => 256),
                        ]
                    ),
                ),
            ]
        ),
        level = "error",
        tags = Dict("key1" => "value1"),
    )

    io = IOBuffer()
    prepare_body(event, io)
    data = JSON3.read(String(take!(io)); jsonlines=true)
    iso_utc = dateformat"yyyy-mm-ddTHH:MM:SS.sZ"

    @test length(data) == 3

    @testset "1" begin
        json = data[1]
        @test keys(json) == Set((:event_id, :sent_at, :dsn))
        @test json["event_id"] == event.event_id
    end

    @testset "2" begin
        json = data[2]
        @test keys(json) == Set((:type, :content_type, :length))
        @test json["type"] == "event"
        @test json["content_type"] == "application/json"
    end

    @testset "3" begin
        json = data[3]
        @test json["timestamp"] == event.timestamp
        @test DateTime(event.timestamp, iso_utc) == event_time
        @test json["level"] == "error"
    end
end

end # module
