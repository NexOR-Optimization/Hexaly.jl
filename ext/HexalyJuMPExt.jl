module HexalyJuMPExt

import Hexaly
import JuMP
import MathOptInterface as MOI

# Build a JuMP nonlinear expression representing the total length of the
# closed tour induced by `nodes`, using `dist_matrix` as the edge weights.
# `nodes` is a vector of JuMP variable references (typically from
# `@variable(model, nodes[1:n] in Hexaly.List())`). `dist_matrix` is a
# constant `AbstractMatrix{<:Real}`. The Hexaly `Optimizer` recognises the
# `:sum_distances` head when this expression is set as the objective.

function Hexaly.sum_distances(
    dist_matrix::AbstractMatrix{<:Real},
    nodes::AbstractVector{V},
) where {V<:JuMP.AbstractVariableRef}
    return JuMP.GenericNonlinearExpr{V}(
        :sum_distances,
        Any[dist_matrix, nodes],
    )
end

# JuMP's default `_is_real` only accepts scalar leaves. We allow constant
# numeric arrays and vectors of variable references so the args of the
# `:sum_distances` expression pass JuMP's validation.
JuMP._is_real(::AbstractArray{<:Real}) = true
JuMP._is_real(::AbstractArray{<:JuMP.AbstractVariableRef}) = true

# Convert each arg of a `GenericNonlinearExpr` to its MOI form when the
# objective is set. The default `moi_function` covers scalars; extend it for
# the two array shapes we use as `sum_distances` args.
JuMP.moi_function(x::AbstractArray{<:Real}) = x

function JuMP.moi_function(x::AbstractVector{<:JuMP.AbstractVariableRef})
    return MOI.VariableIndex[JuMP.index(v) for v in x]
end

end # module
