using Hexaly
using PythonCall
using Test
using Random

@testset "VRP (raw Python API)" begin
    Random.seed!(1234)
    n_customers = 6
    n_trucks = 2

    cx = rand(n_customers + 1)
    cy = rand(n_customers + 1)
    d(i, j) = round(Int, 100hypot(cx[i] - cx[j], cy[i] - cy[j]))
    dist_depot = [d(1, c + 1) for c in 1:n_customers]
    dist_matrix = [d(i + 1, j + 1) for i in 1:n_customers, j in 1:n_customers]

    optimizer = Hexaly.raw_optimizer()
    m = optimizer.model

    routes = [m.list(n_customers) for _ in 1:n_trucks]
    m.constraint(m.partition(pylist(routes)))

    dist_arr = m.array(pylist([pylist(dist_matrix[i, :]) for i in 1:n_customers]))
    depot_arr = m.array(pylist(dist_depot))

    route_dists = Py[]
    for k in 1:n_trucks
        seq = routes[k]
        c = m.count(seq)
        leg = m.lambda_function(pyfunc(
            i -> m.at(dist_arr, seq[i - 1], seq[i]);
            wrap = "lambda f: lambda i: f(i)",
        ))
        rd = m.sum(m.range(1, c), leg) +
             m.iif(c > 0, m.at(depot_arr, seq[0]) + m.at(depot_arr, seq[c - 1]), 0)
        push!(route_dists, rd)
    end

    total = m.sum(route_dists...)
    m.minimize(total)
    m.close()

    optimizer.param.time_limit = 5
    optimizer.param.verbosity = 0
    optimizer.solve()

    route_vals = [[pyconvert(Int, x) for x in seq.value] for seq in routes]
    all_visits = reduce(vcat, route_vals)
    @test sort(all_visits) == collect(0:(n_customers - 1))

    expected = 0
    for r in route_vals
        if !isempty(r)
            expected += dist_depot[r[1] + 1] + dist_depot[r[end] + 1]
            for k in 2:length(r)
                expected += dist_matrix[r[k - 1] + 1, r[k] + 1]
            end
        end
    end
    @test pyconvert(Int, total.value) == expected

    optimizer.delete()
end
