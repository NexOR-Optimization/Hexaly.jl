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

# Below are type piracy that can be removed once
# https://github.com/jump-dev/JuMP.jl/pull/3451
# is merged
JuMP._is_real(::Array{<:Real}) = true

JuMP._is_real(::Array{<:JuMP.AbstractVariableRef}) = true

JuMP.moi_function(x::Array) = JuMP.moi_function.(x)

end # module
