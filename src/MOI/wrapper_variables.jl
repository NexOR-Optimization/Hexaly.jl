function _info(m::Optimizer, key::MOI.VariableIndex)
    if haskey(m.variable_info, key)
        return m.variable_info[key]
    end
    throw(MOI.InvalidIndex(key))
end

function _make_var(
    m::Optimizer,
    variable::Union{Nothing,HxExpression} = nothing;
    is_integer::Bool = false,
    used::Bool = variable !== nothing,
)
    index = MOI.Utilities.CleverDicts.add_item(
        m.variable_info,
        VariableInfo(MOI.VariableIndex(0), variable; is_integer, used),
    )
    _info(m, index).index = index
    return index
end

function _make_var(
    m::Optimizer,
    variable::Union{Nothing,HxExpression},
    set::MOI.AbstractScalarSet;
    is_integer::Bool = true,
)
    index = _make_var(m, variable; is_integer = is_integer)
    S = typeof(set)
    return index, MOI.ConstraintIndex{MOI.VariableIndex,S}(index.value)
end

function _materialize!(m::Optimizer, info::VariableInfo)
    info.variable !== nothing && return info.variable
    if info.is_binary
        info.variable = _new_bool(m)
    elseif info.is_integer
        lb = info.lb === nothing ? _DEFAULT_INT_LB : ceil(Int, info.lb)
        ub = info.ub === nothing ? _DEFAULT_INT_UB : floor(Int, info.ub)
        info.variable = _new_int(m, lb, ub)
    else
        lb = info.lb === nothing ? _DEFAULT_FLOAT_LB : info.lb
        ub = info.ub === nothing ? _DEFAULT_FLOAT_UB : info.ub
        info.variable = _new_float(m, lb, ub)
    end
    !isempty(info.name) && set_name!(info.variable, info.name)
    return info.variable
end

function _expression!(m::Optimizer, index::MOI.VariableIndex)
    info = _info(m, index)
    variable = _materialize!(m, info)
    info.used = true
    return variable
end

function _define_expression!(
    m::Optimizer,
    index::MOI.VariableIndex,
    expression::HxExpression,
)
    info = _info(m, index)
    info.used && error(
        "Cannot define variable $index: it has already been used or materialized.",
    )
    info.variable === nothing || error("Variable $index is already defined.")
    info.variable = expression
    info.is_defined = true
    !isempty(info.name) && set_name!(expression, info.name)
    return
end

_new_int(m::Optimizer, lb::Int, ub::Int) = int!(m.model, lb, ub)
_new_float(m::Optimizer, lb::Real, ub::Real) =
    float!(m.model, Float64(lb), Float64(ub))
_new_bool(m::Optimizer) = bool!(m.model)

function MOI.supports_add_constrained_variable(
    ::Optimizer,
    ::Type{F},
) where {
    F<:Union{
        MOI.EqualTo{Int},
        MOI.LessThan{Int},
        MOI.GreaterThan{Int},
        MOI.Interval{Int},
        MOI.EqualTo{Float64},
        MOI.LessThan{Float64},
        MOI.GreaterThan{Float64},
        MOI.Interval{Float64},
        MOI.ZeroOne,
        MOI.Integer,
    },
}
    return true
end

function MOI.add_variable(m::Optimizer)
    return _make_var(m)
end

function MOI.add_constrained_variable(m::Optimizer, set::MOI.Integer)
    vindex, cindex = _make_var(m, nothing, set; is_integer = true)
    _info(m, vindex).is_integer = true
    return vindex, cindex
end

function MOI.add_constrained_variable(m::Optimizer, set::MOI.ZeroOne)
    vindex, cindex = _make_var(m, nothing, set; is_integer = true)
    info = _info(m, vindex)
    info.is_binary = true
    info.is_integer = true
    info.lb = 0.0
    info.ub = 1.0
    return vindex, cindex
end

function MOI.add_constrained_variable(m::Optimizer, set::MOI.EqualTo{T}) where {T<:Real}
    val = set.value
    is_int = T <: Integer
    vindex, cindex = _make_var(m, nothing, set; is_integer = is_int)
    info = _info(m, vindex)
    info.lb = Float64(val)
    info.ub = Float64(val)
    return vindex, cindex
end

function MOI.add_constrained_variable(
    m::Optimizer,
    set::MOI.GreaterThan{T},
) where {T<:Real}
    if T <: Integer
        lb = ceil(Int, set.lower)
        is_int = true
    else
        is_int = false
    end
    vindex, cindex = _make_var(m, nothing, set; is_integer = is_int)
    _info(m, vindex).lb = Float64(set.lower)
    return vindex, cindex
end

function MOI.add_constrained_variable(
    m::Optimizer,
    set::MOI.LessThan{T},
) where {T<:Real}
    if T <: Integer
        ub = floor(Int, set.upper)
        is_int = true
    else
        is_int = false
    end
    vindex, cindex = _make_var(m, nothing, set; is_integer = is_int)
    _info(m, vindex).ub = Float64(set.upper)
    return vindex, cindex
end

function MOI.add_constrained_variable(
    m::Optimizer,
    set::MOI.Interval{T},
) where {T<:Real}
    if T <: Integer
        lb = ceil(Int, set.lower)
        ub = floor(Int, set.upper)
        is_int = true
    else
        is_int = false
    end
    vindex, cindex = _make_var(m, nothing, set; is_integer = is_int)
    info = _info(m, vindex)
    info.lb = Float64(set.lower)
    info.ub = Float64(set.upper)
    return vindex, cindex
end

MOI.is_valid(m::Optimizer, v::MOI.VariableIndex) = haskey(m.variable_info, v)

# VariableName

function MOI.supports(::Optimizer, ::MOI.VariableName, ::Type{MOI.VariableIndex})
    return true
end

MOI.get(m::Optimizer, ::MOI.VariableName, v::MOI.VariableIndex) = _info(m, v).name

function MOI.set(m::Optimizer, ::MOI.VariableName, v::MOI.VariableIndex, name::String)
    info = _info(m, v)
    info.name = name
    if !isempty(name) && info.variable !== nothing
        try
            set_name!(info.variable, name)
        catch
        end
    end
    return
end

function MOI.get(m::Optimizer, ::Type{MOI.VariableIndex}, name::String)
    found = MOI.VariableIndex[]
    for (k, info) in m.variable_info
        if info.name == name
            push!(found, k)
        end
    end
    if length(found) == 0
        return nothing
    elseif length(found) == 1
        return found[1]
    else
        error("Multiple variables have name $name")
    end
end
