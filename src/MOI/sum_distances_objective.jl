# Hexaly recognises `MOI.ScalarNonlinearFunction` with head `:sum_distances`
# as the closed-tour cost objective. Args: `[dist_matrix, nodes]` where
# `dist_matrix isa AbstractMatrix{<:Real}` and `nodes isa Vector{MOI.VariableIndex}`.
# Lowered to a Hexaly `model.sum(range, lambda)` expression that visits the
# list cyclically.

function MOI.supports(
    ::Optimizer,
    ::MOI.ObjectiveFunction{MOI.ScalarNonlinearFunction},
)
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

function _build_sum_distances_expression(
    model::Optimizer,
    f::MOI.ScalarNonlinearFunction,
)
    f.head == :sum_distances || error(
        "Hexaly: unsupported ScalarNonlinearFunction head `$(f.head)`. ",
        "Only `:sum_distances` is currently lowered.",
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

    # The Hexaly list expression is the Py object stored on the FIRST variable
    # of the List set; all n MOI variables share the same backing list (since
    # `add_constrained_variables(::List)` created them from `list[i]` slices).
    # Recover the list by walking up to the parent — instead of relying on
    # that, we rebuild the Hexaly list expression from the per-element refs.
    m = model.model
    elements = Py[_info(model, vi).variable for vi in nodes]
    seq = m.array(pylist(elements))

    dist_rows = Py[pylist(round.(Int, dist_matrix[i, :])) for i in 1:n]
    dist_arr = m.array(pylist(dist_rows))

    c = m.count(seq)
    inner = m.lambda_function(pyfunc(
        i -> m.at(dist_arr, seq[i - 1], seq[i]);
        wrap = "lambda f: lambda i: f(i)",
    ))
    closing = m.at(dist_arr, seq[c - 1], seq[0])
    return m.sum(m.range(1, c), inner) + closing
end
