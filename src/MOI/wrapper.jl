# Default domain bounds for Hexaly integer variables when none are specified.
# Hexaly requires explicit bounds for `model.int(lb, ub)`.
const _DEFAULT_INT_LB = -1_000_000
const _DEFAULT_INT_UB = 1_000_000
const _DEFAULT_FLOAT_LB = -1e15
const _DEFAULT_FLOAT_UB = 1e15

# Hexaly requires a time limit before solving. This is the default if the
# user hasn't set one via `MOI.TimeLimitSec` or `MOI.RawOptimizerAttribute`.
const _DEFAULT_TIME_LIMIT = 10

mutable struct VariableInfo
    index::MOI.VariableIndex
    variable::Py  # Hexaly HxExpression (decision)
    name::String
    lb::Union{Nothing, Float64}
    ub::Union{Nothing, Float64}
    is_binary::Bool
    is_integer::Bool
end

function VariableInfo(index::MOI.VariableIndex, variable::Py; is_integer::Bool = true)
    return VariableInfo(index, variable, "", nothing, nothing, false, is_integer)
end

mutable struct ConstraintInfo
    index::MOI.ConstraintIndex
    constraint::Union{Py, Nothing}  # Hexaly constraint expression
    f::Union{MOI.AbstractScalarFunction, MOI.AbstractVectorFunction}
    set::MOI.AbstractSet
    name::String
end

function ConstraintInfo(
    index::MOI.ConstraintIndex,
    constraint::Union{Py, Nothing},
    f::Union{MOI.AbstractScalarFunction, MOI.AbstractVectorFunction},
    set::MOI.AbstractSet,
)
    return ConstraintInfo(index, constraint, f, set, "")
end

mutable struct Optimizer <: MOI.AbstractOptimizer
    inner::Py   # HexalyOptimizer
    model::Py   # HxModel
    variable_info::MOI.Utilities.CleverDicts.CleverDict{MOI.VariableIndex, VariableInfo}
    constraint_info::Dict{MOI.ConstraintIndex, ConstraintInfo}
    name::String
    objective_sense::MOI.OptimizationSense
    objective_function_type::Union{Nothing, DataType}
    objective_function::Union{
        Nothing,
        MOI.VariableIndex,
        MOI.ScalarAffineFunction{Float64},
        MOI.ScalarAffineFunction{Int},
    }
    silent::Bool
    time_limit::Int
    options::Dict{String, Any}
    termination_status::MOI.TerminationStatusCode
    primal_status::MOI.ResultStatusCode
    raw_status_string::String
    solved::Bool

    function Optimizer()
        model = new()
        model.inner = raw_optimizer()
        model.model = model.inner.model
        model.variable_info = MOI.Utilities.CleverDicts.CleverDict{MOI.VariableIndex, VariableInfo}()
        model.constraint_info = Dict{MOI.ConstraintIndex, ConstraintInfo}()
        model.name = ""
        model.objective_sense = MOI.FEASIBILITY_SENSE
        model.objective_function_type = nothing
        model.objective_function = nothing
        model.silent = false
        model.time_limit = _DEFAULT_TIME_LIMIT
        model.options = Dict{String, Any}()
        model.termination_status = MOI.OPTIMIZE_NOT_CALLED
        model.primal_status = MOI.NO_SOLUTION
        model.raw_status_string = ""
        model.solved = false
        finalizer(_finalize, model)
        return model
    end
end

function _finalize(model::Optimizer)
    try
        model.inner.delete()
    catch
    end
    return
end

function MOI.empty!(model::Optimizer)
    try
        model.inner.delete()
    catch
    end
    model.inner = raw_optimizer()
    model.model = model.inner.model
    empty!(model.variable_info)
    empty!(model.constraint_info)
    model.name = ""
    model.objective_sense = MOI.FEASIBILITY_SENSE
    model.objective_function_type = nothing
    model.objective_function = nothing
    model.termination_status = MOI.OPTIMIZE_NOT_CALLED
    model.primal_status = MOI.NO_SOLUTION
    model.raw_status_string = ""
    model.solved = false
    return
end

function MOI.is_empty(model::Optimizer)
    !isempty(model.name) && return false
    !isempty(model.variable_info) && return false
    !isempty(model.constraint_info) && return false
    model.objective_sense != MOI.FEASIBILITY_SENSE && return false
    model.objective_function_type !== nothing && return false
    model.objective_function !== nothing && return false
    model.solved && return false
    return true
end

MOI.get(::Optimizer, ::MOI.SolverName) = "Hexaly"

function MOI.get(::Optimizer, ::MOI.SolverVersion)
    return string(version())
