# Hexaly's counterparts of the `MathOptVRP` variable sets. They have the
# same shape, the difference is the value convention: a Hexaly `list`
# decision variable takes values in `0:n-1` and Hexaly indexes arrays
# 0-based, while `MathOptVRP` is 1-based like the rest of MOI. The
# `ZeroBasedBridge`s of `bridges.jl` convert between the two, so a model
# written against `MathOptVRP` never sees these sets.

"""
    List(dimension::Int)

The 0-based counterpart of [`MathOptVRP.List`](@ref): the `dimension`
variables form a permutation of `0:dimension-1`.
"""
struct List <: MOI.AbstractVectorSet
    dimension::Int
end

MOI.dimension(s::List) = s.dimension

"""
    Partition(num_clients::Int, num_trucks::Int)

The 0-based counterpart of [`MathOptVRP.Partition`](@ref): the columns
together partition `0:num_clients-1`.
"""
struct Partition <: MOI.AbstractVectorSet
    num_clients::Int
    num_trucks::Int
end

MOI.dimension(s::Partition) = s.num_clients * s.num_trucks

"""
    PartitionPD(num_services::Int, num_pickup_deliveries::Int, num_trucks::Int)

The 0-based counterpart of [`MathOptVRP.PartitionPD`](@ref).
"""
struct PartitionPD <: MOI.AbstractVectorSet
    num_services::Int
    num_pickup_deliveries::Int
    num_trucks::Int
end

_pd_n_total(s::PartitionPD) = s.num_services + 2 * s.num_pickup_deliveries

MOI.dimension(s::PartitionPD) = _pd_n_total(s) * s.num_trucks
