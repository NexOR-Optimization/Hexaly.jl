function _has_lb(m::Optimizer, index::MOI.VariableIndex)
    return _info(m, index).lb !== nothing
end

function _has_ub(m::Optimizer, index::MOI.VariableIndex)
    return _info(m, index).ub !== nothing
end

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VariableIndex},
    ::Type{S},
) where {
    T<:Union{Int,Float64},
    S<:Union{MOI.EqualTo{T},MOI.LessThan{T},MOI.GreaterThan{T},MOI.Interval{T}},
}
    return true
end

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VariableIndex},
    ::Type{<:Union{MOI.ZeroOne,MOI.Integer}},
)
    return true
end

function MOI.is_valid(
    m::Optimizer,
    c::MOI.ConstraintIndex{MOI.VariableIndex,MOI.LessThan{T}},
) where {T<:Real}
    index = MOI.VariableIndex(c.value)
    return MOI.is_valid(m, index) && _has_ub(m, index)
end

function MOI.is_valid(
    m::Optimizer,
    c::MOI.ConstraintIndex{MOI.VariableIndex,MOI.GreaterThan{T}},
) where {T<:Real}
    index = MOI.VariableIndex(c.value)
    return MOI.is_valid(m, index) && _has_lb(m, index)
end

function MOI.is_valid(
    m::Optimizer,
    c::MOI.ConstraintIndex{MOI.VariableIndex,MOI.Interval{T}},
) where {T<:Real}
    index = MOI.VariableIndex(c.value)
    return MOI.is_valid(m, index) && _has_lb(m, index) && _has_ub(m, index)
end

function MOI.is_valid(
    m::Optimizer,
    c::MOI.ConstraintIndex{MOI.VariableIndex,MOI.EqualTo{T}},
) where {T<:Real}
    index = MOI.VariableIndex(c.value)
    return MOI.is_valid(m, index) &&
           _info(m, index).lb !== nothing &&
           _info(m, index).ub !== nothing &&
           _info(m, index).lb == _info(m, index).ub
end

function MOI.is_valid(
    m::Optimizer,
    c::MOI.ConstraintIndex{MOI.VariableIndex,MOI.ZeroOne},
)
    index = MOI.VariableIndex(c.value)
    return MOI.is_valid(m, index) && _info(m, index).is_binary
end

function MOI.is_valid(
    m::Optimizer,
    c::MOI.ConstraintIndex{MOI.VariableIndex,MOI.Integer},
)
    index = MOI.VariableIndex(c.value)
    return MOI.is_valid(m, index) && _info(m, index).is_integer
end

function MOI.add_constraint(
    m::Optimizer,
    f::MOI.VariableIndex,
    s::MOI.EqualTo{T},
) where {T<:Real}
    v = _info(m, f).variable
    rhs = T <: Integer ? Int(s.value) : Float64(s.value)
    expr = eq(m.model, v, rhs)
    _add_hexaly_constraint!(m, expr)
    info = _info(m, f)
    info.lb = Float64(s.value)
    info.ub = Float64(s.value)
    index = MOI.ConstraintIndex{MOI.VariableIndex,MOI.EqualTo{T}}(f.value)
    m.constraint_info[index] = ConstraintInfo(index, expr, f, s)
    return index
end

function MOI.add_constraint(
    m::Optimizer,
    f::MOI.VariableIndex,
    s::MOI.LessThan{T},
) where {T<:Real}
    v = _info(m, f).variable
    rhs = T <: Integer ? Int(s.upper) : Float64(s.upper)
    expr = leq(m.model, v, rhs)
    _add_hexaly_constraint!(m, expr)
    _info(m, f).ub = Float64(s.upper)
    index = MOI.ConstraintIndex{MOI.VariableIndex,MOI.LessThan{T}}(f.value)
    m.constraint_info[index] = ConstraintInfo(index, expr, f, s)
    return index
end

function MOI.add_constraint(
    m::Optimizer,
    f::MOI.VariableIndex,
    s::MOI.GreaterThan{T},
) where {T<:Real}
    v = _info(m, f).variable
    rhs = T <: Integer ? Int(s.lower) : Float64(s.lower)
    expr = geq(m.model, v, rhs)
    _add_hexaly_constraint!(m, expr)
    _info(m, f).lb = Float64(s.lower)
    index = MOI.ConstraintIndex{MOI.VariableIndex,MOI.GreaterThan{T}}(f.value)
    m.constraint_info[index] = ConstraintInfo(index, expr, f, s)
    return index
end

function MOI.add_constraint(
    m::Optimizer,
    f::MOI.VariableIndex,
    s::MOI.Interval{T},
) where {T<:Real}
    v = _info(m, f).variable
    lb = T <: Integer ? Int(s.lower) : Float64(s.lower)
    ub = T <: Integer ? Int(s.upper) : Float64(s.upper)
    lb_expr = geq(m.model, v, lb)
    ub_expr = leq(m.model, v, ub)
    _add_hexaly_constraint!(m, lb_expr)
    _add_hexaly_constraint!(m, ub_expr)
    info = _info(m, f)
    info.lb = Float64(s.lower)
    info.ub = Float64(s.upper)
    index = MOI.ConstraintIndex{MOI.VariableIndex,MOI.Interval{T}}(f.value)
    m.constraint_info[index] = ConstraintInfo(index, nothing, f, s)
    return index
end

function MOI.get(
    m::Optimizer,
    ::MOI.ConstraintFunction,
    c::MOI.ConstraintIndex{MOI.VariableIndex,<:Any},
)
    MOI.throw_if_not_valid(m, c)
    return MOI.VariableIndex(c.value)
end

function MOI.set(
    ::Optimizer,
    ::MOI.ConstraintFunction,
    ::MOI.ConstraintIndex{MOI.VariableIndex,S},
    ::MOI.VariableIndex,
) where {S}
    throw(MOI.SettingVariableIndexFunctionNotAllowed())
end
