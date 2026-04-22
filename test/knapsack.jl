using Test
import Hexaly
import MathOptInterface as MOI

@testset "Knapsack" begin
    # Classic 0/1 knapsack:
    # items with (weight, value):
    weights = [2, 3, 4, 5]
    values  = [3, 4, 5, 6]
    capacity = 5
    # Optimal: pick items 1 (w=2,v=3) and 3 (w=4,v=5) → w=6 > 5, infeasible.
    # So pick items 1 and 2: w=5, v=7.
    # Or items 3: w=4, v=5.
    # Or items 2 and 3: w=7 > 5.
    # Or items 1 and 4: w=7.
    # Best feasible: items 1 and 2 with v=7.

    opt = Hexaly.Optimizer()
    MOI.set(opt, MOI.Silent(), true)
    MOI.set(opt, MOI.TimeLimitSec(), 3)

    x = MOI.VariableIndex[]
    for _ in 1:length(weights)
        vi, _ = MOI.add_constrained_variable(opt, MOI.ZeroOne())
        push!(x, vi)
    end

    # capacity constraint: sum w_i x_i ≤ capacity
    MOI.add_constraint(
        opt,
        MOI.ScalarAffineFunction(
            [MOI.ScalarAffineTerm(weights[i], x[i]) for i in eachindex(x)],
            0,
        ),
        MOI.LessThan(capacity),
    )

    MOI.set(opt, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    MOI.set(
        opt,
        MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Int}}(),
        MOI.ScalarAffineFunction(
            [MOI.ScalarAffineTerm(values[i], x[i]) for i in eachindex(x)],
            0,
        ),
    )

    MOI.optimize!(opt)
    @test MOI.get(opt, MOI.TerminationStatus()) == MOI.OPTIMAL
    @test MOI.get(opt, MOI.ObjectiveValue()) == 7

    sel = [MOI.get(opt, MOI.VariablePrimal(), v) for v in x]
    @test sum(weights .* sel) <= capacity
end
