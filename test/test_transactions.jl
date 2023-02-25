module TestTransactions

using Test

using SentryIntegration
import SentryIntegration: Span, Transaction, get_span_tree

SentryIntegration.init("fake", debug=false, traces_sample_rate=1.0)

function async_op(t, description)
    SentryIntegration.set_task_transaction(t)
    start_transaction(; op="async_op", description) do t2
        perform_sub_op("1")
        perform_sub_op("2")
        if description == "recurse"
            @sync @async async_op(t2, "final")
        end
    end
end

function perform_sub_op(description)
    start_transaction(; op="sub_op", description) do t
        sleep(0.1)
    end
end

function async_nested(; end_early=false)
    start_transaction(; name="main", op="main") do t
        @sync begin
            @async async_op(t, "1")
            @async async_op(t, "2")
            @async async_op(t, "recurse")
            end_early && finish_transaction(t)
        end
        t
    end
end

span_key(span) = (span.op, span.description)
span_keys(node) = (span_key(node.span), map(span_keys, node.sub_nodes))

@testset "async, nested spans" begin
    expected = (("main", nothing), [
        (("async_op", "1"), [
            (("sub_op", "1"), []),
            (("sub_op", "2"), []),
        ]),
        (("async_op", "2"), [
            (("sub_op", "1"), []),
            (("sub_op", "2"), []),
        ]),
        (("async_op", "recurse"), [
            (("sub_op", "1"), []),
            (("sub_op", "2"), []),
            (("async_op", "final"), [
                (("sub_op", "1"), []),
                (("sub_op", "2"), []),
            ]),
        ]),
    ])

    t = async_nested().transaction
    @test span_keys(get_span_tree(t)) == expected

    t = async_nested(; end_early=true).transaction
    @test span_keys(get_span_tree(t)) == expected
end

end # module
