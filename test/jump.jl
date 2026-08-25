using Hexaly
using JuMP
using Test
import MathOptVRP
import MathOptInterface as MOI

@testset "MathOptVRP sequence sets" begin
    model = Model(Hexaly.Optimizer)
    set_time_limit_sec(model, 2.0)
    set_silent(model)
    @variable(model, route[1:7, 1:3] in MathOptVRP.Partition(7, 3))
    @constraint(model, route[:, 1] in MathOptVRP.RouteCompatibility(
        Bool[true, true, false, false, false, false, false],
    ))
    @constraint(model, route[:, 2] in MathOptVRP.RouteCompatibility(
        Bool[false, false, true, true, false, false, false],
    ))
    @constraint(model, route[:, 3] in MathOptVRP.RouteCompatibility(
        Bool[false, false, false, false, true, true, true],
    ))
    @constraint(model, route[:, 1] in MathOptVRP.RouteOrder(
        Bool[false, true, false, false, false, false, false],
        Bool[true, false, false, false, false, false, false],
    ))
    @constraint(model, route[:, 2] in MathOptVRP.RouteOrder(
        Bool[false, false, false, true, false, false, false],
        Bool[false, false, true, false, false, false, false],
    ))
    @constraint(model, route[:, 3] in MathOptVRP.RouteExtremities(
        Bool[false, false, false, false, true, true, false],
    ))
    optimize!(model)
    @test termination_status(model) in (MOI.OPTIMAL, MOI.TIME_LIMIT)
    values = round.(Int, value.(route))
    @test values[1:2, 1] == [2, 1]
    @test values[1:2, 2] == [4, 3]
    @test values[2, 3] == 7
    @test Set(values[[1, 3], 3]) == Set([5, 6])
end

@testset "MathOptVRP defined route values" begin
    model = Model(Hexaly.Optimizer)
    set_time_limit_sec(model, 2.0)
    set_silent(model)
    @variable(model, route[1:3, 1:2] in MathOptVRP.Partition(3, 2))
    @variable(model, empty[1:2], Bin)
    @variable(model, total[1:2])
    for r in 1:2
        @constraint(model, [empty[r]; route[:, r]] in MathOptVRP.IsEmpty(3))
        @constraint(model,
            [total[r]; route[:, r]] in MathOptVRP.SumGetIndex([2, 3, 5]))
    end
    @constraint(model, !empty[2] => { empty[1] := false })
    @constraint(model, route[:, 2] in
        MathOptVRP.RouteCompatibility(Bool[false, false, false]))
    @objective(model, Min, total[1] + total[2])
    optimize!(model)
    @test termination_status(model) == MOI.OPTIMAL
    @test round.(Int, value.(empty)) == [0, 1]
    @test round.(Int, value.(total)) == [10, 0]
    raw = unsafe_backend(model)
    @test Hexaly._info(raw, index(empty[1])).is_defined
    @test Hexaly._info(raw, index(total[1])).is_defined
end

# The routes are read back from the `Partition` variables themselves: a
# truck's column holds the clients it visits followed by `0`s, so
# `MathOptVRP.Tests` needs nothing Hexaly-specific to recover them. See
# `Hexaly._add_list_variables!` for the trailing `0` sentinel.
MathOptVRP.Tests.runtests(Hexaly.Optimizer)
