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

# `Int` / `ZeroOne` annotations on existing variables are redundant — the
# variable was created with the right Hexaly domain (`int!`, `bool!`).
# Record the constraint for MOI bookkeeping but skip posting to Hexaly.
function MOI.add_constraint(
    m::Optimizer,
    f::MOI.VariableIndex,
    s::Union{MOI.Integer,MOI.ZeroOne},
)
    info = _info(m, f)
    if s isa MOI.ZeroOne
        info.is_binary = true
        info.lb = info.lb === nothing ? 0.0 : max(info.lb, 0.0)
        info.ub = info.ub === nothing ? 1.0 : min(info.ub, 1.0)
    end
    info.is_integer = true
    S = typeof(s)
    index = MOI.ConstraintIndex{MOI.VariableIndex,S}(f.value)
    m.constraint_info[index] = ConstraintInfo(index, nothing, f, s)
    return index
end

function MOI.add_constraint(
    m::Optimizer,
    f::MOI.VariableIndex,
    s::MOI.EqualTo{T},
) where {T<:Real}
    info = _info(m, f)
    value = Float64(s.value)
    (info.lb === nothing || info.lb <= value) &&
        (info.ub === nothing || value <= info.ub) || error(
            "Variable $f has incompatible equality and bound domains.",
        )
    info.lb = value
    info.ub = value
    rhs = T <: Integer ? Int(s.value) : Float64(s.value)
    expr = info.variable === nothing ? nothing : eq(m.model, info.variable, rhs)
    expr !== nothing && _add_hexaly_constraint!(m, expr)
    index = MOI.ConstraintIndex{MOI.VariableIndex,MOI.EqualTo{T}}(f.value)
    m.constraint_info[index] = ConstraintInfo(index, expr, f, s)
    return index
end

function MOI.add_constraint(
    m::Optimizer,
    f::MOI.VariableIndex,
    s::MOI.LessThan{T},
) where {T<:Real}
    info = _info(m, f)
    upper = Float64(s.upper)
    info.ub = info.ub === nothing ? upper : min(info.ub, upper)
    rhs = T <: Integer ? Int(s.upper) : Float64(s.upper)
    expr = info.variable === nothing ? nothing : leq(m.model, info.variable, rhs)
    expr !== nothing && _add_hexaly_constraint!(m, expr)
    index = MOI.ConstraintIndex{MOI.VariableIndex,MOI.LessThan{T}}(f.value)
    m.constraint_info[index] = ConstraintInfo(index, expr, f, s)
    return index
end

function MOI.add_constraint(
    m::Optimizer,
    f::MOI.VariableIndex,
    s::MOI.GreaterThan{T},
) where {T<:Real}
    info = _info(m, f)
    lower = Float64(s.lower)
    info.lb = info.lb === nothing ? lower : max(info.lb, lower)
    rhs = T <: Integer ? Int(s.lower) : Float64(s.lower)
    expr = info.variable === nothing ? nothing : geq(m.model, info.variable, rhs)
    expr !== nothing && _add_hexaly_constraint!(m, expr)
    index = MOI.ConstraintIndex{MOI.VariableIndex,MOI.GreaterThan{T}}(f.value)
    m.constraint_info[index] = ConstraintInfo(index, expr, f, s)
    return index
end

function MOI.add_constraint(
    m::Optimizer,
    f::MOI.VariableIndex,
    s::MOI.Interval{T},
) where {T<:Real}
    info = _info(m, f)
    lower, upper = Float64(s.lower), Float64(s.upper)
    info.lb = info.lb === nothing ? lower : max(info.lb, lower)
    info.ub = info.ub === nothing ? upper : min(info.ub, upper)
    lb = T <: Integer ? Int(s.lower) : Float64(s.lower)
    ub = T <: Integer ? Int(s.upper) : Float64(s.upper)
    if info.variable !== nothing
        _add_hexaly_constraint!(m, geq(m.model, info.variable, lb))
        _add_hexaly_constraint!(m, leq(m.model, info.variable, ub))
    end
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
