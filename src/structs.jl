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

sample(::NoSamples) = false
sample(sampler::RatioSampler) = rand() < sampler.ratio
sample(sampler::Function) = sampler()

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

function get_span_tree(t::Transaction)
    children_lookup = Dict()
    for span in t.spans
        push!(get!(children_lookup, span.parent_span_id, []), span)
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

print_indent(io, l, args...) = println(io, repeat(" ", 2 * l), args...)

function print_node(io, node, l = 0)
    (; span, sub_nodes) = node
    print_indent(io, l, "", span.op, " - ", something(span.description, span.span_id))
    for sub_node in sub_nodes
        print_node(io, sub_node, l + 1)
    end
end

function Base.show(io::IO, s::Span)
    print(io, "Span(", s.op, ", ", something(s.description, s.span_id), ")")
end

function Base.show(io::IO, t::Transaction)
    print(
        io,
        "Transaction(",
        t.name,
        ", ",
        length(t.spans),
        " spans",
        ", ",
        t.root_span.status,
        ")",
    )
end

function Base.show(io::IO, ::MIME"text/plain", t::Transaction)
    println(
        io,
        "Transaction: ",
        t.name,
        " (",
        length(t.spans),
        " spans",
        ", ",
        t.root_span.status,
        ")",
    )
    for node in get_span_tree(t).sub_nodes
        print_node(io, node, 1)
    end
end
