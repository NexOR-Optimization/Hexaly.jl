function _info(m::Optimizer, key::MOI.VariableIndex)
    if haskey(m.variable_info, key)
        return m.variable_info[key]
    end
    throw(MOI.InvalidIndex(key))
end

function _make_var(m::Optimizer, variable::HxExpression; is_integer::Bool = true)
    index = MOI.Utilities.CleverDicts.add_item(
        m.variable_info,
        VariableInfo(MOI.VariableIndex(0), variable; is_integer = is_integer),
    )
    _info(m, index).index = index
    return index
end

function _make_var(
    m::Optimizer,
    variable::HxExpression,
    set::MOI.AbstractScalarSet;
    is_integer::Bool = true,
)
    index = _make_var(m, variable; is_integer = is_integer)
    S = typeof(set)
    return index, MOI.ConstraintIndex{MOI.VariableIndex,S}(index.value)
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
    v = _new_float(m, _DEFAULT_FLOAT_LB, _DEFAULT_FLOAT_UB)
    return _make_var(m, v; is_integer = false)
end

function MOI.add_constrained_variable(m::Optimizer, set::MOI.Integer)
    v = _new_int(m, _DEFAULT_INT_LB, _DEFAULT_INT_UB)
    vindex, cindex = _make_var(m, v, set; is_integer = true)
    _info(m, vindex).is_integer = true
    return vindex, cindex
end

function MOI.add_constrained_variable(m::Optimizer, set::MOI.ZeroOne)
    v = _new_bool(m)
    vindex, cindex = _make_var(m, v, set; is_integer = true)
    info = _info(m, vindex)
    info.is_binary = true
    info.is_integer = true
    info.lb = 0.0
    info.ub = 1.0
    return vindex, cindex
end

function MOI.add_constrained_variable(m::Optimizer, set::MOI.EqualTo{T}) where {T<:Real}
    val = set.value
    if T <: Integer
        v = _new_int(m, Int(val), Int(val))
        is_int = true
    else
        v = _new_float(m, val, val)
        is_int = false
    end
    vindex, cindex = _make_var(m, v, set; is_integer = is_int)
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
        v = _new_int(m, lb, _DEFAULT_INT_UB)
        is_int = true
    else
        v = _new_float(m, set.lower, _DEFAULT_FLOAT_UB)
        is_int = false
    end
    vindex, cindex = _make_var(m, v, set; is_integer = is_int)
    _info(m, vindex).lb = Float64(set.lower)
    return vindex, cindex
end

function MOI.add_constrained_variable(
    m::Optimizer,
    set::MOI.LessThan{T},
) where {T<:Real}
    if T <: Integer
        ub = floor(Int, set.upper)
        v = _new_int(m, _DEFAULT_INT_LB, ub)
        is_int = true
    else
        v = _new_float(m, _DEFAULT_FLOAT_LB, set.upper)
        is_int = false
    end
    vindex, cindex = _make_var(m, v, set; is_integer = is_int)
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
        v = _new_int(m, lb, ub)
        is_int = true
    else
        v = _new_float(m, set.lower, set.upper)
        is_int = false
    end
    vindex, cindex = _make_var(m, v, set; is_integer = is_int)
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
    if !isempty(name)
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
