function _info(m::Optimizer, key::MOI.ConstraintIndex)
    if haskey(m.constraint_info, key)
        return m.constraint_info[key]
    end
    throw(MOI.InvalidIndex(key))
end

function MOI.is_valid(
    m::Optimizer,
    c::MOI.ConstraintIndex{F,S},
) where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    info = get(m.constraint_info, c, nothing)
    return info !== nothing && typeof(info.set) == S && typeof(info.f) == F
end

function _add_hexaly_constraint!(m::Optimizer, expr::HxExpression)
    add_constraint!(m.model, expr)
    return
end

# ScalarAffineFunction-in-Set

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.ScalarAffineFunction{T}},
    ::Type{S},
) where {T<:Union{Int,Float64},S<:Union{MOI.EqualTo{T},MOI.LessThan{T},MOI.GreaterThan{T}}}
    return true
end

function MOI.add_constraint(
    m::Optimizer,
    f::MOI.ScalarAffineFunction{T},
    s::S,
) where {T<:Real,S<:Union{MOI.EqualTo{T},MOI.LessThan{T},MOI.GreaterThan{T}}}
    index = MOI.ConstraintIndex{MOI.ScalarAffineFunction{T},S}(
        length(m.constraint_info) + 1,
    )
    expr = _build_constraint(m, f, s)
    _add_hexaly_constraint!(m, expr)
    m.constraint_info[index] = ConstraintInfo(index, expr, f, s)
    return index
end

# VectorOfVariables CP constraints

function MOI.add_constraint(
    m::Optimizer,
    f::MOI.VectorOfVariables,
    s::S,
) where {S<:Union{MOI.AllDifferent,MOI.Circuit}}
    index = MOI.ConstraintIndex{MOI.VectorOfVariables,S}(length(m.constraint_info) + 1)
    expr = _build_constraint(m, f, s)
    _add_hexaly_constraint!(m, expr)
    m.constraint_info[index] = ConstraintInfo(index, expr, f, s)
    return index
end

function MOI.add_constraint(
    m::Optimizer,
    f::MOI.VectorOfVariables,
    s::MOI.BinPacking{T},
) where {T<:Real}
    index = MOI.ConstraintIndex{MOI.VectorOfVariables,MOI.BinPacking{T}}(
        length(m.constraint_info) + 1,
    )
    expr = _build_constraint(m, f, s)
    _add_hexaly_constraint!(m, expr)
    m.constraint_info[index] = ConstraintInfo(index, expr, f, s)
    return index
end

function MOI.add_constraint(
    m::Optimizer,
    f::MOI.VectorOfVariables,
    s::MOI.Table{T},
) where {T<:Real}
    index = MOI.ConstraintIndex{MOI.VectorOfVariables,MOI.Table{T}}(
        length(m.constraint_info) + 1,
    )
    expr = _build_constraint(m, f, s)
    _add_hexaly_constraint!(m, expr)
    m.constraint_info[index] = ConstraintInfo(index, expr, f, s)
    return index
end

function MOI.get(
    m::Optimizer,
    ::MOI.ConstraintFunction,
    c::MOI.ConstraintIndex{F,S},
) where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    return _info(m, c).f
end

function MOI.get(
    m::Optimizer,
    ::MOI.ConstraintSet,
    c::MOI.ConstraintIndex{F,S},
) where {F<:MOI.AbstractFunction,S<:MOI.AbstractSet}
    return _info(m, c).set
end

function MOI.supports(::Optimizer, ::MOI.ConstraintName, ::Type{<:MOI.ConstraintIndex})
    return true
end

function MOI.get(m::Optimizer, ::MOI.ConstraintName, c::MOI.ConstraintIndex)
    return _info(m, c).name
end

function MOI.set(
    m::Optimizer,
    ::MOI.ConstraintName,
    c::MOI.ConstraintIndex,
    name::String,
)
    _info(m, c).name = name
    return
end
