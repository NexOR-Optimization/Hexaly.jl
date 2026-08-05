# `MathOptVRP` sets are 1-based, Hexaly's `list` decision variables are
# 0-based. Rather than special-casing the offset everywhere, we let a
# variable bridge do it once: the model sent to Hexaly is written with the
# 0-based sets of `sets.jl` and every occurrence of a node variable in the
# user's functions is substituted by `y + 1`.
#
# `_shift_to_zero_based` in `sum_distances_objective.jl` takes the `-1` back
# out when lowering `:sum_distances` and the routing constraints, so the two
# offsets cancel and Hexaly indexes its arrays 0-based as it expects.

"""
    ZeroBasedBridge{T,S1,S2} <: MOI.Bridges.Variable.SetMapBridge{T,S1,S2}

Bridges the 1-based `MathOptVRP` set `S2` into its 0-based Hexaly
counterpart `S1` with the substitution rule `x = y + 1`.

Because the map is a translation, its linear part is the identity, so both
adjoint maps are the identity as well.
"""
struct ZeroBasedBridge{T,S1,S2} <:
       MOI.Bridges.Variable.SetMapBridge{T,S1,S2}
    variables::Vector{MOI.VariableIndex}
    constraint::MOI.ConstraintIndex{MOI.VectorOfVariables,S1}
end

"""
    ListBridge{T} = ZeroBasedBridge{T,List,MathOptVRP.List}

Bridges `MathOptVRP.List(n)` into [`List(n)`](@ref).
"""
const ListBridge{T} = ZeroBasedBridge{T,List,MathOptVRP.List}

"""
    PartitionBridge{T} = ZeroBasedBridge{T,Partition,MathOptVRP.Partition}

Bridges `MathOptVRP.Partition` into [`Partition`](@ref).
"""
const PartitionBridge{T} = ZeroBasedBridge{T,Partition,MathOptVRP.Partition}

"""
    PartitionPDBridge{T} = ZeroBasedBridge{T,PartitionPD,MathOptVRP.PartitionPD}

Bridges `MathOptVRP.PartitionPD` into [`PartitionPD`](@ref).
"""
const PartitionPDBridge{T} =
    ZeroBasedBridge{T,PartitionPD,MathOptVRP.PartitionPD}

# `map_set` goes Hexaly -> MathOptVRP, `inverse_map_set` the other way; the
# shape is unchanged, only the value convention differs.

MOI.Bridges.map_set(::Type{<:ListBridge}, s::List) = MathOptVRP.List(s.dimension)

function MOI.Bridges.inverse_map_set(::Type{<:ListBridge}, s::MathOptVRP.List)
    return List(s.dimension)
end

function MOI.Bridges.map_set(::Type{<:PartitionBridge}, s::Partition)
    return MathOptVRP.Partition(s.num_clients, s.num_trucks)
end

function MOI.Bridges.inverse_map_set(
    ::Type{<:PartitionBridge},
    s::MathOptVRP.Partition,
)
    return Partition(s.num_clients, s.num_trucks)
end

function MOI.Bridges.map_set(::Type{<:PartitionPDBridge}, s::PartitionPD)
    return MathOptVRP.PartitionPD(
        s.num_services,
        s.num_pickup_deliveries,
        s.num_trucks,
    )
end

function MOI.Bridges.inverse_map_set(
    ::Type{<:PartitionPDBridge},
    s::MathOptVRP.PartitionPD,
)
    return PartitionPD(
        s.num_services,
        s.num_pickup_deliveries,
        s.num_trucks,
    )
end

# `MOI.Utilities.operate` wants the shift to match the shape of `func`: a
# scalar for `unbridged_map`'s `MOI.VariableIndex`, a vector for the
# functions and for the solution vectors of `MOI.VariablePrimal`.
function _translate(::Type{T}, func::Vector, α::T) where {T}
    return func .+ α
end

function _translate(::Type{T}, func::MOI.AbstractVectorFunction, α::T) where {T}
    return MOI.Utilities.operate(+, T, func, fill(α, MOI.output_dimension(func)))
end

function _translate(::Type{T}, func, α::T) where {T}
    return MOI.Utilities.operate(+, T, func, α)
end

function MOI.Bridges.map_function(::Type{<:ZeroBasedBridge{T}}, func) where {T}
    return _translate(T, func, one(T))
end

function MOI.Bridges.inverse_map_function(
    ::Type{<:ZeroBasedBridge{T}},
    func,
) where {T}
    return _translate(T, func, -one(T))
end

MOI.Bridges.adjoint_map_function(::Type{<:ZeroBasedBridge}, func) = func

function MOI.Bridges.inverse_adjoint_map_function(
    ::Type{<:ZeroBasedBridge},
    func,
)
    return func
end
