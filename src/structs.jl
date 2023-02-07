##############################
# * Support structs
#----------------------------

Base.@kwdef mutable struct Span
    span_id::String = generate_uuid4()[1:16]
    parent_span_id::Union{Nothing, String} = nothing
    tags::Union{Nothing, Dict{String, String}} = nothing
    op::Union{Nothing, String} = nothing
    description::Union{Nothing, String} = nothing
    start_timestamp::String = nowstr()
    timestamp::Union{Nothing, String} = nothing
    status::String = "ok"
end

Base.@kwdef mutable struct Transaction
    event_id::String = generate_uuid4()
    trace_id::String
    name::String
    spans::Vector{Span} = []
    root_span::Union{Nothing, Span} = nothing
    num_open_spans::Int = 0
end

Base.@kwdef struct Event
    event_id::String = generate_uuid4()
    timestamp::String = nowstr()
    message::Union{Nothing, NamedTuple} = nothing
    exception::Union{Nothing, NamedTuple} = nothing
    level::String
    tags::Union{Nothing, Dict{String, String}} = nothing
    attachments::Vector{Any} = []
    transaction::Union{Nothing, Transaction} = nothing
end


##############################
# * Hub
#----------------------------

struct NoSamples end
struct RatioSampler
    ratio::Float64
    function RatioSampler(x)
        @assert 0 <= x <= 1
        new(x)
    end
end

const Sampler = Union{NoSamples, RatioSampler}

sample(::NoSamples) = false
sample(sampler::RatioSampler) = rand() < sampler.ratio
sample(sampler::Function) = sampler()

const TaskPayload = Union{Event, Transaction}

# This is to supposedly support the "unified api" of the sentry sdk. I'm not a
# fan, so it will only go partway to this goal.
# Note: a proper implementation here would make Hub a module.
Base.@kwdef mutable struct Hub
    initialised::Bool = false
    traces_sampler::Sampler = NoSamples()

    dsn::Union{Nothing, String} = nothing
    upstream::String = ""
    project_id::String = ""
    public_key::String = ""

    release::Union{Nothing, String} = nothing
    debug::Bool = false

    # last_send_time::Union{Nothing, String} = nothing
    queued_tasks::Channel{TaskPayload} = Channel{TaskPayload}(100)
    sending_tasks::Dict{String, TaskPayload} = Dict()
    sender_task::Union{Nothing, Task} = nothing
end
