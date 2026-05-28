using JuMP
using Hexaly
using PythonCall
using Test
import MathOptInterface as MOI
using Random

# Build a single VRP instance (2D random coords, depot at index 1, customers
# at 2..n_customers+1) that both the raw-Python and JuMP formulations consume.
function _build_instance(; seed::Int, n_customers::Int, n_trucks::Int)
    Random.seed!(seed)
    cx = rand(n_customers + 1)
    cy = rand(n_customers + 1)
    d(i, j) = round(Int, 100hypot(cx[i] - cx[j], cy[i] - cy[j]))
    dist_depot = [d(1, c + 1) for c = 1:n_customers]
    dist_matrix = [d(i + 1, j + 1) for i = 1:n_customers, j = 1:n_customers]
    # Full `(n_customers + 1) × (n_customers + 1)` matrix used by the JuMP
    # encoding. Hexaly-0-indexed row/col order: customers 0..n-1 first, depot
    # last at index `n_customers`.
    depot = n_customers
    M = zeros(Int, n_customers + 1, n_customers + 1)
    M[1:n_customers, 1:n_customers] .= dist_matrix
    M[n_customers+1, 1:n_customers] .= dist_depot
    M[1:n_customers, n_customers+1] .= dist_depot
    return (; n_customers, n_trucks, dist_depot, dist_matrix, M, depot)
end

# Recompute the VRP cost from the recovered routes, exactly the way the
# original raw-Python test did.
function _route_cost(routes, dist_depot, dist_matrix)
    total = 0
    for r in routes
        isempty(r) && continue
        total += dist_depot[r[1]+1] + dist_depot[r[end]+1]
        for k = 2:length(r)
            total += dist_matrix[r[k-1]+1, r[k]+1]
        end
    end
    return total
end

# Solve via the raw Python Hexaly API: one `model.list` per truck, a
# `model.partition` constraint, and a hand-rolled `model.sum(range, lambda)`
# objective with explicit depot legs.
function _solve_raw(inst)
    optimizer = Hexaly.raw_optimizer()
    m = optimizer.model
    routes = [m.list(inst.n_customers) for _ = 1:(inst.n_trucks)]
    m.constraint(m.partition(pylist(routes)))
    dist_arr =
        m.array(pylist([pylist(inst.dist_matrix[i, :]) for i = 1:(inst.n_customers)]))
    depot_arr = m.array(pylist(inst.dist_depot))
    route_dists = Py[]
    for k = 1:(inst.n_trucks)
        seq = routes[k]
        c = m.count(seq)
        leg = m.lambda_function(
            pyfunc(
                i -> m.at(dist_arr, seq[i-1], seq[i]);
                wrap = "lambda f: lambda i: f(i)",
            ),
        )
        rd =
            m.sum(m.range(1, c), leg) +
            m.iif(c > 0, m.at(depot_arr, seq[0]) + m.at(depot_arr, seq[c-1]), 0)
        push!(route_dists, rd)
    end
    total = m.sum(route_dists...)
    m.minimize(total)
    m.close()
    optimizer.param.time_limit = 5
    optimizer.param.verbosity = 0
    optimizer.solve()
    route_vals = [[pyconvert(Int, x) for x in seq.value] for seq in routes]
    obj = pyconvert(Int, total.value)
    optimizer.delete()
    return route_vals, obj
end

# Solve via JuMP / MOI using `Hexaly.Partition` + `Hexaly.op_sum_distances`,
# with the depot threaded into the cost via `vcat(depot, nodes[:, i], depot)`.
function _solve_jump(inst)
    model = Model(Hexaly.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, 5)
    @variable(
        model,
        nodes[1:(inst.n_customers), 1:(inst.n_trucks)] in
        Hexaly.Partition(inst.n_customers, inst.n_trucks),
    )
    @objective(
        model,
        Min,
        sum(
            Hexaly.op_sum_distances(inst.M, vcat(inst.depot, nodes[:, i], inst.depot)) for
            i = 1:(inst.n_trucks)
        ),
    )
    optimize!(model)
    @test termination_status(model) in (MOI.OPTIMAL, MOI.LOCALLY_SOLVED)
    inner = JuMP.unsafe_backend(model)
    routes = Vector{Int}[]
    for i = 1:(inst.n_trucks)
        vi = JuMP.index(nodes[1, i])
        list_py = inner.variable_info[vi].parent_list::PythonCall.Py
        list_val = list_py.value
        c = pyconvert(Int, list_val.count())
        push!(routes, [pyconvert(Int, list_val[Py(k)]) for k = 0:(c-1)])
    end
    return routes, round(Int, objective_value(model))
end

@testset "VRP" begin
    inst = _build_instance(seed = 1234, n_customers = 6, n_trucks = 2)
    raw_routes, raw_obj = _solve_raw(inst)
    jump_routes, jump_obj = _solve_jump(inst)

    @testset "raw Python API" begin
        @test sort(reduce(vcat, raw_routes)) == collect(0:(inst.n_customers-1))
        @test raw_obj == _route_cost(raw_routes, inst.dist_depot, inst.dist_matrix)
    end

    @testset "JuMP" begin
        @test sort(reduce(vcat, jump_routes)) == collect(0:(inst.n_customers-1))
        @test jump_obj == _route_cost(jump_routes, inst.dist_depot, inst.dist_matrix)
    end

    @testset "raw and JuMP agree on the objective" begin
        @test raw_obj == jump_obj
    end
end
