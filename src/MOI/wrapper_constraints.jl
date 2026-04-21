function _info(model::Optimizer, key::MOI.ConstraintIndex)
    if haskey(model.constraint_info, key)
        return model.constraint_info[key]
    end
    throw(MOI.InvalidIndex(key))
end

function MOI.is_valid(
    model::Optimizer,
    c::MOI.ConstraintIndex{F, S},
) where {F <: MOI.AbstractFunction, S <: MOI.AbstractSet}
    info = get(model.constraint_info, c, nothing)
    return info !== nothing && typeof(info.set) == S && typeof(info.f) == F
end

function _add_hexaly_constraint!(model::Optimizer, expr::Py)
    model.model.constraint(expr)
    return
end

# ScalarAffineFunction-in-Set

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.ScalarAffineFunction{T}},
    ::Type{S},
) where {T <: Real, S <: Union{MOI.EqualTo{T}, MOI.LessThan{T}, MOI.GreaterThan{T}}}
    return true
end

function MOI.add_constraint(
    model::Optimizer,
    f::MOI.ScalarAffineFunction{T},
    s::S,
) where {T <: Real, S <: Union{MOI.EqualTo{T}, MOI.LessThan{T}, MOI.GreaterThan{T}}}
    index = MOI.ConstraintIndex{MOI.ScalarAffineFunction{T}, S}(
        length(model.constraint_info) + 1,
    )
    expr = _build_constraint(model, f, s)
    _add_hexaly_constraint!(model, expr)
    model.constraint_info[index] = ConstraintInfo(index, expr, f, s)
    return index
end

# VectorOfVariables CP constraints

function MOI.add_constraint(
    model::Optimizer,
    f::MOI.VectorOfVariables,
    s::S,
) where {S <: Union{MOI.AllDifferent, MOI.Circuit}}
    index = MOI.ConstraintIndex{MOI.VectorOfVariables, S}(
        length(model.constraint_info) + 1,
    )
    expr = _build_constraint(model, f, s)
    _add_hexaly_constraint!(model, expr)
    model.constraint_info[index] = ConstraintInfo(index, expr, f, s)
    return index
end

function MOI.add_constraint(
    model::Optimizer,
    f::MOI.VectorOfVariables,
    s::MOI.BinPacking{T},
) where {T <: Real}
    index = MOI.ConstraintIndex{MOI.VectorOfVariables, MOI.BinPacking{T}}(
        length(model.constraint_info) + 1,
    )
    expr = _build_constraint(model, f, s)
    _add_hexaly_constraint!(model, expr)
    model.constraint_info[index] = ConstraintInfo(index, expr, f, s)
    return index
end

function MOI.get(
    model::Optimizer,
    ::MOI.ConstraintFunction,
    c::MOI.ConstraintIndex{F, S},
) where {F <: MOI.AbstractFunction, S <: MOI.AbstractSet}
    return _info(model, c).f
end

function MOI.get(
    model::Optimizer,
    ::MOI.ConstraintSet,
    c::MOI.ConstraintIndex{F, S},
) where {F <: MOI.AbstractFunction, S <: MOI.AbstractSet}
    return _info(model, c).set
end

function MOI.supports(
    ::Optimizer,
    ::MOI.ConstraintName,
    ::Type{<:MOI.ConstraintIndex},
)
    return true
end

function MOI.get(model::Optimizer, ::MOI.ConstraintName, c::MOI.ConstraintIndex)
    return _info(model, c).name
end

function MOI.set(
    model::Optimizer,
    ::MOI.ConstraintName,
    c::MOI.ConstraintIndex,
    name::String,
)
    _info(model, c).name = name
    return
end
