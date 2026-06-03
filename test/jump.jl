using JuMP
using Hexaly
using PythonCall
using Test
import MathOptInterface as MOI
import MathOptVRP

# Hexaly-specific recovery of each truck's variable-length list from the
# `nodes` partition variables. Reaches through `JuMP.unsafe_backend` into
# the Hexaly `Optimizer` to read each list's solved value (its
# `count()` + per-position values), which can't be inferred from the
# JuMP variable values alone since trucks have variable length.
function _hexaly_read_routes(model, nodes)
    inner = JuMP.unsafe_backend(model)
    routes = Vector{Int}[]
    for i = 1:size(nodes, 2)
        vi = JuMP.index(nodes[1, i])
        list_py = inner.variable_info[vi].parent_list::PythonCall.Py
        list_val = list_py.value
        c = pyconvert(Int, list_val.count())
        push!(routes, [pyconvert(Int, list_val[Py(k)]) for k = 0:(c-1)])
    end
    return routes
end

MathOptVRP.runtests(Hexaly.Optimizer; read_routes = _hexaly_read_routes)
