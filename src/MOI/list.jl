# `Hexaly.List` — a vector set backed by a Hexaly `model.list(n)` decision
# variable. The n MOI variables exposed by the set are the elements of the
# list; their values are a permutation of `0:n-1`.

struct List <: MOI.AbstractVectorSet
    dimension::Int
end

MOI.dimension(s::List) = s.dimension

function MOI.supports_add_constrained_variables(::Optimizer, ::Type{List})
    return true
end

function MOI.add_constrained_variables(model::Optimizer, set::List)
    n = set.dimension
    hx_list = model.model.list(Py(n))
    indices = _add_list_variables!(model, hx_list, n)
    cindex =
        MOI.ConstraintIndex{MOI.VectorOfVariables,List}(length(model.constraint_info) + 1)
    model.constraint_info[cindex] = ConstraintInfo(
        cindex,
        hx_list,
        MOI.VectorOfVariables(indices),
        set,
    )
    return indices, cindex
end

# Create `n` MOI variables backed by `hx_list[0..n-1]`, each tagged with
# `parent_list = hx_list` so the objective handler can recover the list.
function _add_list_variables!(model::Optimizer, hx_list::Py, n::Int)
    indices = MOI.VariableIndex[]
    for i = 0:(n-1)
        elem = hx_list[Py(i)]
        info = VariableInfo(
            MOI.VariableIndex(0),
            elem;
            is_integer = true,
            parent_list = hx_list,
        )
        info.lb = 0.0
        info.ub = Float64(n - 1)
        idx = MOI.Utilities.CleverDicts.add_item(model.variable_info, info)
        _info(model, idx).index = idx
        push!(indices, idx)
    end
    return indices
end

# `Hexaly.Partition` — `num_trucks` lists of size `num_clients`, with a
# `model.partition` constraint forcing each value in `0:num_clients-1` to
# appear in exactly one truck's list. The flat MOI representation lays out
# variables column-major: nodes[1..num_clients, 1], nodes[1..num_clients, 2], …

struct Partition <: MOI.AbstractVectorSet
    num_clients::Int
    num_trucks::Int
end

MOI.dimension(s::Partition) = s.num_clients * s.num_trucks

function MOI.supports_add_constrained_variables(::Optimizer, ::Type{Partition})
    return true
end

# JuMP needs an explicit `build_variable` for the 2D-matrix-in-vector-set form
# `@variable(model, x[1:nc, 1:nt] in Partition(nc, nt))`.
function JuMP.build_variable(
    error_fn::Function,
    variables::Matrix{<:JuMP.AbstractVariable},
    set::Partition,
)
    size(variables) == (set.num_clients, set.num_trucks) || error_fn(
        "Hexaly.Partition: expected a `$(set.num_clients) × $(set.num_trucks)` ",
        "variable matrix, got `$(size(variables))`.",
    )
    return JuMP.VariablesConstrainedOnCreation(
        vec(variables),
        set,
        JuMP.ArrayShape(size(variables)),
    )
end

function MOI.add_constrained_variables(model::Optimizer, set::Partition)
    m = model.model
    lists = Py[m.list(Py(set.num_clients)) for _ = 1:set.num_trucks]
    m.constraint(m.partition(pylist(lists)))
    indices = MOI.VariableIndex[]
    for hx_list in lists
        col_indices = _add_list_variables!(model, hx_list, set.num_clients)
        append!(indices, col_indices)
    end
    cindex = MOI.ConstraintIndex{MOI.VectorOfVariables,Partition}(
        length(model.constraint_info) + 1,
    )
    model.constraint_info[cindex] = ConstraintInfo(
        cindex,
        nothing,
        MOI.VectorOfVariables(indices),
        set,
    )
    return indices, cindex
end
