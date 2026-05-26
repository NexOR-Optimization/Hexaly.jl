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
    indices = MOI.VariableIndex[]
    for i = 0:(n-1)
        elem = hx_list[Py(i)]
        info = VariableInfo(MOI.VariableIndex(0), elem; is_integer = true)
        info.lb = 0.0
        info.ub = Float64(n - 1)
        idx = MOI.Utilities.CleverDicts.add_item(model.variable_info, info)
        _info(model, idx).index = idx
        push!(indices, idx)
    end
    cindex =
        MOI.ConstraintIndex{MOI.VectorOfVariables,List}(length(model.constraint_info) + 1)
    model.constraint_info[cindex] = ConstraintInfo(
        cindex,
        hx_list,  # store the list expression itself so the objective handler can find it
        MOI.VectorOfVariables(indices),
        set,
    )
    return indices, cindex
end
