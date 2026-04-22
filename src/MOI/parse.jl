# Helpers to translate MOI functions and variable collections into Hexaly
# Python expressions.

function _parse_to_vars(model::Optimizer, f::MOI.VectorOfVariables)
    return Py[_info(model, v).variable for v in f.variables]
end

# Build a Hexaly expression representing the linear function
# `sum(c_i * x_i) + constant`.
function _build_linear_expression(
    model::Optimizer,
    f::MOI.ScalarAffineFunction{T},
) where {T <: Real}
    f = MOI.Utilities.canonical(f)
    m = model.model
    terms = f.terms
    # Build individual coefficient*variable terms.
    term_exprs = Py[]
    for t in terms
        v = _info(model, t.variable).variable
        c = t.coefficient
        if isone(c)
            push!(term_exprs, v)
        else
            push!(term_exprs, m.prod(_py_number(T, c), v))
        end
    end

    if isempty(term_exprs)
        return m.create_constant(_py_number(T, f.constant))
    end

    s = length(term_exprs) == 1 ? term_exprs[1] : m.sum(term_exprs...)
    if !iszero(f.constant)
        s = m.sum(s, m.create_constant(_py_number(T, f.constant)))
    end
    return s
end

# Convert a numeric scalar to the Python representation Hexaly expects.
# Integers are preserved to avoid unnecessary double-expressions.
_py_number(::Type{T}, x) where {T <: Integer} = Py(round(Int, x))
_py_number(::Type{T}, x) where {T} = Py(Float64(x))

_py_int(x::Real) = Py(round(Int, x))
_py_float(x::Real) = Py(Float64(x))

function _build_objective_expression(model::Optimizer)
    f = model.objective_function
    if f isa MOI.VariableIndex
        return _info(model, f).variable
    else
        return _build_linear_expression(model, f)
    end
end
