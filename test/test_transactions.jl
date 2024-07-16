module TestTransactions

using Test

using SentryIntegration
using SentryIntegration: Span, Transaction, get_span_tree

SentryIntegration.init("fake"; debug = true, traces_sample_rate = 1.0)

function span_key(span)
    (span.op, span.description)
end

function span_keys(node)
    (span_key(node.span), map(span_keys, node.sub_nodes))
end

@testset "one task, flat spans (serial execution)" begin
    expected = (("root_span", "0"), [(("span1", "1"), []), (("span2", "2"), [])])

    tps =
        start_transaction(; name = "transaction", op = "root_span", description = "0") do t
            start_transaction(_ -> sleep(0.1); op = "span1", description = "1")
            start_transaction(_ -> sleep(0.1); op = "span2", description = "2")
            t
        end
    @test span_keys(get_span_tree(tps.transaction)) == expected

    tps =
        start_transaction(; name = "transaction", op = "root_span", description = "0") do t
            s1 = start_transaction(; op = "span1", description = "1")
            sleep(0.1) # do work
            finish_transaction(s1)

            s2 = start_transaction(; op = "span2", description = "2")
            sleep(0.1) # do work
            finish_transaction(s2)
            t
        end
    @test span_keys(get_span_tree(tps.transaction)) == expected
end

@testset "one task, flat spans (parallel execution)" begin
    expected = (("root_span", "0"), [(("span1", "1"), []), (("span2", "2"), [])])

    tps =
        start_transaction(; name = "transaction", op = "root_span", description = "0") do t
            # start two spans:
            # 1. parent_span == root_span
            @test task_local_storage(:sentry_parent_span) == t.span
            s1 = start_transaction(; op = "span1", description = "1")
            @test task_local_storage(:sentry_parent_span) == s1.span

            # 2. must set parent_span = root_span before starting span2
            set_task_transaction(t)
            @test task_local_storage(:sentry_parent_span) == t.span
            s2 = start_transaction(; op = "span2", description = "2")
            @test task_local_storage(:sentry_parent_span) == s2.span

            # do work elsewhere
            sleep(0.1)
            # finish spans
            finish_transaction(s1)
            finish_transaction(s2)
            t
        end
    @test span_keys(get_span_tree(tps.transaction)) == expected

    # TODO allow setting parent_span explicitly in start_transaction?
end

@testset "one task, nested spans" begin
    expected = (("root_span", "0"), [(("span1", "1"), [(("span2", "2"), [])])])

    # explicitly nested
    tps =
        start_transaction(; name = "transaction", op = "root_span", description = "0") do t
            start_transaction(; op = "span1", description = "1") do _
                start_transaction(; op = "span2", description = "2") do _
                    sleep(0.1)
                end
            end
            t
        end
    @test span_keys(get_span_tree(tps.transaction)) == expected

    # implicitly nested
    tps =
        start_transaction(; name = "transaction", op = "root_span", description = "0") do t
            s1 = start_transaction(; op = "span1", description = "1")
            s2 = start_transaction(; op = "span2", description = "2")
            sleep(0.1)
            finish_transaction(s1)
            finish_transaction(s2)
            t
        end
    @test span_keys(get_span_tree(tps.transaction)) == expected
end

@testset "async tasks, separate transactions" begin
    t0, t1, t2 =
        start_transaction(; name = "transaction", op = "root_span", description = "0") do t
            t1 = nothing
            t2 = nothing
            @sync begin
                @async t1 = start_transaction(; op = "span1", description = "1")
                @async t2 = start_transaction(; op = "span2", description = "2")
            end
            finish_transaction(t1)
            finish_transaction(t2)
            t, t1, t2
        end

    @test span_keys(get_span_tree(t0.transaction)) == (("root_span", "0"), [])
    @test span_keys(get_span_tree(t1.transaction)) == (("span1", "1"), [])
    @test span_keys(get_span_tree(t2.transaction)) == (("span2", "2"), [])
end

@testset "async tasks, one transaction" begin
    function async_op(t, description)
        set_task_transaction(t)
        start_transaction(; op = "async_op", description) do t2
            perform_sub_op("1")
            perform_sub_op("2")
            if description == "recurse"
                @sync (@async async_op(t2, "final"))
            end
        end
    end

    function perform_sub_op(description)
        start_transaction(; op = "sub_op", description) do t
            sleep(0.1)
        end
    end

    function async_nested(; end_early = false)
        start_transaction(; name = "transaction", op = "root_span") do t
            @sync begin
                end_early && finish_transaction(t)
                @async async_op(t, "1")
                @async async_op(t, "2")
                @async async_op(t, "recurse")
            end
            t
        end
    end

    expected = (
        ("root_span", nothing),
        [
            (("async_op", "1"), [(("sub_op", "1"), []), (("sub_op", "2"), [])]),
            (("async_op", "2"), [(("sub_op", "1"), []), (("sub_op", "2"), [])]),
            (
                ("async_op", "recurse"),
                [
                    (("sub_op", "1"), []),
                    (("sub_op", "2"), []),
                    (("async_op", "final"), [(("sub_op", "1"), []), (("sub_op", "2"), [])]),
                ],
            ),
        ],
    )

    t = async_nested().transaction
    @test span_keys(get_span_tree(t)) == expected

    t = async_nested(; end_early = true).transaction
    @test span_keys(get_span_tree(t)) == expected
end

end # module
