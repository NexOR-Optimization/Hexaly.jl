using JuMP
using Test
import Hexaly
import MathOptInterface as MOI
using Random

@testset "TSP (JuMP + Hexaly.List + sum_distances)" begin
    Random.seed!(1234)
    n = 6
    x = rand(n)
    y = rand(n)
    d(i, j) = round(Int, 100hypot(x[i] - x[j], y[i] - y[j]))
    dist = [d(i, j) for i = 1:n, j = 1:n]

    model = Model(Hexaly.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, 5)

    @variable(model, nodes[1:n] in Hexaly.List(n))
    @objective(model, Min, Hexaly.op_sum_distances(dist, nodes))

    optimize!(model)

    @test termination_status(model) in (MOI.OPTIMAL, MOI.LOCALLY_SOLVED)

    seq = [round(Int, value(v)) for v in nodes]
    @test sort(seq) == collect(0:(n-1))

    expected = 0
    for k = 1:n
        a = seq[k]
        b = seq[mod1(k + 1, n)]
        expected += dist[a+1, b+1]
    end
    @test round(Int, objective_value(model)) == expected
end
