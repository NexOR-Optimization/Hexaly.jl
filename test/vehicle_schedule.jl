using Hexaly
using JuMP
using Test
import MathOptVRP
import MathOptInterface as MOI

# Nodes 1 and 2 with the depot 3: 10 from the depot to each, 5 between them.
const SCHEDULE_TRAVEL = [0 5 10; 5 0 10; 10 10 0]

function _schedule_model(; num_trips = 1, kwargs...)
    model = Model(Hexaly.Optimizer)
    set_silent(model)
    set_time_limit_sec(model, 2.0)
    @variable(model, route[1:2, 1:num_trips] in MathOptVRP.Partition(2, num_trips))
    @variable(model, trip_start[1:num_trips], Int)
    @variable(model, trip_end[1:num_trips], Int)
    @variable(model, taken, Bin)
    @variable(model, break_start, Int)
    @variable(model, visit_start[1:2], Int)
    set = MathOptVRP.VehicleSchedule(
        SCHEDULE_TRAVEL, 3, kwargs[:earliest], [1000, 1000], [5, 5];
        day = (0, 1000), num_trips, delete!(Dict(kwargs), :earliest)...,
    )
    @constraint(model,
        [trip_start; trip_end; taken; break_start; visit_start; vec(route)] in set)
    @expression(model, day_start, trip_start[1])
    @expression(model, day_end, trip_end[end])
    @objective(model, Min, day_end - day_start)
    return model
end

@testset "MathOptVRP.VehicleSchedule" begin
    @testset "Departure avoids waiting" begin
        model = _schedule_model(; earliest = [0, 30])
        route, taken = model[:route], model[:taken]
        @constraint(model, route[:, 1] in
            MathOptVRP.RouteOrder(Bool[true, false], Bool[false, true]))
        fix(taken, 0)
        optimize!(model)
        @test primal_status(model) == MOI.FEASIBLE_POINT
        @test value.(route) == reshape([1, 2], 2, 1)
        # Any departure from 10 meets node 2 at its earliest time or later.
        day_start, visit_start = value(model[:day_start]), value.(model[:visit_start])
        @test day_start >= 10
        @test visit_start == day_start .+ [10, 20]
        @test value(model[:day_end]) == day_start + 35
        raw = unsafe_backend(model)
        @test Hexaly._info(raw, index(model[:visit_start][1])).is_defined
        @test Hexaly._info(raw, index(model[:trip_end][1])).is_defined
    end

    @testset "Break" begin
        model = _schedule_model(;
            earliest = [0, 30], break_length = 10, break_window = (20, 20))
        route = model[:route]
        @constraint(model, route[:, 1] in
            MathOptVRP.RouteOrder(Bool[true, false], Bool[false, true]))
        fix(model[:taken], 1)
        optimize!(model)
        @test value(model[:break_start]) == 20
        @test value(model[:day_end]) - value(model[:day_start]) == 45
        @test value(model[:visit_start][2]) >= 30
    end

    @testset "Reload between trips" begin
        model = _schedule_model(;
            earliest = [0, 0], num_trips = 2, reload_fixed = 7, reload = [1, 2])
        route = model[:route]
        for t in 1:2
            @constraint(model, route[:, t] in MathOptVRP.Capacity([1, 1], 1))
        end
        fix(model[:taken], 0)
        @variable(model, distance[1:2])
        for t in 1:2
            @constraint(model, [distance[t]; route[:, t]] in
                MathOptVRP.SumDistances(SCHEDULE_TRAVEL, 3, 3, 2))
        end
        @constraint(model, distance[1] + distance[2] <= 40)
        optimize!(model)
        @test value(route[1, 2]) == 1
        @test value(model[:day_end]) - value(model[:day_start]) == 25 + 8 + 25
        trip_start, trip_end = value.(model[:trip_start]), value.(model[:trip_end])
        @test trip_end[1] - trip_start[1] == 25 == trip_end[2] - trip_start[2]
        @test trip_start[2] >= trip_end[1] + 8
        @test value.(distance) == [20, 20]
    end

    @testset "Waiting for another visit" begin
        model = _schedule_model(; earliest = [0, 0])
        route, visit_start = model[:route], model[:visit_start]
        @constraint(model, route[:, 1] in
            MathOptVRP.RouteOrder(Bool[true, false], Bool[false, true]))
        fix(model[:taken], 0)
        @constraint(model, visit_start[2] >= visit_start[1] + 30)
        optimize!(model)
        @test primal_status(model) == MOI.FEASIBLE_POINT
        @test value(visit_start[2]) - value(visit_start[1]) == 30
        @test value(model[:day_end]) - value(model[:day_start]) == 55
    end
end
