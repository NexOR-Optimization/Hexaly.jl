# MathOptVRP definition constraints. The first MOI variable is substituted by
# a native Hexaly expression; no Hexaly decision is created for it.

for SetType in (MathOptVRP.IsEmpty, MathOptVRP.SumGetIndex)
    @eval begin
        function MOI.supports_constraint(
            ::Optimizer,
            ::Type{<:Union{MOI.VectorOfVariables,MOI.VectorAffineFunction}},
            ::Type{<:$SetType},
        )
            return true
        end

        function MOI.supports_add_constrained_variables(
            ::Optimizer,
            ::Type{<:$SetType},
        )
            return false
        end
    end
end

function _definition_output_and_route(
    m::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    dimension::Int,
    name::AbstractString,
)
    items = _normalize_sum_distances_items(f)
    length(items) == dimension || error(
        "$name expected $dimension variables; got $(length(items)).",
    )
    all(it -> it isa MOI.VariableIndex, items) || error(
        "$name expects only `MOI.VariableIndex` values.",
    )
    output = items[1]
    route_vars = items[2:end]
    route = _info(m, route_vars[1]).parent_list
    route !== nothing || error("$name route variables have no parent Hexaly list.")
    all(_info(m, vi).parent_list === route for vi in route_vars) || error(
        "$name route variables must belong to the same Hexaly list.",
    )
    return output, route
end

function MOI.add_constraint(
    m::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::MathOptVRP.IsEmpty,
)
    output, route = _definition_output_and_route(
        m, f, MOI.dimension(s), "MathOptVRP.IsEmpty",
    )
    info = _info(m, output)
    info.is_binary || error(
        "MathOptVRP.IsEmpty output must be created in `MOI.ZeroOne`.",
    )
    _define_expression!(m, output, eq(m.model, count_(m.model, route), 0))
    cindex = MOI.ConstraintIndex{typeof(f),typeof(s)}(
        length(m.constraint_info) + 1,
    )
    m.constraint_info[cindex] = ConstraintInfo(cindex, nothing, f, s)
    return cindex
end

function MOI.add_constraint(
    m::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::MathOptVRP.SumGetIndex,
)
    output, route = _definition_output_and_route(
        m, f, MOI.dimension(s), "MathOptVRP.SumGetIndex",
    )
    terms = HxExpression[
        prod(m.model, s.values[i], contains_(m.model, route, i - 1))
        for i in eachindex(s.values) if !iszero(s.values[i])
    ]
    expression = isempty(terms) ? create_constant(m.model, 0) :
        sum(m.model, terms...)
    info = _info(m, output)
    info.is_integer = all(isinteger, s.values)
    _define_expression!(m, output, expression)
    cindex = MOI.ConstraintIndex{typeof(f),typeof(s)}(
        length(m.constraint_info) + 1,
    )
    m.constraint_info[cindex] = ConstraintInfo(cindex, nothing, f, s)
    return cindex
end
