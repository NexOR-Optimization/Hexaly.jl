using JuMP
using PythonCall
using Test
import Hexaly
import MathOptInterface as MOI
using Random

@testset "VRP (JuMP + Hexaly.Partition + op_sum_distances)" begin
    Random.seed!(1234)
    num_clients = 5
    num_trucks = 2
    x = rand(num_clients)
    y = rand(num_clients)
    d(i, j) = round(Int, 100hypot(x[i] - x[j], y[i] - y[j]))
    dist = [d(i, j) for i = 1:num_clients, j = 1:num_clients]

    model = Model(Hexaly.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, 5)

    @variable(
        model,
        nodes[1:num_clients, 1:num_trucks] in Hexaly.Partition(num_clients, num_trucks),
    )
    @objective(
        model,
        Min,
        sum(Hexaly.op_sum_distances(dist, nodes[:, i]) for i = 1:num_trucks),
    )

    optimize!(model)

    @test termination_status(model) in (MOI.OPTIMAL, MOI.LOCALLY_SOLVED)

    # Reach into the inner Hexaly.Optimizer to recover each truck's underlying
    # Hexaly list (its length is variable, so we cannot just read every
    # `nodes[k, i]`).
    inner = JuMP.unsafe_backend(model)
    trucks = Vector{Int}[]
    for i = 1:num_trucks
        vi = JuMP.index(nodes[1, i])
        list_py = inner.variable_info[vi].parent_list::PythonCall.Py
        list_val = list_py.value
        c = pyconvert(Int, list_val.count())
        push!(trucks, [pyconvert(Int, list_val[Py(k)]) for k = 0:(c-1)])
    end

    # Partition: every client appears in exactly one truck.
    @test sort(reduce(vcat, trucks)) == collect(0:(num_clients-1))

    # Recompute the objective: each truck contributes its closed-tour cost
    # over its visited clients (0 if the truck is empty or has one client).
    expected = 0
    for seq in trucks
        c = length(seq)
        c <= 1 && continue
        for k = 2:c
            expected += dist[seq[k-1]+1, seq[k]+1]
        end
        expected += dist[seq[end]+1, seq[1]+1]
    end
    @test round(Int, objective_value(model)) == expected
end
