using Hexaly
using PythonCall
using Test
using Random

# VRPTW instance: same shape as `vrp.jl` plus a time window `[earliest_i,
# latest_i]` per customer and a fixed service time. Time = distance (1 unit
# of distance == 1 unit of time, so we can reuse the distance matrix).
function _build_instance(; seed::Int, n_customers::Int, n_trucks::Int)
    Random.seed!(seed)
    cx = rand(n_customers + 1)
    cy = rand(n_customers + 1)
    d(i, j) = round(Int, 100hypot(cx[i] - cx[j], cy[i] - cy[j]))
    dist_depot = [d(1, c + 1) for c = 1:n_customers]
    dist_matrix = [d(i + 1, j + 1) for i = 1:n_customers, j = 1:n_customers]
    service_time = 5
    # Windows wide enough that the instance is feasible for any reasonable
    # partition (max one-truck round-trip in this instance is ~ 4·100 + a
    # handful of service times).
    earliest = [rand(0:30) for _ = 1:n_customers]
    latest = [earliest[c] + 300 for c = 1:n_customers]
    return (;
        n_customers,
        n_trucks,
        dist_depot,
        dist_matrix,
        service_time,
        earliest,
        latest,
    )
end

# Recompute the total VRP cost (closed routes with depot legs).
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

# Simulate the route timing the same way the Hexaly model does and return
# `(max_lateness, ok::Bool)`. `start_service[k] = max(arrival, earliest[c])`,
# `end_service[k] = start_service[k] + service_time`. The route is feasible
# iff `start_service[k] <= latest[c]` for every visited customer.
function _check_time_windows(routes, inst)
    max_late = 0
    ok = true
    for r in routes
        isempty(r) && continue
        t = 0
        for (k, c) in enumerate(r)
            travel = k == 1 ? inst.dist_depot[c+1] : inst.dist_matrix[r[k-1]+1, c+1]
            arrival = t + travel
            start = max(inst.earliest[c+1], arrival)
            late = start - inst.latest[c+1]
            if late > 0
                max_late = max(max_late, late)
                ok = false
            end
            t = start + inst.service_time
        end
    end
    return max_late, ok
end

# Solve the VRPTW with the raw Hexaly Python API: one `model.list` per
# truck, a `model.partition` over them, and per-truck distance + a
# recursive `model.array(range, lambda(i, prev), 0)` for the end-of-service
# time. Lexicographic objectives: minimise total lateness, then total
# distance — for a feasible instance the lateness optimum is 0.
function _solve_raw(inst)
    # Force a Julia + Python GC so any orphaned `Py` reference to a Hexaly
    # optimizer from a previous (errored) run is finalised and its license
    # token is released before we ask for a new one.
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
    n = inst.n_customers
    service = inst.service_time

    routes = [m.list(n) for _ = 1:inst.n_trucks]
    m.constraint(m.partition(pylist(routes)))

    dist_arr = m.array(pylist([pylist(inst.dist_matrix[i, :]) for i = 1:n]))
    depot_arr = m.array(pylist(inst.dist_depot))
    earliest_arr = m.array(pylist(inst.earliest))
    latest_arr = m.array(pylist(inst.latest))

    route_dists = Py[]
    route_lateness = Py[]
    for k = 1:inst.n_trucks
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

        # End-of-service time at the i-th customer in this truck.
        #   end_time[0]  = max(earliest[seq[0]], dist_depot[seq[0]]) + service
        #   end_time[i]  = max(earliest[seq[i]], end_time[i-1] + dist[seq[i-1], seq[i]]) + service
        end_time = m.array(
            m.range(0, c),
            m.lambda_function(
                pyfunc(
                    (i, prev) -> m.iif(
                        i == 0,
                        m.max(
                            m.at(earliest_arr, seq[0]),
                            m.at(depot_arr, seq[0]),
                        ) + Py(service),
                        m.max(
                            m.at(earliest_arr, seq[i]),
                            prev + m.at(dist_arr, seq[i-1], seq[i]),
                        ) + Py(service),
                    );
                    wrap = "lambda f: lambda i, prev: f(i, prev)",
                ),
            ),
            Py(0),
        )

        # Lateness per visited customer = max(0, start_service - latest)
        # where start_service = end_time[i] - service.
        late = m.lambda_function(
            pyfunc(
                i -> m.max(Py(0), end_time[i] - Py(service) - m.at(latest_arr, seq[i]));
                wrap = "lambda f: lambda i: f(i)",
            ),
        )
        push!(route_lateness, m.sum(m.range(0, c), late))
    end

    total_dist = m.sum(route_dists...)
    total_late = m.sum(route_lateness...)

    # Lexicographic: feasibility (lateness == 0) dominates distance.
    m.minimize(total_late)
    m.minimize(total_dist)
    m.close()

    optimizer.param.time_limit = 5
    optimizer.param.verbosity = 0
    optimizer.solve()

    route_vals = [[pyconvert(Int, x) for x in seq.value] for seq in routes]
    obj_dist = pyconvert(Int, total_dist.value)
    obj_late = pyconvert(Int, total_late.value)

    return route_vals, obj_dist, obj_late
end

@testset "VRPTW (raw Python API)" begin
    inst = _build_instance(seed = 1234, n_customers = 4, n_trucks = 2)
    routes, obj_dist, obj_late = _solve_raw(inst)

    # Partition validity.
    @test sort(reduce(vcat, routes)) == collect(0:(inst.n_customers-1))

    # Time-window feasibility: lateness == 0 and an independent simulation
    # of arrival / wait / service times also confirms no customer is late.
    @test obj_late == 0
    max_late, ok = _check_time_windows(routes, inst)
    @test ok
    @test max_late == 0

    # The reported distance objective matches a manual recomputation.
    @test obj_dist == _route_cost(routes, inst.dist_depot, inst.dist_matrix)
end
