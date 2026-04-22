# CP constraints implemented as Hexaly expressions.

# AllDifferent — Hexaly's `distinct` on an array is an operator, not a
# boolean constraint, so we encode AllDifferent as a conjunction of pairwise
# `neq` expressions, which are boolean and can be constrained directly.

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorOfVariables},
    ::Type{MOI.AllDifferent},
)
    return true
end

function _build_constraint(
    model::Optimizer,
    f::MOI.VectorOfVariables,
    ::MOI.AllDifferent,
)
    vars = _parse_to_vars(model, f)
    m = model.model
    n = length(vars)
    if n <= 1
        return m.create_constant(Py(1))
    end
    pairs = Py[]
    for i in 1:n, j in (i + 1):n
        push!(pairs, m.neq(vars[i], vars[j]))
    end
    return length(pairs) == 1 ? pairs[1] : m.and_(pairs...)
end

# Circuit — Hexaly uses list decision variables for circuits, but we can
# express it on integer variables via: `distinct(x)` on 1..n together with
# a connectivity constraint. For simplicity we encode it as a conjunction:
# - all next[i] distinct
# - starting from node 1, following next exactly n steps returns to 1
# MOI's `Circuit` uses 1-based indices so x[i] ∈ {1..n}.
# We use an iterative reachability formulation:
#   visit[0] = 1, visit[k+1] = next[visit[k]], and visit[n] = 1.

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorOfVariables},
    ::Type{MOI.Circuit},
)
    return true
end

function _build_constraint(
    model::Optimizer,
    f::MOI.VectorOfVariables,
    s::MOI.Circuit,
)
    vars = _parse_to_vars(model, f)
    m = model.model
    n = length(vars)
    # MOI: x[i] ∈ 1..n denotes successor (1-based).
    # Hexaly at-indexing is 0-based, so we use `x[i] - 1`.
    shifted = Py[m.sub(v, Py(1)) for v in vars]
    pairs = Py[]
    # Domain: x[i] ∈ 1..n (implicitly required by MOI.Circuit)
    for v in vars
        push!(pairs, m.geq(v, Py(1)))
        push!(pairs, m.leq(v, Py(n)))
    end
    # All successors distinct (pairwise neq).
    for i in 1:n, j in (i + 1):n
        push!(pairs, m.neq(shifted[i], shifted[j]))
    end
    # Reachability: walk the successor array starting at node 0 and require
    # that after k < n steps the walk has not yet returned to 0, and after n
    # steps it has. Combined with distinctness this rules out sub-cycles and
    # forces a single Hamiltonian circuit.
    arr = m.array(pylist(shifted))
    cur = Py(0)
    for k in 1:n
        cur = m.at(arr, cur)
        if k < n
            push!(pairs, m.neq(cur, Py(0)))
        else
            push!(pairs, m.eq(cur, Py(0)))
        end
    end
    return length(pairs) == 1 ? pairs[1] : m.and_(pairs...)
end

# BinPacking — Hexaly models bin packing via load constraints.
# For each bin b, sum of weights of items assigned to b ≤ capacity.
# MOI bins are 1-indexed; Hexaly is 0-indexed when using `at`.

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{MOI.VectorOfVariables},
    ::Type{MOI.BinPacking{T}},
) where {T <: Real}
    return true
end

function _build_constraint(
    model::Optimizer,
    f::MOI.VectorOfVariables,
    s::MOI.BinPacking{T},
) where {T <: Real}
    vars = _parse_to_vars(model, f)
    m = model.model
    weights = s.weights
    capacity = s.capacity
    n_items = length(vars)
    # Determine number of bins from the item variables' upper bounds.
    max_bin = 0
    for vi in f.variables
        info = _info(model, vi)
        ub = info.ub
        if ub === nothing
            ub = n_items
        end
        max_bin = max(max_bin, round(Int, ub))
    end
    n_bins = max_bin
    # For each bin b (1..n_bins), sum_{i: x[i]==b} weights[i] ≤ capacity
    # Build using indicator: sum_i weights[i] * (x[i] == b) ≤ capacity
    and_terms = Py[]
    for b in 1:n_bins
        indicators = Py[]
        for i in 1:n_items
            ind = m.eq(vars[i], Py(b))
            push!(indicators, m.prod(Py(round(Int, weights[i])), ind))
        end
        load = m.sum(indicators...)
        push!(and_terms, m.leq(load, Py(round(Int, capacity))))
    end
    return length(and_terms) == 1 ? and_terms[1] : m.and_(and_terms...)
end
