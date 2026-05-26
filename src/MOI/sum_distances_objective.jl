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
    nodes = if nodes_raw isa MOI.VectorOfVariables
        nodes_raw.variables
    else
        nodes_raw::AbstractVector{MOI.VariableIndex}
    end
    n = length(nodes)
    n == size(dist_matrix, 1) == size(dist_matrix, 2) || error(
        "Hexaly: `:sum_distances` shape mismatch: dist_matrix is $(size(dist_matrix)), nodes has length $n.",
    )

    m = model.model
    dist_rows = Py[pylist(round.(Int, dist_matrix[i, :])) for i = 1:n]
    dist_arr = m.array(pylist(dist_rows))

    # If every variable shares the same `parent_list` (the usual case when
    # `nodes` is one column of a `Hexaly.Partition` or all of a `Hexaly.List`),
    # use the underlying list directly so the cyclic sum runs over the list's
    # *variable* count, not the static array length.
    first_pl = _info(model, nodes[1]).parent_list
    if first_pl !== nothing &&
       all(_info(model, vi).parent_list === first_pl for vi in nodes)
        seq = first_pl
    else
        seq = m.array(pylist(Py[_info(model, vi).variable for vi in nodes]))
    end

    c = m.count(seq)
    inner = m.lambda_function(
        pyfunc(i -> m.at(dist_arr, seq[i-1], seq[i]); wrap = "lambda f: lambda i: f(i)"),
    )
    closing = m.iif(c > 0, m.at(dist_arr, seq[c-1], seq[0]), Py(0))
    return m.sum(m.range(1, c), inner) + closing
end
