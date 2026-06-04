# CP constraints implemented as Hexaly expressions.

# AllDifferent — Hexaly's `distinct` is an operator over a *list* decision
# variable, not a boolean constraint on individual variables. We encode
# AllDifferent as a conjunction of pairwise `neq` expressions, which are
# boolean and can be constrained directly.

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