end

# Name

function MOI.supports(::Optimizer, ::MOI.Name)
    return true
end

MOI.get(model::Optimizer, ::MOI.Name) = model.name

function MOI.set(model::Optimizer, ::MOI.Name, name::String)
    model.name = name
    return
end

# Silent / Verbosity

MOI.supports(::Optimizer, ::MOI.Silent) = true
MOI.get(model::Optimizer, ::MOI.Silent) = model.silent
function MOI.set(model::Optimizer, ::MOI.Silent, silent::Bool)
    model.silent = silent
    return
end

# Time limit

MOI.supports(::Optimizer, ::MOI.TimeLimitSec) = true
MOI.get(model::Optimizer, ::MOI.TimeLimitSec) = Float64(model.time_limit)

function MOI.set(model::Optimizer, ::MOI.TimeLimitSec, ::Nothing)
    model.time_limit = _DEFAULT_TIME_LIMIT
    return
end

function MOI.set(model::Optimizer, ::MOI.TimeLimitSec, value::Real)
    model.time_limit = max(1, round(Int, value))
    return
end

# Raw optimizer attributes (mapped to Hexaly `param` settings)

MOI.supports(::Optimizer, ::MOI.RawOptimizerAttribute) = true

function MOI.get(model::Optimizer, attr::MOI.RawOptimizerAttribute)
    return get(model.options, attr.name, nothing)
end

function MOI.set(model::Optimizer, attr::MOI.RawOptimizerAttribute, value)
    model.options[attr.name] = value
    return
end

# Objective support

function MOI.supports(
    ::Optimizer,
    ::MOI.ObjectiveFunction{F},
) where {F <: Union{
    MOI.VariableIndex,
    MOI.ScalarAffineFunction{Float64},
    MOI.ScalarAffineFunction{Int},
}}
    return true
end

MOI.supports(::Optimizer, ::MOI.ObjectiveSense) = true

MOI.get(model::Optimizer, ::MOI.ObjectiveSense) = model.objective_sense

function MOI.set(model::Optimizer, ::MOI.ObjectiveSense, sense::MOI.OptimizationSense)
    model.objective_sense = sense
    return
end

function MOI.get(model::Optimizer, ::MOI.ObjectiveFunctionType)
    return model.objective_function_type
end

function MOI.get(model::Optimizer, ::MOI.ObjectiveFunction{F}) where {F}
    if model.objective_function_type !== F
        error("Objective function type is $(model.objective_function_type), not $F.")
    end
    return model.objective_function::F
end

function MOI.set(
    model::Optimizer,
    ::MOI.ObjectiveFunction{F},
    f::F,
) where {F <: Union{
    MOI.VariableIndex,
    MOI.ScalarAffineFunction{Float64},
    MOI.ScalarAffineFunction{Int},
}}
    model.objective_function_type = F
    model.objective_function = f
    return
end

function MOI.get(model::Optimizer, ::MOI.ListOfModelAttributesSet)
    attributes = Any[MOI.ObjectiveSense()]
    typ = model.objective_function_type
    if typ !== nothing
        push!(attributes, MOI.ObjectiveFunction{typ}())
    end
    if !isempty(model.name)
        push!(attributes, MOI.Name())
    end
    return attributes
end

# Incremental interface

MOI.supports_incremental_interface(::Optimizer) = true

function MOI.copy_to(dest::Optimizer, src::MOI.ModelLike)
    return MOI.Utilities.default_copy_to(dest, src)
end

# Apply Hexaly parameters (time limit, verbosity, raw options)

function _apply_params!(model::Optimizer)
    param = model.inner.param
    param.time_limit = model.time_limit
    param.verbosity = model.silent ? 0 : 1
    for (k, v) in model.options
        try
            setproperty!(param, Symbol(k), v)
        catch
            try
                param.set_advanced_param(k, v)
            catch err
                @warn "Hexaly: could not set parameter $(k)=$(v)" error=err
            end
        end
    end
    return
end

function _map_status(model::Optimizer, status::Py)
    status_str = pyconvert(String, pystr(status))
    # HxSolutionStatus: INCONSISTENT, INFEASIBLE, FEASIBLE, OPTIMAL
    if occursin("OPTIMAL", status_str)
        return MOI.OPTIMAL, MOI.FEASIBLE_POINT, status_str
    elseif occursin("FEASIBLE", status_str)
        return MOI.LOCALLY_SOLVED, MOI.FEASIBLE_POINT, status_str
    elseif occursin("INFEASIBLE", status_str)
        return MOI.INFEASIBLE, MOI.NO_SOLUTION, status_str
    elseif occursin("INCONSISTENT", status_str)
        return MOI.INFEASIBLE, MOI.NO_SOLUTION, status_str
    else
        return MOI.OTHER_ERROR, MOI.NO_SOLUTION, status_str
    end
