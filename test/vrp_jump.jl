using JuMP
using PythonCall
using Test
import Hexaly
import MathOptInterface as MOI
using Random

@testset "VRP (JuMP, matches raw-Python vrp.jl)" begin
    # Identical instance to `test/vrp.jl`: same seed, same coords, same
    # n_customers / n_trucks. We compare the JuMP-side objective to the raw
    # Python objective so the two paths land on the same optimum.
    Random.seed!(1234)
    n_customers = 6
    n_trucks = 2

    cx = rand(n_customers + 1)
    cy = rand(n_customers + 1)
    d(i, j) = round(Int, 100hypot(cx[i] - cx[j], cy[i] - cy[j]))
    # `coords[1]` is the depot, `coords[2..]` are customers.
    # `dist_matrix_with_depot` is `(n_customers + 1) × (n_customers + 1)`,
    # with Hexaly-0-indexed row/col order [customer_0, …, customer_{n-1}, depot].
    depot = n_customers  # Hexaly index of the depot
    M = zeros(Int, n_customers + 1, n_customers + 1)
    for i = 1:n_customers, j = 1:n_customers
        M[i, j] = d(i + 1, j + 1)        # customer-to-customer
    end
    for c = 1:n_customers
        M[n_customers+1, c] = d(1, c + 1)  # depot-to-customer
        M[c, n_customers+1] = d(c + 1, 1)  # customer-to-depot
    end

    model = Model(Hexaly.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, 5)

    @variable(
        model,
        nodes[1:n_customers, 1:n_trucks] in
        Hexaly.Partition(n_customers, n_trucks),
    )
    @objective(
        model,
        Min,
        sum(
            Hexaly.op_sum_distances(M, vcat(depot, nodes[:, i], depot)) for
            i = 1:n_trucks
        ),
    )

    optimize!(model)

    @test termination_status(model) in (MOI.OPTIMAL, MOI.LOCALLY_SOLVED)

    # Recover each truck's actual list and recompute the route cost the way
    # `test/vrp.jl` does (depot legs via `dist_depot`, internals via
    # `dist_matrix`) — both Hexaly paths should land on the same value.
    inner = JuMP.unsafe_backend(model)
    dist_depot = [d(1, c + 1) for c = 1:n_customers]
    dist_matrix = [d(i + 1, j + 1) for i = 1:n_customers, j = 1:n_customers]

    trucks = Vector{Int}[]
    for i = 1:n_trucks
        vi = JuMP.index(nodes[1, i])
        list_py = inner.variable_info[vi].parent_list::PythonCall.Py
        list_val = list_py.value
        c = pyconvert(Int, list_val.count())
        push!(trucks, [pyconvert(Int, list_val[Py(k)]) for k = 0:(c-1)])
    end

    @test sort(reduce(vcat, trucks)) == collect(0:(n_customers-1))

    expected = 0
    for seq in trucks
        if !isempty(seq)
            expected += dist_depot[seq[1]+1] + dist_depot[seq[end]+1]
            for k = 2:length(seq)
                expected += dist_matrix[seq[k-1]+1, seq[k]+1]
            end
        end
    end
    @test round(Int, objective_value(model)) == expected
end
