using Hexaly
using Hexaly.PythonCall
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
        @testset "TSP (raw Python API)" begin
            optimizer = Hexaly.raw_optimizer()
            # 4-city TSP with known optimal tour of cost 80:
            #   0 -10-> 1 -25-> 3 -30-> 2 -15-> 0
            dist = pylist([
                pylist([0, 10, 15, 20]),
                pylist([10, 0, 35, 25]),
                pylist([15, 35, 0, 30]),
                pylist([20, 25, 30, 0]),
            ])
            nb_cities = 4

            model = optimizer.model

            cities = model.list(nb_cities)
            model.constraint(model.count(cities) == nb_cities)

            dist_matrix = model.array(dist)

            obj = model.at(dist_matrix, cities[nb_cities - 1], cities[0])
            for k in 1:(nb_cities - 1)
                obj = obj + model.at(dist_matrix, cities[k - 1], cities[k])
            end
            model.minimize(obj)
            model.close()

            optimizer.param.time_limit = 5
            optimizer.param.verbosity = 0
            optimizer.solve()

            tour_cost = pyconvert(Int, obj.value)
            @test tour_cost == 80
            @info "TSP optimal cost: $tour_cost"

            optimizer.delete()
        end

        include("MOI_wrapper.jl")
        include("sudoku.jl")
        include("knapsack.jl")
    end
end