end

# Optimize

function MOI.optimize!(model::Optimizer)
    # Build objective (before closing the model).
    if model.objective_function !== nothing && model.objective_sense != MOI.FEASIBILITY_SENSE
        obj_expr = _build_objective_expression(model)
        if model.objective_sense == MOI.MIN_SENSE
            model.model.minimize(obj_expr)
        else
            model.model.maximize(obj_expr)
        end
    end

    # Close the model (required before solving).
    if !pyconvert(Bool, model.model.is_closed())
        model.model.close()
    end

    _apply_params!(model)

    try
        model.inner.solve()
    catch err
        model.termination_status = MOI.OTHER_ERROR
        model.primal_status = MOI.NO_SOLUTION
        model.raw_status_string = sprint(showerror, err)
        model.solved = true
        return
    end

    status = model.inner.solution.status
    t, p, s = _map_status(model, status)
    model.termination_status = t
    model.primal_status = p
    model.raw_status_string = s
    model.solved = true
    return
end

# Solution getters

MOI.get(model::Optimizer, ::MOI.TerminationStatus) = model.termination_status

function MOI.get(model::Optimizer, attr::MOI.PrimalStatus)
    if attr.result_index != 1
        return MOI.NO_SOLUTION
    end
    return model.primal_status
end

MOI.get(::Optimizer, ::MOI.DualStatus) = MOI.NO_SOLUTION

MOI.get(model::Optimizer, ::MOI.RawStatusString) = model.raw_status_string

function MOI.get(model::Optimizer, ::MOI.ResultCount)
    return model.primal_status == MOI.NO_SOLUTION ? 0 : 1
end

function MOI.get(
    model::Optimizer,
    attr::MOI.VariablePrimal,
    vi::MOI.VariableIndex,
)
    MOI.check_result_index_bounds(model, attr)
    info = _info(model, vi)
    val = info.variable.value
    if info.is_integer
        return pyconvert(Int, val)
    else
        return pyconvert(Float64, val)
    end
end

function MOI.get(model::Optimizer, attr::MOI.ObjectiveValue)
    MOI.check_result_index_bounds(model, attr)
    if model.objective_function === nothing || model.objective_sense == MOI.FEASIBILITY_SENSE
        return 0.0
    end
    return _evaluate_objective(model)
end

function _evaluate_objective(model::Optimizer)
    f = model.objective_function
    if f isa MOI.VariableIndex
        info = _info(model, f)
        val = info.variable.value
        return info.is_integer ? pyconvert(Int, val) : pyconvert(Float64, val)
    else
        # ScalarAffineFunction
        T = typeof(f).parameters[1]
        val = f.constant
        for t in f.terms
            info = _info(model, t.variable)
            v = info.is_integer ? pyconvert(Int, info.variable.value) :
                pyconvert(Float64, info.variable.value)
            val += t.coefficient * v
        end
        if T <: Integer
            return round(Int, val)
        end
        return val
    end
end

function MOI.get(model::Optimizer, ::MOI.SolveTimeSec)
    if !model.solved
        return 0.0
    end
    return Float64(pyconvert(Int, model.inner.statistics.running_time))
end

# Number of variables / constraints (MOI bookkeeping)

MOI.get(model::Optimizer, ::MOI.NumberOfVariables) = length(model.variable_info)

function MOI.get(model::Optimizer, ::MOI.ListOfVariableIndices)
    return sort!(collect(keys(model.variable_info)); by = v -> v.value)
end

function MOI.get(
    model::Optimizer,
    ::MOI.NumberOfConstraints{F, S},
) where {F, S}
    n = 0
    for (_, info) in model.constraint_info
        if info.f isa F && info.set isa S
            n += 1
        end
    end
    return n
end

function MOI.get(
    model::Optimizer,
    ::MOI.ListOfConstraintIndices{F, S},
) where {F, S}
    indices = MOI.ConstraintIndex{F, S}[]
    for (ci, info) in model.constraint_info
        if info.f isa F && info.set isa S
            push!(indices, ci)
        end
    end
    return sort!(indices; by = c -> c.value)
end

function MOI.get(model::Optimizer, ::MOI.ListOfConstraintTypesPresent)
    types = Set{Tuple{Type, Type}}()
    for (_, info) in model.constraint_info
        push!(types, (typeof(info.f), typeof(info.set)))
    end
    return collect(types)
end
