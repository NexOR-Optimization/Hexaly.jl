using Hexaly
using Test

@testset "Hexaly" begin
    @testset "Version" begin
        v = Hexaly.version()
        @test v isa VersionNumber
        @test v >= v"13"
        @info "Hexaly version: $v"
    end
end
