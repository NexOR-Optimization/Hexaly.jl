using Hexaly
using Test

const CI = get(ENV, "CI", "false") == "true"
const HAS_LICENSE = Hexaly.has_license()

@testset "Hexaly" begin
    @testset "Version" begin
        v = Hexaly.version()
        @test v isa VersionNumber
        @test v >= v"13"
        @info "Hexaly version: $v"
    end

    @testset "License" begin
        if CI
            @test !HAS_LICENSE
        else
            @test HAS_LICENSE
        end
    end

    if HAS_LICENSE
        @testset "TSP (raw C API)" begin
            optimizer = Hexaly.raw_optimizer()
            # 4-city TSP with known optimal tour of cost 80:
            #   0 -10-> 1 -25-> 3 -30-> 2 -15-> 0
            dist = [
                [0, 10, 15, 20],
                [10, 0, 35, 25],
                [15, 35, 0, 30],
                [20, 25, 30, 0],
            ]
            nb_cities = 4

            md = Hexaly.model(optimizer)

            cities = Hexaly.list!(md, nb_cities)
            Hexaly.add_constraint!(md,
                Hexaly.eq(md, Hexaly.count_(md, cities), nb_cities))

            dist_rows = [Hexaly.array(md, row) for row in dist]
            dist_matrix = Hexaly.array(md, dist_rows)

            obj = Hexaly.at(md, dist_matrix,
                Hexaly.at(md, cities, nb_cities - 1),
                Hexaly.at(md, cities, 0))
            for k = 1:(nb_cities - 1)
                obj = Hexaly.sum(md, obj,
                    Hexaly.at(md, dist_matrix,
                        Hexaly.at(md, cities, k - 1),
                        Hexaly.at(md, cities, k)))
            end
            Hexaly.minimize!(md, obj)
            Hexaly.close!(md)

            p = Hexaly.param(optimizer)
            Hexaly.time_limit!(p, 5)
            Hexaly.verbosity!(p, 0)
            Hexaly.solve!(optimizer)

            tour_cost = Hexaly.value(obj; is_integer = true)
            @test tour_cost == 80
            @info "TSP optimal cost: $tour_cost"
        end

        include("MOI_wrapper.jl")
        include("sudoku.jl")
        include("knapsack.jl")
        # The VRP-variant JuMP tests live in `MathOptVRP`'s Test extension
        # and are run through `MathOptVRP.runtests` here with a Hexaly-
        # specific route reader. See `test/jump.jl` for that wiring.
        include("jump.jl")
    end
end
