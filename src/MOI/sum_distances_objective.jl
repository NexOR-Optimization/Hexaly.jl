# Hexaly recognises `MOI.ScalarNonlinearFunction` with head `:sum_distances`
# as the closed-tour cost objective. Args: `[dist_matrix, nodes]` where
# `dist_matrix isa AbstractMatrix{<:Real}` and `nodes isa Vector{MOI.VariableIndex}`.
# Lowered to a Hexaly `sum(range, lambda)` expression that visits the list
# cyclically.

function MOI.supports(::Optimizer, ::MOI.ObjectiveFunction{MOI.ScalarNonlinearFunction})
    return true
end

function MOI.set(
    m::Optimizer,
    ::MOI.ObjectiveFunction{MOI.ScalarNonlinearFunction},
    f::MOI.ScalarNonlinearFunction,
)
    m.objective_function_type = MOI.ScalarNonlinearFunction
    m.objective_function = f
    return
end

# Lower a `ScalarNonlinearFunction` whose root head is `:sum_distances`, or a
# `:+` tree (sum of subexpressions) whose leaves are `:sum_distances` — the
# shape JuMP produces when the user writes
# `sum(MathOptVRP.op_sum_distances(...) for i in 1:n_trucks)`.
function _build_sum_distances_expression(m::Optimizer, f::MOI.ScalarNonlinearFunction)
    if f.head == :+
        terms = [_build_sum_distances_expression(m, arg) for arg in f.args]
        return reduce((a, b) -> sum(m.model, a, b), terms)
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

    md = m.model
    n_rows = size(dist_matrix, 1)
    n_rows == size(dist_matrix, 2) || error(
        "Hexaly: `:sum_distances` expects a square dist_matrix; got $(size(dist_matrix)).",
    )
    dist_rows = [array(md, round.(Int, dist_matrix[i, :])) for i = 1:n_rows]
    dist_arr = array(md, dist_rows)

    # Pattern A: every item is a list-element variable, and they all share
    # the same `parent_list`. Lower as a closed tour over that list (variable
    # count). Used by the TSP form `op_sum_distances(M, list_column)`.
    if all(it -> it isa MOI.VariableIndex, items)
        first_pl = _info(m, items[1]).parent_list
        if first_pl !== nothing &&
           all(_info(m, vi).parent_list === first_pl for vi in items)
            return _closed_tour_over_list(md, dist_arr, first_pl)
        end
    end

    # Pattern B: `[const c0, list_vars..., const c1]` with all list_vars
    # sharing the same parent_list.
    if length(items) >= 3 &&
       items[1] isa Real &&
       items[end] isa Real &&
       all(items[i] isa MOI.VariableIndex for i = 2:(length(items)-1))
        first_pl = _info(m, items[2]).parent_list
        if first_pl !== nothing &&
           all(_info(m, items[i]).parent_list === first_pl for i = 2:(length(items)-1))
            return _closed_tour_with_depots(
                md,
                dist_arr,
                first_pl,
                round(Int, items[1]),
                round(Int, items[end]),
            )
        end
    end

    # Fallback: fixed-length closed tour over a static array of mixed
    # constants and variables.
    elements = HxExpression[_item_to_expr(m, it) for it in items]
    seq = array(md, elements)
    c = count_(md, seq)
    inner = lambda_function(md,
        i -> at(md, dist_arr, at(md, seq, sub(md, i, 1)), at(md, seq, i)); nargs = 1)
    closing = iif(md,
        gt(md, c, 0),
        at(md, dist_arr, at(md, seq, sub(md, c, 1)), at(md, seq, 0)),
        0,
    )
    return sum(md, sum(md, range_(md, 1, c), inner), closing)
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

function _item_to_expr(m::Optimizer, it)
    if it isa MOI.VariableIndex
        return _info(m, it).variable
    elseif it isa Real
        return create_constant(m.model, round(Int, it))
    end
    return error("Hexaly: `:sum_distances` cannot lower item of type $(typeof(it))")
end

# Closed tour over a Hexaly list with *variable* count.
function _closed_tour_over_list(md::HxModel, dist_arr::HxExpression, seq::HxExpression)
    c = count_(md, seq)
    inner = lambda_function(md,
        i -> at(md, dist_arr, at(md, seq, sub(md, i, 1)), at(md, seq, i)); nargs = 1)
    closing = iif(md,
        gt(md, c, 0),
        at(md, dist_arr, at(md, seq, sub(md, c, 1)), at(md, seq, 0)),
        0,
    )
    return sum(md, sum(md, range_(md, 1, c), inner), closing)
end

# Closed tour over `[c0, seq[0], seq[1], ..., seq[count-1], c1]`.
function _closed_tour_with_depots(
    md::HxModel, dist_arr::HxExpression, seq::HxExpression, c0::Int, c1::Int,
)
    c = count_(md, seq)
    inner = lambda_function(md,
        i -> at(md, dist_arr, at(md, seq, sub(md, i, 1)), at(md, seq, i)); nargs = 1)
    inner_sum = sum(md, range_(md, 1, c), inner)
    nonempty = sum(md,
        at(md, dist_arr, c0, at(md, seq, 0)),
        at(md, dist_arr, at(md, seq, sub(md, c, 1)), c1),
    )
    empty_ = at(md, dist_arr, c0, c1)
    wraparound = at(md, dist_arr, c1, c0)
    return sum(md, sum(md, inner_sum, iif(md, gt(md, c, 0), nonempty, empty_)), wraparound)
end
