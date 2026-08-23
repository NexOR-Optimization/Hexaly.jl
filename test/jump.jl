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

# The routes are read back from the `Partition` variables themselves: a
# truck's column holds the clients it visits followed by `0`s, so
# `MathOptVRP.Tests` needs nothing Hexaly-specific to recover them. See
# `Hexaly._add_list_variables!` for the trailing `0` sentinel.
MathOptVRP.Tests.runtests(Hexaly.Optimizer)
