module TestHexaly

using Test
import MathOptInterface as MOI
import Hexaly

function runtests()
    for name in names(@__MODULE__; all = true)
        if startswith("$(name)", "test_")
            @testset "$(name)" begin
                getfield(@__MODULE__, name)()
            end
        end
    end
    return
end

function _silent(opt::Hexaly.Optimizer, t::Int = 2)
    MOI.set(opt, MOI.Silent(), true)
    MOI.set(opt, MOI.TimeLimitSec(), t)
    return
end

function test_solver_name()
    opt = Hexaly.Optimizer()
    @test MOI.get(opt, MOI.SolverName()) == "Hexaly"
end

function test_empty()
    opt = Hexaly.Optimizer()
    @test MOI.is_empty(opt)
    MOI.add_variable(opt)
    @test !MOI.is_empty(opt)
    MOI.empty!(opt)
    @test MOI.is_empty(opt)
end

function test_time_limit()
    opt = Hexaly.Optimizer()
    MOI.set(opt, MOI.TimeLimitSec(), 7.0)
    @test MOI.get(opt, MOI.TimeLimitSec()) == 7.0
    MOI.set(opt, MOI.TimeLimitSec(), nothing)
    @test MOI.get(opt, MOI.TimeLimitSec()) == Float64(Hexaly._DEFAULT_TIME_LIMIT)
end

function test_integer_unconstrained_objective()
    # minimize x: x in [2, 10], integer → optimum at x = 2.
    opt = Hexaly.Optimizer()
    _silent(opt)
    x, _ = MOI.add_constrained_variable(opt, MOI.Integer())
    MOI.add_constraint(opt, x, MOI.GreaterThan(2))
    MOI.add_constraint(opt, x, MOI.LessThan(10))
    MOI.set(opt, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.set(opt, MOI.ObjectiveFunction{MOI.VariableIndex}(), x)
    MOI.optimize!(opt)
    @test MOI.get(opt, MOI.TerminationStatus()) == MOI.OPTIMAL
    @test MOI.get(opt, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
    @test MOI.get(opt, MOI.VariablePrimal(), x) == 2
    @test MOI.get(opt, MOI.ObjectiveValue()) == 2
end

function test_linear_objective_and_constraint()
    # maximize 3x + 2y
    # s.t. x + y ≤ 4, x, y ∈ {0, 1, 2, 3}
    # Optimum: x=3, y=1 (since max for x+y=4 is 3*3+2*1 = 11).
    opt = Hexaly.Optimizer()
    _silent(opt)
    x, _ = MOI.add_constrained_variable(opt, MOI.Interval(0, 3))
    y, _ = MOI.add_constrained_variable(opt, MOI.Interval(0, 3))

    f = MOI.ScalarAffineFunction(
        [MOI.ScalarAffineTerm(1, x), MOI.ScalarAffineTerm(1, y)],
        0,
    )
    MOI.add_constraint(opt, f, MOI.LessThan(4))

    obj = MOI.ScalarAffineFunction(
        [MOI.ScalarAffineTerm(3, x), MOI.ScalarAffineTerm(2, y)],
        0,
    )
    MOI.set(opt, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    MOI.set(opt, MOI.ObjectiveFunction{typeof(obj)}(), obj)
    MOI.optimize!(opt)

    @test MOI.get(opt, MOI.TerminationStatus()) == MOI.OPTIMAL
    xv = MOI.get(opt, MOI.VariablePrimal(), x)
    yv = MOI.get(opt, MOI.VariablePrimal(), y)
    @test xv + yv <= 4
    @test MOI.get(opt, MOI.ObjectiveValue()) == 3 * xv + 2 * yv
    @test MOI.get(opt, MOI.ObjectiveValue()) == 11
end

function test_binary()
    # maximize x + y: x, y ∈ {0, 1}, x + y ≤ 1 → optimum = 1.
    opt = Hexaly.Optimizer()
    _silent(opt)
    x, _ = MOI.add_constrained_variable(opt, MOI.ZeroOne())
    y, _ = MOI.add_constrained_variable(opt, MOI.ZeroOne())
    MOI.add_constraint(
        opt,
        MOI.ScalarAffineFunction(
            [MOI.ScalarAffineTerm(1, x), MOI.ScalarAffineTerm(1, y)],
            0,
        ),
        MOI.LessThan(1),
    )
    MOI.set(opt, MOI.ObjectiveSense(), MOI.MAX_SENSE)
    MOI.set(
        opt,
        MOI.ObjectiveFunction{MOI.ScalarAffineFunction{Int}}(),
        MOI.ScalarAffineFunction(
            [MOI.ScalarAffineTerm(1, x), MOI.ScalarAffineTerm(1, y)],
            0,
        ),
    )
    MOI.optimize!(opt)
    @test MOI.get(opt, MOI.TerminationStatus()) == MOI.OPTIMAL
    @test MOI.get(opt, MOI.ObjectiveValue()) == 1
end

function test_alldifferent()
    opt = Hexaly.Optimizer()
    _silent(opt)
    x = MOI.VariableIndex[]
    for _ in 1:3
        vi, _ = MOI.add_constrained_variable(opt, MOI.Interval(1, 3))
        push!(x, vi)
    end
    MOI.add_constraint(opt, MOI.VectorOfVariables(x), MOI.AllDifferent(3))
    MOI.optimize!(opt)
    @test MOI.get(opt, MOI.TerminationStatus()) == MOI.OPTIMAL
    vals = sort!([MOI.get(opt, MOI.VariablePrimal(), v) for v in x])
    @test vals == [1, 2, 3]
end

function test_double_solve()
    opt = Hexaly.Optimizer()
    _silent(opt)
    x, _ = MOI.add_constrained_variable(opt, MOI.Interval(1, 5))
    MOI.set(opt, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.set(opt, MOI.ObjectiveFunction{MOI.VariableIndex}(), x)
    MOI.optimize!(opt)
    @test MOI.get(opt, MOI.ObjectiveValue()) == 1
end

end  # module

TestHexaly.runtests()
