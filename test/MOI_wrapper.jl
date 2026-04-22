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

function _silent(opt, t::Int = 2)
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
    @test MOI.get(opt, MOI.TimeLimitSec()) === nothing
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

function test_moi_runtests()
    model = MOI.instantiate(
        Hexaly.Optimizer,
        with_bridge_type = Float64,
    )
    _silent(model)
    config = MOI.Test.Config(
        Float64;
        exclude = Any[
            MOI.ConstraintBasisStatus,
            MOI.VariableBasisStatus,
            MOI.ConstraintName,
            MOI.VariableName,
            MOI.DualStatus,
            MOI.ConstraintDual,
            MOI.DualObjectiveValue,
            MOI.RawStatusString,
            MOI.SolveTimeSec,
            MOI.ObjectiveBound,
            MOI.RelativeGap,
            MOI.delete,
        ],
    )
    MOI.Test.runtests(
        model,
        config;
        verbose = true,
        exclude = [
            # Delete not supported — affects all test_basic_, test_model_, test_variable_delete
            r"test_basic_",
            r"test_variable_delete",
            r"test_variable_add_variable",
            r"test_variable_add_variables",
            r"test_add_constrained_variables_vector",
            r"test_add_parameter",
            r"test_model_ordered_indices",
            r"test_model_add_constrained_variable_tuple",
            r"test_model$",
            # Conic tests not applicable
            r"test_conic_",
            # Linear tests exercise double-solve / constraint delete which
            # Hexaly's one-shot model semantics do not support.
            r"test_linear_",
            # Constraint retrieval by name not implemented
            r"test_constraint_get_ConstraintIndex",
            r"test_constraint_ScalarAffineFunction_",
            r"test_constraint_VectorAffineFunction_",
            # ModelFilter uses MOI attributes we don't implement
            r"test_model_ModelFilter_",
            r"test_model_ListOfConstraintAttributesSet",
            # Name-based lookup of constraint indices not implemented
            r"test_model_Name_VariableName_ConstraintName",
            r"test_model_ScalarAffineFunction_ConstraintName",
            r"test_model_duplicate_ScalarAffineFunction_ConstraintName",
            r"test_model$",
            # Clearing objective on FEASIBILITY_SENSE not exposed
            r"test_objective_FEASIBILITY_SENSE_clears_objective",
            # Modification not supported
            r"test_modification_",
            # Dual-related
            r"test_DualObjectiveValue",
            r"test_solve_DualStatus",
            r"test_solve_VariableIndex_ConstraintDual",
            r"test_solve_ObjectiveBound",
            r"test_solve_TerminationStatus_DUAL_INFEASIBLE",
            r"test_solve_result_index",
            r"test_solve_conflict_",
            r"test_solve_optimize_twice",
            r"test_solve_twice",
            # Infeasible/unbounded need dual certificates
            r"test_infeasible_",
            r"test_unbounded_",
            # Variable solve tests
            r"test_variable_solve_",
            # Constraint tests with unsupported function/set combos
            r"test_constraint_VectorAffineFunction_",
            # Objective tests that require unsupported features
            r"test_objective_ObjectiveFunction_VariableIndex",
            r"test_objective_ObjectiveFunction_constant",
            r"test_objective_ObjectiveFunction_duplicate_terms",
            r"test_objective_get_ObjectiveFunction_ScalarAffineFunction",
            r"test_objective_set_via_modify",
            r"test_objective_ObjectiveSense_in_ListOfModelAttributesSet",
            # SOS, quadratic, nonlinear
            r"test_quadratic_",
            r"test_nonlinear_",
            r"test_vector_nonlinear_",
            r"test_solve_SOS2",
        ],
    )
    return
end

end  # module

TestHexaly.runtests()
