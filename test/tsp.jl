using Test
import Hexaly
import MathOptInterface as MOI
using Random

@testset "TSP" begin
    n = 6
    Random.seed!(1234)
    x = rand(n)
    y = rand(n)
    d(i, j) = round(Int, 100hypot(x[i] - x[j], y[i] - y[j]))

    opt = Hexaly.Optimizer()
    MOI.set(opt, MOI.Silent(), true)
    MOI.set(opt, MOI.TimeLimitSec(), 10)

    next_ = [MOI.add_constrained_variable(opt, MOI.Interval(1, n))[1] for _ in 1:n]
    MOI.add_constraint(opt, MOI.VectorOfVariables(next_), MOI.Circuit(n))

    maxd = maximum(d(i, j) for i in 1:n for j in 1:n if i != j)
    cost = [MOI.add_constrained_variable(opt, MOI.Interval(0, maxd))[1] for _ in 1:n]

    for i in 1:n
        table = reduce(vcat, [[j  d(i, j)] for j in 1:n if j != i])
        MOI.add_constraint(
            opt,
            MOI.VectorOfVariables([next_[i], cost[i]]),
            MOI.Table(table),
        )
    end

    MOI.set(opt, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.set(
        opt,
        MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Int}}(),
        MOI.ScalarAffineFunction(
            [MOI.ScalarAffineTerm(1, c) for c in cost],
            0,
        ),
    )

    MOI.optimize!(opt)

    @test MOI.get(opt, MOI.TerminationStatus()) == MOI.OPTIMAL

    next_val = [round(Int, MOI.get(opt, MOI.VariablePrimal(), v)) for v in next_]
    cost_val = [round(Int, MOI.get(opt, MOI.VariablePrimal(), v)) for v in cost]

    visited = falses(n)
    cur = 1
    for _ in 1:n
        @test !visited[cur]
        visited[cur] = true
        cur = next_val[cur]
    end
    @test cur == 1
    @test all(visited)

    for i in 1:n
        @test cost_val[i] == d(i, next_val[i])
    end

    @test MOI.get(opt, MOI.ObjectiveValue()) == sum(cost_val)
end
