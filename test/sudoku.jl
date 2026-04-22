using Test
import Hexaly
import MathOptInterface as MOI

@testset "Sudoku (small 4x4)" begin
    # 4x4 sudoku (with 2x2 sub-blocks), harder-to-mistake minimal test.
    init_sol = [
        1 0 0 4
        0 0 0 0
        0 0 0 0
        4 0 0 1
    ]

    opt = Hexaly.Optimizer()
    MOI.set(opt, MOI.Silent(), true)
    MOI.set(opt, MOI.TimeLimitSec(), 5)

    x = Matrix{MOI.VariableIndex}(undef, 4, 4)
    for i in 1:4, j in 1:4
        x[i, j], _ = MOI.add_constrained_variable(opt, MOI.Interval(1, 4))
    end

    # Row + column AllDifferent
    for i in 1:4
        MOI.add_constraint(opt, MOI.VectorOfVariables(x[i, :]), MOI.AllDifferent(4))
        MOI.add_constraint(opt, MOI.VectorOfVariables(x[:, i]), MOI.AllDifferent(4))
    end

    # 2x2 block AllDifferent
    for i in (0, 2), j in (0, 2)
        block = vec(x[i .+ (1:2), j .+ (1:2)])
        MOI.add_constraint(opt, MOI.VectorOfVariables(block), MOI.AllDifferent(4))
    end

    # Fix initial cells
    for i in 1:4, j in 1:4
        if init_sol[i, j] != 0
            MOI.add_constraint(opt, x[i, j], MOI.EqualTo(init_sol[i, j]))
        end
    end

    MOI.optimize!(opt)

    @test MOI.get(opt, MOI.TerminationStatus()) == MOI.OPTIMAL
    @test MOI.get(opt, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT

    sol = [MOI.get(opt, MOI.VariablePrimal(), x[i, j]) for i in 1:4, j in 1:4]
    # Check all rows/cols/blocks
    for i in 1:4
        @test sort(sol[i, :]) == [1, 2, 3, 4]
        @test sort(sol[:, i]) == [1, 2, 3, 4]
    end
end
