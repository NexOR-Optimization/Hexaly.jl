# Build Hexaly expressions for ScalarAffineFunction-in-Set constraints.
# The LHS is built via `_build_linear_expression`, and the comparison is
# expressed through `model.eq` / `model.leq` / `model.geq`.

function _build_constraint(
    model::Optimizer,
    f::MOI.ScalarAffineFunction{T},
    s::MOI.EqualTo{T},
) where {T <: Real}
    lhs = _build_linear_expression(model, f)
    rhs = T <: Integer ? _py_int(s.value) : _py_float(s.value)
    return model.model.eq(lhs, rhs)
end

function _build_constraint(
    model::Optimizer,
    f::MOI.ScalarAffineFunction{T},
    s::MOI.LessThan{T},
) where {T <: Real}
    lhs = _build_linear_expression(model, f)
    rhs = T <: Integer ? _py_int(s.upper) : _py_float(s.upper)
    return model.model.leq(lhs, rhs)
end

function _build_constraint(
    model::Optimizer,
    f::MOI.ScalarAffineFunction{T},
    s::MOI.GreaterThan{T},
) where {T <: Real}
    lhs = _build_linear_expression(model, f)
    rhs = T <: Integer ? _py_int(s.lower) : _py_float(s.lower)
    return model.model.geq(lhs, rhs)
end
