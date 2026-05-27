# Hexaly recognises `MOI.ScalarNonlinearFunction` with head `:sum_distances`
# as the closed-tour cost objective. Args: `[dist_matrix, nodes]` where
# `dist_matrix isa AbstractMatrix{<:Real}` and `nodes isa Vector{MOI.VariableIndex}`.
# Lowered to a Hexaly `model.sum(range, lambda)` expression that visits the
# list cyclically.

function MOI.supports(::Optimizer, ::MOI.ObjectiveFunction{MOI.ScalarNonlinearFunction})
    return true
end

function MOI.set(
    model::Optimizer,
    ::MOI.ObjectiveFunction{MOI.ScalarNonlinearFunction},
    f::MOI.ScalarNonlinearFunction,
)
    model.objective_function_type = MOI.ScalarNonlinearFunction
    model.objective_function = f
    return
end

# Lower a `ScalarNonlinearFunction` whose root head is `:sum_distances`, or a
# `:+` tree (sum of subexpressions) whose leaves are `:sum_distances` — the
# shape JuMP produces when the user writes
# `sum(Hexaly.op_sum_distances(...) for i in 1:n_trucks)`.
function _build_sum_distances_expression(model::Optimizer, f::MOI.ScalarNonlinearFunction)
    if f.head == :+
        terms = [_build_sum_distances_expression(model, arg) for arg in f.args]
        return reduce((a, b) -> a + b, terms)
    end
    f.head == :sum_distances || error(
        "Hexaly: unsupported ScalarNonlinearFunction head `$(f.head)`. ",
        "Only `:sum_distances` (optionally wrapped in `:+`) is currently lowered.",
    )
    length(f.args) == 2 || error(
        "Hexaly: `:sum_distances` expects 2 args (dist_matrix, nodes); got $(length(f.args)).",
    )
    dist_matrix = f.args[1]::AbstractMatrix{<:Real}
    nodes_raw = f.args[2]
    items = _normalize_sum_distances_items(nodes_raw)

    m = model.model
    n_rows = size(dist_matrix, 1)
    n_rows == size(dist_matrix, 2) || error(
        "Hexaly: `:sum_distances` expects a square dist_matrix; got $(size(dist_matrix)).",
    )
    dist_rows = Py[pylist(round.(Int, dist_matrix[i, :])) for i = 1:n_rows]
    dist_arr = m.array(pylist(dist_rows))

    # Pattern A: every item is a list-element variable, and they all share
    # the same `parent_list`. Lower as a closed tour over that list (variable
    # count). Used by the TSP form `op_sum_distances(M, list_column)`.
    if all(it -> it isa MOI.VariableIndex, items)
        first_pl = _info(model, items[1]).parent_list
        if first_pl !== nothing &&
           all(_info(model, vi).parent_list === first_pl for vi in items)
            return _closed_tour_over_list(m, dist_arr, first_pl)
        end
    end

    # Pattern B: `[const c0, list_vars..., const c1]` with all list_vars
    # sharing the same parent_list. Used by the VRP form
    # `op_sum_distances(M, vcat(depot, nodes[:, i], depot))`.
    if length(items) >= 3 &&
       items[1] isa Real &&
       items[end] isa Real &&
       all(items[i] isa MOI.VariableIndex for i = 2:(length(items)-1))
        first_pl = _info(model, items[2]).parent_list
        if first_pl !== nothing &&
           all(_info(model, items[i]).parent_list === first_pl for i = 2:(length(items)-1))
            return _closed_tour_with_depots(
                m,
                dist_arr,
                first_pl,
                round(Int, items[1]),
                round(Int, items[end]),
            )
        end
    end

    # Fallback: fixed-length closed tour over a static array of mixed
    # constants and variables.
    elements = Py[_item_to_py(model, it) for it in items]
    seq = m.array(pylist(elements))
    c = m.count(seq)
    inner = m.lambda_function(
        pyfunc(i -> m.at(dist_arr, seq[i-1], seq[i]); wrap = "lambda f: lambda i: f(i)"),
    )
    closing = m.iif(c > 0, m.at(dist_arr, seq[c-1], seq[0]), Py(0))
    return m.sum(m.range(1, c), inner) + closing
