using JuMP
using Hexaly
using PythonCall
using Test
import MathOptInterface as MOI
using Random

# CVRPTW instance: services + pickup/delivery pairs + per-customer time
# windows. Service time at node `v` is the affine function
# `fixed_time + slope * |delta[v]|`, so service nodes take `fixed_time` and
# pickup/delivery nodes take longer in proportion to the quantity handled.
function _build_instance(;
    seed::Int,
    num_services::Int,
    num_pickup_deliveries::Int,
    num_trucks::Int,
    capacity::Int,
    fixed_time::Int,
    slope::Int,
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
    delta = zeros(Int, n_total)
    for k = 1:num_pickup_deliveries
        delta[num_services+k] = quantities[k]
        delta[num_services+num_pickup_deliveries+k] = -quantities[k]
    end

    earliest = [rand(0:30) for _ = 1:n_total]
    latest = [earliest[c] + 400 for c = 1:n_total]

    # Full `(n_total + 1) × (n_total + 1)` travel matrix used by the JuMP
    # encoding; depot at Hexaly index `n_total`.
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
        earliest,
        latest,
        fixed_time,
        slope,
        M,
        depot,
    )
end

# Sum of truck makespans, recomputed from the solution. A truck's
# makespan is the time it returns to the depot: travel + waiting (if it
# arrives before `earliest`) + affine service `fixed_time + slope * |delta[v]|`
# + return travel. Empty trucks contribute 0.
function _route_total_time(routes, inst)
    total = 0
    for r in routes
        isempty(r) && continue
        t = 0
        for (k, v) in enumerate(r)
            travel = k == 1 ? inst.dist_depot[v+1] : inst.dist_matrix[r[k-1]+1, v+1]
            arrival = t + travel
            start = max(inst.earliest[v+1], arrival)
            svc = inst.fixed_time + inst.slope * abs(inst.delta[v+1])
            t = start + svc
        end
        total += t + inst.dist_depot[r[end]+1]
    end
    return total
end

# Independently re-simulate each route to validate partition, PD pairing,
# capacity and time-window feasibility.
function _check_cvrptw!(routes, inst)
    @test sort(reduce(vcat, routes)) == collect(0:(inst.n_total-1))
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
    for r in routes
        isempty(r) && continue
        load = 0
        t = 0
        for (k, v) in enumerate(r)
            travel = k == 1 ? inst.dist_depot[v+1] : inst.dist_matrix[r[k-1]+1, v+1]
            arrival = t + travel
            start = max(inst.earliest[v+1], arrival)
            @test start <= inst.latest[v+1]
            load += inst.delta[v+1]
            @test 0 <= load <= inst.capacity
            svc = inst.fixed_time + inst.slope * abs(inst.delta[v+1])
            t = start + svc
        end
        @test load == 0
    end
end

# Pure-Hexaly CVRPTW solve: list per truck, partition + PD pairing,
# cumulative load array, per-position capacity constraint, end-of-service
# time array using the affine service time, per-customer time window.
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
    earliest_arr = m.array(pylist(inst.earliest))
    latest_arr = m.array(pylist(inst.latest))
    delta_arr = m.array(pylist(inst.delta))
    service_vals = [inst.fixed_time + inst.slope * abs(inst.delta[v]) for v = 1:n_total]
    service_arr = m.array(pylist(service_vals))

    route_times = Py[]
    for k = 1:(inst.num_trucks)
        seq = routes[k]
        c = m.count(seq)

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

        end_time = m.array(
            m.range(0, c),
            m.lambda_function(
                pyfunc(
                    (i, prev) -> m.iif(
                        i == 0,
                        m.max(m.at(earliest_arr, seq[0]), m.at(depot_arr, seq[0])) +
                        m.at(service_arr, seq[0]),
                        m.max(
                            m.at(earliest_arr, seq[i]),
                            prev + m.at(dist_arr, seq[i-1], seq[i]),
                        ) + m.at(service_arr, seq[i]),
                    );
                    wrap = "lambda f: lambda i, prev: f(i, prev)",
                ),
            ),
            Py(0),
        )

        m.constraint(
            m.and_(
                m.range(0, c),
                m.lambda_function(
                    pyfunc(
                        i -> end_time[i] - m.at(service_arr, seq[i]) <=
                             m.at(latest_arr, seq[i]);
                        wrap = "lambda f: lambda i: f(i)",
                    ),
                ),
            ),
        )

        # Truck makespan = end_time at last customer + return travel to
        # depot (or 0 if the truck never leaves the depot).
        rt = m.iif(c > 0, end_time[c-1] + m.at(depot_arr, seq[c-1]), Py(0))
        push!(route_times, rt)
    end

    total = m.sum(route_times...)
    m.minimize(total)
    m.close()

    optimizer.param.time_limit = 5
    optimizer.param.verbosity = 0
    optimizer.solve()

    route_vals = [[pyconvert(Int, x) for x in seq.value] for seq in routes]
    obj = pyconvert(Int, total.value)
    return route_vals, obj
end

# JuMP / MOI solve: `Hexaly.PartitionPD` for the truck columns (partition +
# PD pairing), one combined `Hexaly.CapacitatedTimeWindows` constraint per
# truck (capacity + TW + makespan linkage `t[i] >= total_time_i`), and a
# `sum(t)` objective so the makespan of every truck is minimised.
function _solve_jump(inst)
    GC.gc()
    model = Model(Hexaly.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, 5)
    @variable(model, t[1:(inst.num_trucks)] >= 0)
    @variable(
        model,
        nodes[1:(inst.n_total), 1:(inst.num_trucks)] in Hexaly.PartitionPD(
            inst.num_services,
            inst.num_pickup_deliveries,
            inst.num_trucks,
        ),
    )
    for i = 1:(inst.num_trucks)
        @constraint(
            model,
            [t[i]; inst.depot; nodes[:, i]; inst.depot] in
            Hexaly.CapacitatedTimeWindows(
                inst.M,
                inst.earliest,
                inst.latest,
                inst.fixed_time,
                inst.slope,
                inst.delta,
                inst.capacity,
            )
        )
    end
    @objective(model, Min, sum(t))
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

@testset "CVRPTW" begin
    inst = _build_instance(
        seed = 1234,
        num_services = 2,
        num_pickup_deliveries = 2,
        num_trucks = 2,
        capacity = 5,
        fixed_time = 2,
        slope = 1,
    )
    raw_routes, raw_obj = _solve_raw(inst)
    jump_routes, jump_obj = _solve_jump(inst)

    @testset "raw Python API" begin
        _check_cvrptw!(raw_routes, inst)
        @test raw_obj == _route_total_time(raw_routes, inst)
    end

    @testset "JuMP" begin
        _check_cvrptw!(jump_routes, inst)
        @test jump_obj == _route_total_time(jump_routes, inst)
    end

    @testset "raw and JuMP agree on the objective" begin
        @test raw_obj == jump_obj
    end
end
