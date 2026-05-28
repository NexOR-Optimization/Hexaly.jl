using JuMP
using Hexaly
using PythonCall
using Test
import MathOptInterface as MOI
using Random

# VRPPD instance: `num_services` plain visits, `num_pickup_deliveries` pickup
# and delivery pairs, and `num_trucks` vehicles. Indices in Hexaly's
# 0-indexed list values:
#   - services:  0 .. num_services - 1
#   - pickups:   num_services .. num_services + num_pd - 1
#   - deliveries: num_services + num_pd .. n_total - 1
# Pickup `k` is paired with delivery `num_services + num_pd + k`.
function _build_instance(;
    seed::Int,
    num_services::Int,
    num_pickup_deliveries::Int,
    num_trucks::Int,
)
    Random.seed!(seed)
    n_total = num_services + 2 * num_pickup_deliveries
    cx = rand(n_total + 1)
    cy = rand(n_total + 1)
    d(i, j) = round(Int, 100hypot(cx[i] - cx[j], cy[i] - cy[j]))
    dist_depot = [d(1, c + 1) for c = 1:n_total]
    dist_matrix = [d(i + 1, j + 1) for i = 1:n_total, j = 1:n_total]
    depot = n_total
    M = zeros(Int, n_total + 1, n_total + 1)
    M[1:n_total, 1:n_total] .= dist_matrix
    M[n_total+1, 1:n_total] .= dist_depot
    M[1:n_total, n_total+1] .= dist_depot
    return (;
        num_services,
        num_pickup_deliveries,
        num_trucks,
        n_total,
        dist_depot,
        dist_matrix,
        M,
        depot,
    )
end

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

# Validate a recovered partition: every value 0..n_total-1 appears once, each
# pickup precedes its delivery, and both sit in the same truck.
function _check_vrppd!(routes, inst)
    @test sort(reduce(vcat, routes)) == collect(0:(inst.n_total-1))
    for k = 0:(inst.num_pickup_deliveries-1)
        p = inst.num_services + k
        d = inst.num_services + inst.num_pickup_deliveries + k
        truck_with_p = findfirst(r -> p in r, routes)
        truck_with_d = findfirst(r -> d in r, routes)
        @test truck_with_p !== nothing
        @test truck_with_p == truck_with_d
        seq = routes[truck_with_p]
        @test findfirst(==(p), seq) < findfirst(==(d), seq)
    end
end

function _solve_raw(inst)
    optimizer = Hexaly.raw_optimizer()
    m = optimizer.model
    n_total = inst.n_total
    routes = [m.list(n_total) for _ = 1:(inst.num_trucks)]
    m.constraint(m.partition(pylist(routes)))
    # Pickup-delivery constraints.
    for k = 0:(inst.num_pickup_deliveries-1)
        p = inst.num_services + k
        d = inst.num_services + inst.num_pickup_deliveries + k
        for seq in routes
            m.constraint(m.contains(seq, Py(p)) == m.contains(seq, Py(d)))
            m.constraint(m.index(seq, Py(p)) <= m.index(seq, Py(d)))
        end
    end
    dist_arr = m.array(pylist([pylist(inst.dist_matrix[i, :]) for i = 1:n_total]))
    depot_arr = m.array(pylist(inst.dist_depot))
    route_dists = Py[]
    for k = 1:(inst.num_trucks)
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

function _solve_jump(inst)
    model = Model(Hexaly.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, 5)
    @variable(
        model,
        nodes[1:(inst.n_total), 1:(inst.num_trucks)] in
        Hexaly.PartitionPD(inst.num_services, inst.num_pickup_deliveries, inst.num_trucks),
    )
    @objective(
        model,
        Min,
        sum(
            Hexaly.op_sum_distances(inst.M, vcat(inst.depot, nodes[:, i], inst.depot)) for
            i = 1:(inst.num_trucks)
        ),
    )
    optimize!(model)
    @test termination_status(model) in (MOI.OPTIMAL, MOI.LOCALLY_SOLVED)
    inner = JuMP.unsafe_backend(model)
    routes = Vector{Int}[]
    for i = 1:(inst.num_trucks)
        vi = JuMP.index(nodes[1, i])
        list_py = inner.variable_info[vi].parent_list::PythonCall.Py
        list_val = list_py.value
        c = pyconvert(Int, list_val.count())
        push!(routes, [pyconvert(Int, list_val[Py(k)]) for k = 0:(c-1)])
    end
    return routes, round(Int, objective_value(model))
end

@testset "VRPPD" begin
    inst = _build_instance(
        seed = 1234,
        num_services = 3,
        num_pickup_deliveries = 2,
        num_trucks = 2,
    )
    raw_routes, raw_obj = _solve_raw(inst)
    jump_routes, jump_obj = _solve_jump(inst)

    @testset "raw Python API" begin
        _check_vrppd!(raw_routes, inst)
        @test raw_obj == _route_cost(raw_routes, inst.dist_depot, inst.dist_matrix)
    end

    @testset "JuMP" begin
        _check_vrppd!(jump_routes, inst)
        @test jump_obj == _route_cost(jump_routes, inst.dist_depot, inst.dist_matrix)
    end

    @testset "raw and JuMP agree on the objective" begin
        @test raw_obj == jump_obj
    end
end
