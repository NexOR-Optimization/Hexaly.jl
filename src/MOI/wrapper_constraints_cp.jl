# CP constraints implemented as Hexaly expressions.

# AllDifferent — `model.distinct(array)` returns a boolean expression that
# holds iff all elements of the array are pairwise distinct.

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
    arr = model.model.array(pylist(vars))
    return model.model.distinct(arr)
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
    # next_arr[i] = x[i] (we build an array indexed 0..n-1, shifted by -1)
    # MOI: x[i] ∈ 1..n denotes successor (1-based).
    # Hexaly: build `next0[i] = x[i] - 1` so next0[i] ∈ 0..n-1.
    shifted = Py[m.sub(v, Py(1)) for v in vars]
    # All successors distinct
    distinct_expr = m.distinct(m.array(pylist(shifted)))
    # Reachability: starting at 0, applying `next` n times yields 0 and all
    # intermediate nodes are distinct (guaranteed by distinct).
    arr = m.array(pylist(shifted))
    cur = Py(0)
    for _ in 1:n
        cur = m.at(arr, cur)
    end
    return_to_start = m.eq(cur, Py(0))
    return m.and_(distinct_expr, return_to_start)
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