end

function _normalize_sum_distances_items(nodes_raw)
    if nodes_raw isa MOI.VectorOfVariables
        return Any[vi for vi in nodes_raw.variables]
    elseif nodes_raw isa MOI.VectorAffineFunction
        return _vector_affine_to_items(nodes_raw)
    elseif nodes_raw isa AbstractVector
        return Any[_simplify_item(el) for el in nodes_raw]
    end
    return error(
        "Hexaly: `:sum_distances` second arg has unexpected type $(typeof(nodes_raw))",
    )
end

# `Vector{AffExpr}` is converted by JuMP to a single `VectorAffineFunction`
# at the MOI level. Decompose it back into per-row scalar items so the
# pattern-detection logic in `_build_sum_distances_expression` can see each
# entry individually.
function _vector_affine_to_items(f::MOI.VectorAffineFunction)
    n = length(f.constants)
    per_row = [MOI.ScalarAffineTerm{eltype(f.constants)}[] for _ = 1:n]
    for vt in f.terms
        push!(per_row[vt.output_index], vt.scalar_term)
    end
    items = Vector{Any}(undef, n)
    for i = 1:n
        items[i] = _simplify_item(MOI.ScalarAffineFunction(per_row[i], f.constants[i]))
    end
    return items
end

# JuMP often produces a `Vector{AffExpr}` for `vcat(::Int, vars, ::Int)` and
# converts each entry to `MOI.ScalarAffineFunction`. Reduce trivial affine
# functions (pure constants, single-variable identity terms) back to a plain
# constant or `MOI.VariableIndex` so the lowering can treat them uniformly.
_simplify_item(x) = x
function _simplify_item(f::MOI.ScalarAffineFunction)
    if isempty(f.terms)
        return f.constant
    end
    if length(f.terms) == 1 && iszero(f.constant) && isone(f.terms[1].coefficient)
        return f.terms[1].variable
    end
    return f
end

function _item_to_py(model::Optimizer, it)
    if it isa MOI.VariableIndex
        return _info(model, it).variable
    elseif it isa Real
        return Py(round(Int, it))
    end
    return error("Hexaly: `:sum_distances` cannot lower item of type $(typeof(it))")
end

# Closed tour over a Hexaly list with *variable* count.
function _closed_tour_over_list(m::Py, dist_arr::Py, seq::Py)
    c = m.count(seq)
    inner = m.lambda_function(
        pyfunc(i -> m.at(dist_arr, seq[i-1], seq[i]); wrap = "lambda f: lambda i: f(i)"),
    )
    closing = m.iif(c > 0, m.at(dist_arr, seq[c-1], seq[0]), Py(0))
    return m.sum(m.range(1, c), inner) + closing
end

# Closed tour over `[c0, seq[0], seq[1], ..., seq[count-1], c1]`.
# - count == 0 → degenerate cycle [c0, c1]: dist(c0,c1) + dist(c1,c0).
# - count >= 1 → dist(c0,seq[0]) + inner + dist(seq[c-1],c1) + dist(c1,c0).
function _closed_tour_with_depots(m::Py, dist_arr::Py, seq::Py, c0::Int, c1::Int)
    c = m.count(seq)
    inner = m.lambda_function(
        pyfunc(i -> m.at(dist_arr, seq[i-1], seq[i]); wrap = "lambda f: lambda i: f(i)"),
    )
    inner_sum = m.sum(m.range(1, c), inner)
    nonempty = m.at(dist_arr, Py(c0), seq[0]) + m.at(dist_arr, seq[c-1], Py(c1))
    empty = m.at(dist_arr, Py(c0), Py(c1))
    wraparound = m.at(dist_arr, Py(c1), Py(c0))
    return inner_sum + m.iif(c > 0, nonempty, empty) + wraparound
end
