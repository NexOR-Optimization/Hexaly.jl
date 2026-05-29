using JuMP
using Hexaly
using PythonCall
using Test
import MathOptInterface as MOI
using Random

# CVRP instance with pickup/delivery pairs:
#   - `num_services` plain visits (no load impact)
#   - `num_pickup_deliveries` pickup/delivery pairs; pickup `k` adds
#     `quantities[k+1]` to the truck's load, the paired delivery subtracts the
#     same amount
#   - `num_trucks` vehicles, each with `capacity` upper bound on its load at
#     every step of the route
# Hexaly 0-indexed node ids:
#   - services:   0 .. num_services - 1
#   - pickups:    num_services .. num_services + num_pd - 1
#   - deliveries: num_services + num_pd .. n_total - 1
function _build_instance(;
    seed::Int,
    num_services::Int,
    num_pickup_deliveries::Int,
    num_trucks::Int,
    capacity::Int,
    quantity_range = 2:4,
)
    Random.seed!(seed)
    n_total = num_services + 2 * num_pickup_deliveries
    cx = rand(n_total + 1)
    cy = rand(n_total + 1)
    d(i, j) = round(Int, 100hypot(cx[i] - cx[j], cy[i] - cy[j]))
    dist_depot = [d(1, c + 1) for c = 1:n_total]
    dist_matrix = [d(i + 1, j + 1) for i = 1:n_total, j = 1:n_total]

    quantities = [rand(quantity_range) for _ = 1:num_pickup_deliveries]
    # Load-change per Hexaly-0-indexed node: +q at the pickup, -q at the
    # paired delivery, 0 at services.
    delta = zeros(Int, n_total)
    for k = 1:num_pickup_deliveries
        delta[num_services+k] = quantities[k]
        delta[num_services+num_pickup_deliveries+k] = -quantities[k]
    end

    # Full `(n_total + 1) × (n_total + 1)` travel matrix used by the JuMP
    # encoding (`op_sum_distances` reads from it); depot at index `n_total`.
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
        capacity,
        quantities,
        delta,
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

# Verify partition + PD pairing + capacity feasibility from the recovered
# routes (independent of the Hexaly model).
function _check_cvrp!(routes, inst)
    @test sort(reduce(vcat, routes)) == collect(0:(inst.n_total-1))
    # Pickup-delivery pairing: same truck and pickup before delivery.
    for k = 0:(inst.num_pickup_deliveries-1)
        p = inst.num_services + k
        d = inst.num_services + inst.num_pickup_deliveries + k
        truck_p = findfirst(r -> p in r, routes)
        truck_d = findfirst(r -> d in r, routes)
        @test truck_p !== nothing
        @test truck_p == truck_d
        seq = routes[truck_p]
        @test findfirst(==(p), seq) < findfirst(==(d), seq)
    end
    # Capacity: cumulative load along each route never exceeds `capacity`,
    # and finishes at 0 (every pickup matched by its delivery in the same truck).
    for r in routes
        load = 0
        max_load = 0
        for v in r
            load += inst.delta[v+1]
            max_load = max(max_load, load)
        end
        @test 0 <= max_load <= inst.capacity
        @test load == 0
    end
end

# Pure-Hexaly CVRP solve: list per truck, partition, PD constraints,
# cumulative load array via `model.array(range, lambda(i, prev), 0)`, and a
# per-position capacity hard constraint via `model.and_(range, lambda)`.
function _solve_raw(inst)
    GC.gc()
    optimizer = Hexaly.raw_optimizer()
    try
        return _build_and_solve_raw(optimizer, inst)
    finally
        optimizer.delete()
    end
end

function _build_and_solve_raw(optimizer, inst)
    m = optimizer.model
    n_total = inst.n_total
    routes = [m.list(n_total) for _ = 1:(inst.num_trucks)]
    m.constraint(m.partition(pylist(routes)))

    # PD pairing: same truck, pickup before delivery.
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
    delta_arr = m.array(pylist(inst.delta))

    route_dists = Py[]
    for k = 1:(inst.num_trucks)
        seq = routes[k]
        c = m.count(seq)

        # Distance for this truck (closed VRP cost with depot legs).
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

        # Cumulative load through the route:
        #   load[0] = delta[seq[0]]
        #   load[i] = load[i-1] + delta[seq[i]]
        load = m.array(
            m.range(0, c),
            m.lambda_function(
                pyfunc(
                    (i, prev) -> m.iif(
                        i == 0,
                        m.at(delta_arr, seq[0]),
                        prev + m.at(delta_arr, seq[i]),
                    );
                    wrap = "lambda f: lambda i, prev: f(i, prev)",
                ),
            ),
            Py(0),
        )

        # Capacity constraint: at every visited position the load is at most
        # the truck's capacity. (Load is always non-negative because pickup
        # precedes delivery for every PD pair.)
        m.constraint(
            m.and_(
                m.range(0, c),
                m.lambda_function(
                    pyfunc(
                        i -> load[i] <= Py(inst.capacity);
                        wrap = "lambda f: lambda i: f(i)",
                    ),
                ),
            ),
        )
    end

    total = m.sum(route_dists...)
    m.minimize(total)
    m.close()

    optimizer.param.time_limit = 5
    optimizer.param.verbosity = 0
    optimizer.solve()

    route_vals = [[pyconvert(Int, x) for x in seq.value] for seq in routes]
    obj = pyconvert(Int, total.value)
    return route_vals, obj
end

# JuMP / MOI solve: use `Hexaly.PartitionPD` for the truck columns (so
# pickup/delivery pairing is already enforced), `Hexaly.Capacity` for the
# per-truck cumulative-load constraint, and `op_sum_distances` for the
# closed-tour distance objective with depot legs.
function _solve_jump(inst)
    GC.gc()
    model = Model(Hexaly.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, 5)
    @variable(
        model,
        nodes[1:(inst.n_total), 1:(inst.num_trucks)] in Hexaly.PartitionPD(
            inst.num_services,
            inst.num_pickup_deliveries,
            inst.num_trucks,
        ),
    )
    for i = 1:(inst.num_trucks)
        @constraint(model, nodes[:, i] in Hexaly.Capacity(inst.delta, inst.capacity))
    end
    @objective(
        model,
        Min,
        sum(
            Hexaly.op_sum_distances(inst.M, vcat(inst.depot, nodes[:, i], inst.depot))
            for i = 1:(inst.num_trucks)
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

@testset "CVRP" begin
    # With `quantities ∈ 2:4` and `capacity = 5`, a single-truck route that
    # picks up both pairs before delivering either would exceed 5 — the
    # solver must either split the pairs across trucks or interleave them.
    inst = _build_instance(
        seed = 1234,
        num_services = 2,
        num_pickup_deliveries = 2,
        num_trucks = 2,
        capacity = 5,
    )
    raw_routes, raw_obj = _solve_raw(inst)
    jump_routes, jump_obj = _solve_jump(inst)

    @testset "raw Python API" begin
        _check_cvrp!(raw_routes, inst)
        @test raw_obj == _route_cost(raw_routes, inst.dist_depot, inst.dist_matrix)
    end

    @testset "JuMP" begin
        _check_cvrp!(jump_routes, inst)
        @test jump_obj == _route_cost(jump_routes, inst.dist_depot, inst.dist_matrix)
    end

    @testset "raw and JuMP agree on the objective" begin
        @test raw_obj == jump_obj
    end
end
