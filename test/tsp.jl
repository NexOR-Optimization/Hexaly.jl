using JuMP
using Hexaly
using Test
import MathOptInterface as MOI
using Random

# 2D random TSP instance shared by both formulations.
function _build_instance(; seed::Int, n::Int)
    Random.seed!(seed)
    x = rand(n)
    y = rand(n)
    d(i, j) = round(Int, 100hypot(x[i] - x[j], y[i] - y[j]))
    dist = [d(i, j) for i = 1:n, j = 1:n]
    return (; n, dist)
end

# Closed-tour cost from a 1-indexed tour expressed as `next[i] = successor of i`.
function _tour_from_next(next_val, n)
    tour = Int[]
    cur = 1
    for _ = 1:n
        push!(tour, cur)
        cur = next_val[cur]
    end
    return tour, cur  # cur should be 1 after closing the loop
end

# Closed-tour cost of a (1-indexed) cyclic sequence.
function _closed_cost(tour, dist)
    n = length(tour)
    return sum(dist[tour[k], tour[mod1(k + 1, n)]] for k = 1:n)
end

# Successor-variable formulation through raw MOI: `next` ∈ Circuit(n),
# `cost[i]` linked to `next[i]` via `MOI.Table`, objective = sum(cost).
function _solve_moi(inst)
    n = inst.n
    opt = Hexaly.Optimizer()
    MOI.set(opt, MOI.Silent(), true)
    MOI.set(opt, MOI.TimeLimitSec(), 10)
    next_ = [MOI.add_constrained_variable(opt, MOI.Interval(1, n))[1] for _ = 1:n]
    MOI.add_constraint(opt, MOI.VectorOfVariables(next_), MOI.Circuit(n))
    maxd = maximum(inst.dist[i, j] for i = 1:n for j = 1:n if i != j)
    cost = [MOI.add_constrained_variable(opt, MOI.Interval(0, maxd))[1] for _ = 1:n]
    for i = 1:n
        table = reduce(vcat, [[j inst.dist[i, j]] for j = 1:n if j != i])
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
        MOI.ScalarAffineFunction([MOI.ScalarAffineTerm(1, c) for c in cost], 0),
    )
    MOI.optimize!(opt)
    @test MOI.get(opt, MOI.TerminationStatus()) == MOI.OPTIMAL
    next_val = [round(Int, MOI.get(opt, MOI.VariablePrimal(), v)) for v in next_]
    cost_val = [round(Int, MOI.get(opt, MOI.VariablePrimal(), v)) for v in cost]
    obj = round(Int, MOI.get(opt, MOI.ObjectiveValue()))
    return (; next_val, cost_val, obj)
end

# Permutation formulation through JuMP: `nodes` is a Hexaly.List(n)
# decision variable (a permutation of `0:n-1`), objective via
# `Hexaly.op_sum_distances(dist, nodes)`.
function _solve_jump(inst)
    n = inst.n
    model = Model(Hexaly.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, 5)
    @variable(model, nodes[1:n] in Hexaly.List(n))
    @objective(model, Min, Hexaly.op_sum_distances(inst.dist, nodes))
    optimize!(model)
    @test termination_status(model) in (MOI.OPTIMAL, MOI.LOCALLY_SOLVED)
    seq = [round(Int, value(v)) for v in nodes]
    obj = round(Int, objective_value(model))
    return (; seq, obj)
end

@testset "TSP" begin
    inst = _build_instance(seed = 1234, n = 6)
    moi_sol = _solve_moi(inst)
    jump_sol = _solve_jump(inst)

    @testset "MOI (Circuit + Table)" begin
        # Walk the successor array: every node visited exactly once, returns to 1.
        tour, end_node = _tour_from_next(moi_sol.next_val, inst.n)
        @test end_node == 1
        @test sort(tour) == collect(1:(inst.n))
        # Per-edge costs match the table values.
        for i = 1:(inst.n)
            @test moi_sol.cost_val[i] == inst.dist[i, moi_sol.next_val[i]]
        end
        # Objective equals the recomputed closed-tour cost.
        @test moi_sol.obj == _closed_cost(tour, inst.dist)
        @test moi_sol.obj == sum(moi_sol.cost_val)
    end

    @testset "JuMP (Hexaly.List + op_sum_distances)" begin
        @test sort(jump_sol.seq) == collect(0:(inst.n-1))
        # Recompute the closed-tour cost from the permutation
        # (`seq` is 0-indexed; shift to Julia 1-indexing).
        tour = [c + 1 for c in jump_sol.seq]
        @test jump_sol.obj == _closed_cost(tour, inst.dist)
    end

    @testset "MOI and JuMP agree on the objective" begin
        @test moi_sol.obj == jump_sol.obj
    end
end
