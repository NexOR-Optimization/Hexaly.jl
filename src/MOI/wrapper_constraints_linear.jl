# Build Hexaly expressions for ScalarAffineFunction-in-Set constraints.
# The LHS is built via `_build_linear_expression`, and the comparison is
# expressed through `eq` / `leq` / `geq` from the C wrapper.

function _build_constraint(
    m::Optimizer,
    f::MOI.ScalarAffineFunction{T},
    s::MOI.EqualTo{T},
) where {T<:Real}
    lhs = _build_linear_expression(m, f)
    rhs = T <: Integer ? Int(s.value) : Float64(s.value)
    return eq(m.model, lhs, rhs)
end

function _build_constraint(
    m::Optimizer,
    f::MOI.ScalarAffineFunction{T},
    s::MOI.LessThan{T},
) where {T<:Real}
    lhs = _build_linear_expression(m, f)
    rhs = T <: Integer ? Int(s.upper) : Float64(s.upper)
    return leq(m.model, lhs, rhs)
end

function _build_constraint(
    m::Optimizer,
    f::MOI.ScalarAffineFunction{T},
    s::MOI.GreaterThan{T},
) where {T<:Real}
    lhs = _build_linear_expression(m, f)
    rhs = T <: Integer ? Int(s.lower) : Float64(s.lower)
    return geq(m.model, lhs, rhs)
end
