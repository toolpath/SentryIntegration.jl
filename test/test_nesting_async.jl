using SentryIntegration

SentryIntegration.init("fake", debug=true, traces_sample_rate=1.0)
# SentryIntegration.init(debug=true, traces_sample_rate=1.0)

function perform_op(t, op)
    SentryIntegration.set_task_transaction(t)
    sleep(1)
    start_transaction(op=op, description="testing sub spans") do t2
        sleep(3)
        perform_sub_op()
        if op == "recurse"
            @sync @async perform_op(t2, "end recurse")
        end
    end
end

function perform_sub_op()
    sleep(1)
    start_transaction(op="inside", description="double nesting") do t
        sleep(5)
    end
end

function proper_nesting()
    start_transaction(name="toplevel", op="highest") do t
        @sync begin
            @async perform_op(t, "first async")
            @async perform_op(t, "second async")
            @async perform_op(t, "recurse")
        end
    end
end

function early_end()
    t = start_transaction(op="highest")

    @sync begin
        @async perform_op(t, "first async")
        @async perform_op(t, "second async")
        @async perform_op(t, "recurse")
        finish_transaction(t)
    end
end

proper_nesting()
# early_end()
