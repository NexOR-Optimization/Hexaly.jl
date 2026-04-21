function _info(model::Optimizer, key::MOI.VariableIndex)
    if haskey(model.variable_info, key)
        return model.variable_info[key]
    end
    throw(MOI.InvalidIndex(key))
end

function _make_var(model::Optimizer, variable::Py; is_integer::Bool = true)
    index = CleverDicts.add_item(
        model.variable_info,
        VariableInfo(MOI.VariableIndex(0), variable; is_integer = is_integer),
    )
    _info(model, index).index = index
    return index
end

function _make_var(
    model::Optimizer,
    variable::Py,
    set::MOI.AbstractScalarSet;
    is_integer::Bool = true,
)
    index = _make_var(model, variable; is_integer = is_integer)
    S = typeof(set)
    return index, MOI.ConstraintIndex{MOI.VariableIndex, S}(index.value)
end

_new_int(model::Optimizer, lb::Int, ub::Int) = model.model.int(Py(lb), Py(ub))
_new_float(model::Optimizer, lb::Real, ub::Real) =
    model.model.float(Py(Float64(lb)), Py(Float64(ub)))
_new_bool(model::Optimizer) = model.model.bool()

function MOI.supports_add_constrained_variable(
    ::Optimizer,
    ::Type{F},
) where {
    F <: Union{
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

function MOI.add_variable(model::Optimizer)
    v = _new_float(model, _DEFAULT_FLOAT_LB, _DEFAULT_FLOAT_UB)
    return _make_var(model, v; is_integer = false)
end

function MOI.add_constrained_variable(model::Optimizer, set::MOI.Integer)
    v = _new_int(model, _DEFAULT_INT_LB, _DEFAULT_INT_UB)
    vindex, cindex = _make_var(model, v, set; is_integer = true)
    _info(model, vindex).is_integer = true
    return vindex, cindex
end

function MOI.add_constrained_variable(model::Optimizer, set::MOI.ZeroOne)
    v = _new_bool(model)
    vindex, cindex = _make_var(model, v, set; is_integer = true)
    info = _info(model, vindex)
    info.is_binary = true
    info.is_integer = true
    info.lb = 0.0
    info.ub = 1.0
    return vindex, cindex
end

function MOI.add_constrained_variable(
    model::Optimizer,
    set::MOI.EqualTo{T},
) where {T <: Real}
    val = set.value
    if T <: Integer
        v = _new_int(model, Int(val), Int(val))
        is_int = true
    else
        v = _new_float(model, val, val)
        is_int = false
    end
    vindex, cindex = _make_var(model, v, set; is_integer = is_int)
    info = _info(model, vindex)
    info.lb = Float64(val)
    info.ub = Float64(val)
    return vindex, cindex
end

function MOI.add_constrained_variable(
    model::Optimizer,
    set::MOI.GreaterThan{T},
) where {T <: Real}
    if T <: Integer
        lb = ceil(Int, set.lower)
        v = _new_int(model, lb, _DEFAULT_INT_UB)
        is_int = true
    else
        v = _new_float(model, set.lower, _DEFAULT_FLOAT_UB)
        is_int = false
    end
    vindex, cindex = _make_var(model, v, set; is_integer = is_int)
    _info(model, vindex).lb = Float64(set.lower)
    return vindex, cindex
end

function MOI.add_constrained_variable(
    model::Optimizer,
    set::MOI.LessThan{T},
) where {T <: Real}
    if T <: Integer
        ub = floor(Int, set.upper)
        v = _new_int(model, _DEFAULT_INT_LB, ub)
        is_int = true
    else
        v = _new_float(model, _DEFAULT_FLOAT_LB, set.upper)
        is_int = false
    end
    vindex, cindex = _make_var(model, v, set; is_integer = is_int)
    _info(model, vindex).ub = Float64(set.upper)
    return vindex, cindex
end

function MOI.add_constrained_variable(
    model::Optimizer,
    set::MOI.Interval{T},
) where {T <: Real}
    if T <: Integer
        lb = ceil(Int, set.lower)
        ub = floor(Int, set.upper)
        v = _new_int(model, lb, ub)
        is_int = true
    else
        v = _new_float(model, set.lower, set.upper)
        is_int = false
    end
    vindex, cindex = _make_var(model, v, set; is_integer = is_int)
    info = _info(model, vindex)
    info.lb = Float64(set.lower)
    info.ub = Float64(set.upper)
    return vindex, cindex
end

MOI.is_valid(model::Optimizer, v::MOI.VariableIndex) = haskey(model.variable_info, v)

# VariableName

function MOI.supports(::Optimizer, ::MOI.VariableName, ::Type{MOI.VariableIndex})
    return true
end

MOI.get(model::Optimizer, ::MOI.VariableName, v::MOI.VariableIndex) = _info(model, v).name

function MOI.set(
    model::Optimizer,
    ::MOI.VariableName,
    v::MOI.VariableIndex,
    name::String,
)
    info = _info(model, v)
    info.name = name
    if !isempty(name)
        try
            info.variable.set_name(name)
        catch
        end
    end
    return
end

function MOI.get(model::Optimizer, ::Type{MOI.VariableIndex}, name::String)
    for (k, info) in model.variable_info
        if info.name == name
            return k
        end
    end
    return nothing
end
