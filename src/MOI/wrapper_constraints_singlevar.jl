function _has_lb(model::Optimizer, index::MOI.VariableIndex)
    return _info(model, index).lb !== nothing
end

function _has_ub(model::Optimizer, index::MOI.VariableIndex)
    return _info(model, index).ub !== nothing
end

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VariableIndex},
    ::Type{S},
) where {T <: Union{Int, Float64}, S <: Union{
    MOI.EqualTo{T},
    MOI.LessThan{T},
    MOI.GreaterThan{T},
    MOI.Interval{T},
}}
    return true
end

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VariableIndex},
    ::Type{<:Union{MOI.ZeroOne, MOI.Integer}},
)
    return true
end

function MOI.is_valid(
    model::Optimizer,
    c::MOI.ConstraintIndex{MOI.VariableIndex, MOI.LessThan{T}},
) where {T <: Real}
    index = MOI.VariableIndex(c.value)
    return MOI.is_valid(model, index) && _has_ub(model, index)
end

function MOI.is_valid(
    model::Optimizer,
    c::MOI.ConstraintIndex{MOI.VariableIndex, MOI.GreaterThan{T}},
) where {T <: Real}
    index = MOI.VariableIndex(c.value)
    return MOI.is_valid(model, index) && _has_lb(model, index)
end

function MOI.is_valid(
    model::Optimizer,
    c::MOI.ConstraintIndex{MOI.VariableIndex, MOI.Interval{T}},
) where {T <: Real}
    index = MOI.VariableIndex(c.value)
    return MOI.is_valid(model, index) && _has_lb(model, index) && _has_ub(model, index)
end

function MOI.is_valid(
    model::Optimizer,
    c::MOI.ConstraintIndex{MOI.VariableIndex, MOI.EqualTo{T}},
) where {T <: Real}
    index = MOI.VariableIndex(c.value)
    return MOI.is_valid(model, index) &&
           _info(model, index).lb !== nothing &&
           _info(model, index).ub !== nothing &&
           _info(model, index).lb == _info(model, index).ub
end

function MOI.is_valid(
    model::Optimizer,
    c::MOI.ConstraintIndex{MOI.VariableIndex, MOI.ZeroOne},
)
    index = MOI.VariableIndex(c.value)
    return MOI.is_valid(model, index) && _info(model, index).is_binary
end

function MOI.is_valid(
    model::Optimizer,
    c::MOI.ConstraintIndex{MOI.VariableIndex, MOI.Integer},
)
    index = MOI.VariableIndex(c.value)
    return MOI.is_valid(model, index) && _info(model, index).is_integer
end

function MOI.add_constraint(
    model::Optimizer,
    f::MOI.VariableIndex,
    s::MOI.EqualTo{T},
) where {T <: Real}
    v = _info(model, f).variable
    val = T <: Integer ? _py_int(s.value) : _py_float(s.value)
    expr = model.model.eq(v, val)
    _add_hexaly_constraint!(model, expr)
    info = _info(model, f)
    info.lb = Float64(s.value)
    info.ub = Float64(s.value)
    index = MOI.ConstraintIndex{MOI.VariableIndex, MOI.EqualTo{T}}(f.value)
    model.constraint_info[index] = ConstraintInfo(index, expr, f, s)
    return index
end

function MOI.add_constraint(
    model::Optimizer,
    f::MOI.VariableIndex,
    s::MOI.LessThan{T},
) where {T <: Real}
    v = _info(model, f).variable
    val = T <: Integer ? _py_int(s.upper) : _py_float(s.upper)
    expr = model.model.leq(v, val)
    _add_hexaly_constraint!(model, expr)
    _info(model, f).ub = Float64(s.upper)
    index = MOI.ConstraintIndex{MOI.VariableIndex, MOI.LessThan{T}}(f.value)
    model.constraint_info[index] = ConstraintInfo(index, expr, f, s)
    return index
end

function MOI.add_constraint(
    model::Optimizer,
    f::MOI.VariableIndex,
    s::MOI.GreaterThan{T},
) where {T <: Real}
    v = _info(model, f).variable
    val = T <: Integer ? _py_int(s.lower) : _py_float(s.lower)
    expr = model.model.geq(v, val)
    _add_hexaly_constraint!(model, expr)
    _info(model, f).lb = Float64(s.lower)
    index = MOI.ConstraintIndex{MOI.VariableIndex, MOI.GreaterThan{T}}(f.value)
    model.constraint_info[index] = ConstraintInfo(index, expr, f, s)
    return index
end

function MOI.add_constraint(
    model::Optimizer,
    f::MOI.VariableIndex,
    s::MOI.Interval{T},
) where {T <: Real}
    v = _info(model, f).variable
    lb = T <: Integer ? _py_int(s.lower) : _py_float(s.lower)
    ub = T <: Integer ? _py_int(s.upper) : _py_float(s.upper)
    lb_expr = model.model.geq(v, lb)
    ub_expr = model.model.leq(v, ub)
    _add_hexaly_constraint!(model, lb_expr)
    _add_hexaly_constraint!(model, ub_expr)
    info = _info(model, f)
    info.lb = Float64(s.lower)
    info.ub = Float64(s.upper)
    index = MOI.ConstraintIndex{MOI.VariableIndex, MOI.Interval{T}}(f.value)
    model.constraint_info[index] = ConstraintInfo(index, nothing, f, s)
    return index
end

function MOI.get(
    model::Optimizer,
    ::MOI.ConstraintFunction,
    c::MOI.ConstraintIndex{MOI.VariableIndex, <:Any},
)
    MOI.throw_if_not_valid(model, c)
    return MOI.VariableIndex(c.value)
end

function MOI.set(
    ::Optimizer,
    ::MOI.ConstraintFunction,
    ::MOI.ConstraintIndex{MOI.VariableIndex, S},
    ::MOI.VariableIndex,
) where {S}
    throw(MOI.SettingVariableIndexFunctionNotAllowed())
end
