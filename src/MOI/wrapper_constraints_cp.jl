# CP constraints implemented as Hexaly expressions.

# Indicator constraints. The activation variable may be a defined expression
# such as MathOptVRP.IsEmpty instead of a native Hexaly decision.

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{<:Union{MOI.VectorOfVariables,MOI.VectorAffineFunction}},
    ::Type{<:MOI.Indicator{A,S}},
) where {
    A,
    T<:Real,
    S<:Union{MOI.EqualTo{T},MOI.LessThan{T},MOI.GreaterThan{T}},
}
    return true
end

_indicator_on_one(::MOI.Indicator{MOI.ACTIVATE_ON_ONE}) = true
_indicator_on_one(::MOI.Indicator{MOI.ACTIVATE_ON_ZERO}) = false

function _indicator_item_expression(m::Optimizer, item)
    if item isa MOI.VariableIndex
        return _expression!(m, item)
    elseif item isa MOI.ScalarAffineFunction
        return _build_linear_expression(m, item)
    elseif item isa Real
        return create_constant(m.model, item)
    end
    error("Unsupported indicator item $(typeof(item)).")
end

function MOI.add_constraint(
    m::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::MOI.Indicator{A,S},
) where {
    A,
    T<:Real,
    S<:Union{MOI.EqualTo{T},MOI.LessThan{T},MOI.GreaterThan{T}},
}
    items = _normalize_sum_distances_items(f)
    length(items) == 2 || error("Hexaly indicator constraints need two rows.")
    activation = _indicator_item_expression(m, items[1])
    body = _indicator_item_expression(m, items[2])
    inner = s.set
    condition = if inner isa MOI.EqualTo
        eq(m.model, body, inner.value)
    elseif inner isa MOI.LessThan
        leq(m.model, body, inner.upper)
    else
        geq(m.model, body, inner.lower)
    end
    implication = _indicator_on_one(s) ?
        or_(m.model, not_(m.model, activation), condition) :
        or_(m.model, activation, condition)
    _add_hexaly_constraint!(m, implication)
    cindex = MOI.ConstraintIndex{typeof(f),typeof(s)}(
        length(m.constraint_info) + 1,
    )
    m.constraint_info[cindex] = ConstraintInfo(cindex, implication, f, s)
    return cindex
end

# AllDifferent — Hexaly 15's `distinct(array)` returns a set, not a Boolean
# all-different predicate. Build the Boolean predicate from pairwise `neq`
# expressions so it can also be reified directly.

# These sets constrain existing scalar variables; they are not variable
# constructors. In particular, letting MOI choose `AllDifferent` as a variable
# cone would materialize variables before their Integer/ZeroOne domains arrive.
for SetType in (MOI.AllDifferent, MOI.Circuit, MOI.BinPacking, MOI.Table)
    @eval function MOI.supports_add_constrained_variables(
        ::Optimizer,
        ::Type{<:$SetType},
    )
        return false
    end
end

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorOfVariables},
    ::Type{MOI.AllDifferent},
)
    return true
end

function _build_constraint(m::Optimizer, f::MOI.VectorOfVariables, ::MOI.AllDifferent)
    vars = _parse_to_vars(m, f)
    md = m.model
    n = length(vars)
    if n <= 1
        return create_constant(md, 1)
    end
    pairs = HxExpression[]
    for i = 1:n, j = (i+1):n
        push!(pairs, neq(md, vars[i], vars[j]))
    end
    return length(pairs) == 1 ? pairs[1] : and_(md, pairs...)
end

# Reified(AllDifferent): the first row is the Boolean truth value and the
# remaining rows are the values whose pairwise distinctness it represents.
# Implement the equivalence natively instead of using MOI's
# AllDifferent -> CountDistinct -> MILP bridge chain.
function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorOfVariables},
    ::Type{MOI.Reified{MOI.AllDifferent}},
)
    return true
end

function MOI.supports_add_constrained_variables(
    ::Optimizer,
    ::Type{MOI.Reified{MOI.AllDifferent}},
)
    return false
end

