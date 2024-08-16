# data structs

Base.@kwdef mutable struct Span
    span_id::String = generate_uuid4()[1:16]
    parent_span_id::Union{Nothing,String} = nothing
    tags::Union{Nothing,Dict{String,String}} = nothing
    op::Union{Nothing,String} = nothing
    description::Union{Nothing,String} = nothing
    start_timestamp::String = nowstr()
    timestamp::Union{Nothing,String} = nothing
    status::String = "ok"
end

Base.@kwdef mutable struct Transaction
    event_id::String = generate_uuid4()
    trace_id::String
    name::String
    spans::Vector{Span} = []
    root_span::Union{Nothing,Span} = nothing
    num_open_spans::Int = 0
end

Base.@kwdef struct Event
    event_id::String = generate_uuid4()
    timestamp::String = nowstr()
    message::Union{Nothing,NamedTuple} = nothing
    exception::Union{Nothing,NamedTuple} = nothing
    level::String
    tags::Union{Nothing,Dict{String,String}} = nothing
    attachments::Vector{Any} = []
    transaction::Union{Nothing,Transaction} = nothing
end

# main hub

struct NoSamples end

struct RatioSampler
    ratio::Float64
    function RatioSampler(x)
        @assert 0 <= x <= 1
        new(x)
    end
end

const Sampler = Union{NoSamples,RatioSampler}

function sample(::NoSamples)
    false
end

function sample(sampler::RatioSampler)
    rand() < sampler.ratio
end

function sample(sampler::Function)
    sampler()
end

const TaskPayload = Union{Event,Transaction}

Base.@kwdef mutable struct Hub
    initialised::Bool = false
    traces_sampler::Sampler = NoSamples()

    dsn::Union{Nothing,String} = nothing
    upstream::String = ""
    project_id::String = ""
    public_key::String = ""

    release::Union{Nothing,String} = nothing
    debug::Bool = false

    # last_send_time::Union{Nothing, String} = nothing
    queued_tasks::Channel{TaskPayload} = Channel{TaskPayload}(100)
    sending_tasks::Dict{String,TaskPayload} = Dict()
    sender_task::Union{Nothing,Task} = nothing
end

# helper functions

function unix_time(timestamp::String)
    datetime2unix(DateTime(timestamp[1:23])) # exclude Z
end

function unix_time(::Nothing)
    datetime2unix(now(UTC))
end

function get_duration_seconds(span::Span)
    s = unix_time(span.timestamp) - unix_time(span.start_timestamp)
    round(s; digits = 3)
end

function get_span_tree(t::Transaction)
    children_lookup = Dict{Union{Nothing,String},Vector{Span}}()
    for span in t.spans
        push!(get!(children_lookup, span.parent_span_id, Span[]), span)
    end
    descendants(t.root_span, children_lookup)
end

function descendants(span, children_lookup)
    sub_nodes = if haskey(children_lookup, span.span_id)
        children = children_lookup[span.span_id]
        descendants.(children, Ref(children_lookup))
    else
        []
    end
    sort!(sub_nodes; by = (node -> node.span.start_timestamp))
    (; span, sub_nodes)
end

# show

function print_indent(io, l, args...)
    println(io, repeat(" ", 2 * l), args...)
end

function print_node(io, node, l = 0)
    (; span, sub_nodes) = node
    desc = something(span.description, span.span_id)
    s = get_duration_seconds(span)
    str = "$(span.op) - $desc, $s s"
    print_indent(io, l, str)
    for sub_node in sub_nodes
        print_node(io, sub_node, l + 1)
    end
end

function Base.show(io::IO, span::Span)
    desc = something(span.description, span.span_id)
    s = get_duration_seconds(span)
    print(io, "Span($(span.op) - $desc, $s s)")
end

function Base.show(io::IO, t::Transaction)
    n = length(t.spans)
    s = get_duration_seconds(t.root_span)
    status = t.root_span.status
    print(io, "Transaction(\"$(t.name)\", $n spans, $s s, $status)")
end

function Base.show(io::IO, ::MIME"text/plain", t::Transaction)
    println(io, t)
    for node in get_span_tree(t).sub_nodes
        print_node(io, node, 1)
    end
end
