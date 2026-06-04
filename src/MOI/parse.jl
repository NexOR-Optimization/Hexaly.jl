# Helpers to translate MOI functions and variable collections into Hexaly
# C-API expressions.

function _parse_to_vars(m::Optimizer, f::MOI.VectorOfVariables)
    return HxExpression[_info(m, v).variable for v in f.variables]
end

# Build a Hexaly expression representing the linear function
# `sum(c_i * x_i) + constant`.
function _build_linear_expression(
    m::Optimizer,
    f::MOI.ScalarAffineFunction{T},
) where {T<:Real}
    f = MOI.Utilities.canonical(f)
    md = m.model
    term_exprs = HxExpression[]
    for t in f.terms
        v = _info(m, t.variable).variable
        c = t.coefficient
        if isone(c)
            push!(term_exprs, v)
        else
            push!(term_exprs, prod(md, _num(T, c), v))
        end
    end

    if isempty(term_exprs)
        return create_constant(md, _num(T, f.constant))
    end

    s = length(term_exprs) == 1 ? term_exprs[1] : sum(md, term_exprs...)
    if !iszero(f.constant)
        s = sum(md, s, create_constant(md, _num(T, f.constant)))
    end
    return s
end

# Numeric scalar coercion. Integer coefficients stay integer so Hexaly can
# keep an integer-domain objective when possible.
_num(::Type{T}, x) where {T<:Integer} = round(Int, x)
_num(::Type{T}, x) where {T} = Float64(x)

function _build_objective_expression(m::Optimizer)
    f = m.objective_function
    if f isa MOI.VariableIndex
        return _info(m, f).variable
    elseif f isa MOI.ScalarNonlinearFunction
        return _build_sum_distances_expression(m, f)
    else
        return _build_linear_expression(m, f)
    end
end