function MOI.add_constraint(
    m::Optimizer,
    f::MOI.VectorOfVariables,
    s::MOI.Reified{MOI.AllDifferent},
)
    length(f.variables) == MOI.dimension(s) || error(
        "Hexaly Reified(AllDifferent) expected $(MOI.dimension(s)) variables; " *
        "got $(length(f.variables)).",
    )
    truth = _expression!(m, first(f.variables))
    values = MOI.VectorOfVariables(f.variables[2:end])
    all_different = _build_constraint(m, values, s.set)
    expr = eq(m.model, truth, all_different)
    _add_hexaly_constraint!(m, expr)
    index = MOI.ConstraintIndex{typeof(f),typeof(s)}(
        length(m.constraint_info) + 1,
    )
    m.constraint_info[index] = ConstraintInfo(index, expr, f, s)
    return index
end

# Circuit — encoded via a reachability formulation. See the original Python
# version for the exact construction.

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorOfVariables},
    ::Type{MOI.Circuit},
)
    return true
end

function _build_constraint(m::Optimizer, f::MOI.VectorOfVariables, s::MOI.Circuit)
    vars = _parse_to_vars(m, f)
    md = m.model
    n = length(vars)
    shifted = HxExpression[sub(md, v, 1) for v in vars]
    pairs = HxExpression[]
    for v in vars
        push!(pairs, geq(md, v, 1))
        push!(pairs, leq(md, v, n))
    end
    for i = 1:n, j = (i+1):n
        push!(pairs, neq(md, shifted[i], shifted[j]))
    end
    arr = array(md, shifted)
    cur::Union{Int,HxExpression} = 0
    for k = 1:n
        cur = at(md, arr, cur)
        if k < n
            push!(pairs, neq(md, cur, 0))
        else
            push!(pairs, eq(md, cur, 0))
        end
    end
    return length(pairs) == 1 ? pairs[1] : and_(md, pairs...)
end

# BinPacking — sum of weights of items assigned to bin b ≤ capacity, for
# every bin.

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorOfVariables},
    ::Type{MOI.BinPacking{T}},
) where {T<:Real}
    return true
end

function _build_constraint(
    m::Optimizer,
    f::MOI.VectorOfVariables,
    s::MOI.BinPacking{T},
) where {T<:Real}
    vars = _parse_to_vars(m, f)
    md = m.model
    weights = s.weights
    capacity = s.capacity
    n_items = length(vars)
    max_bin = 0
    for vi in f.variables
        info = _info(m, vi)
        ub = info.ub
        if ub === nothing
            ub = n_items
        end
        max_bin = max(max_bin, round(Int, ub))
    end
    n_bins = max_bin
    and_terms = HxExpression[]
    for b = 1:n_bins
        indicators = HxExpression[]
        for i = 1:n_items
            ind = eq(md, vars[i], b)
            push!(indicators, prod(md, round(Int, weights[i]), ind))
        end
        load = sum(md, indicators...)
        push!(and_terms, leq(md, load, round(Int, capacity)))
    end
    return length(and_terms) == 1 ? and_terms[1] : and_(md, and_terms...)
end

# Table — `x ∈ Table(tbl)` iff there exists a row r such that x[c] == tbl[r,c]
# for all c.

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorOfVariables},
    ::Type{MOI.Table{T}},
) where {T<:Real}
    return true
end

function _build_constraint(
    m::Optimizer,
    f::MOI.VectorOfVariables,
    s::MOI.Table{T},
) where {T<:Real}
    vars = _parse_to_vars(m, f)
    md = m.model
    tbl = s.table
    nrows, ncols = size(tbl)
    @assert ncols == length(vars)
    if nrows == 0
        return create_constant(md, 0)
    end
    row_exprs = HxExpression[]
    for r = 1:nrows
        eqs = HxExpression[eq(md, vars[c], round(Int, tbl[r, c])) for c = 1:ncols]
        push!(row_exprs, length(eqs) == 1 ? eqs[1] : and_(md, eqs...))
    end
    return length(row_exprs) == 1 ? row_exprs[1] : or_(md, row_exprs...)
end
