# Default domain bounds for Hexaly integer variables when none are specified.
# Hexaly requires explicit bounds for `int(lb, ub)`.
const _DEFAULT_INT_LB = -1_000_000
const _DEFAULT_INT_UB = 1_000_000
const _DEFAULT_FLOAT_LB = -1e15
const _DEFAULT_FLOAT_UB = 1e15

# Hexaly requires a time limit before solving. This is the default if the
# user hasn't set one via `MOI.TimeLimitSec` or `MOI.RawOptimizerAttribute`.
const _DEFAULT_TIME_LIMIT = 10

mutable struct VariableInfo
    index::MOI.VariableIndex
    variable::HxExpression
    # When the variable is an element of a Hexaly `list` decision variable
    # (e.g., via `MathOptVRP.List` or `MathOptVRP.Partition`), `parent_list` is that
    # list expression. `_build_sum_distances_expression` uses it to access
    # the underlying list's variable count and elements.
    parent_list::Union{Nothing,HxExpression}
    name::String
    lb::Union{Nothing,Float64}
    ub::Union{Nothing,Float64}
    is_binary::Bool
    is_integer::Bool
end

function VariableInfo(
    index::MOI.VariableIndex,
    variable::HxExpression;
    is_integer::Bool = true,
    parent_list::Union{Nothing,HxExpression} = nothing,
)
    return VariableInfo(
        index,
        variable,
        parent_list,
        "",
        nothing,
        nothing,
        false,
        is_integer,
    )
end

mutable struct ConstraintInfo
    index::MOI.ConstraintIndex
    constraint::Union{HxExpression,Nothing}
    f::Union{MOI.AbstractScalarFunction,MOI.AbstractVectorFunction}
    set::MOI.AbstractSet
    name::String
end

function ConstraintInfo(
    index::MOI.ConstraintIndex,
    constraint::Union{HxExpression,Nothing},
    f::Union{MOI.AbstractScalarFunction,MOI.AbstractVectorFunction},
    set::MOI.AbstractSet,
)
    return ConstraintInfo(index, constraint, f, set, "")
end

mutable struct Optimizer <: MOI.AbstractOptimizer
    inner::HexalyOptimizer
    model::HxModel
    variable_info::MOI.Utilities.CleverDicts.CleverDict{MOI.VariableIndex,VariableInfo}
    constraint_info::Dict{MOI.ConstraintIndex,ConstraintInfo}
    name::String
    objective_sense::MOI.OptimizationSense
    objective_function_type::Union{Nothing,DataType}
    objective_function::Union{
        Nothing,
        MOI.VariableIndex,
        MOI.ScalarAffineFunction{Float64},
        MOI.ScalarAffineFunction{Int},
        MOI.ScalarNonlinearFunction,
    }
    silent::Bool
    time_limit::Union{Nothing,Float64}
    options::Dict{String,Any}
    termination_status::MOI.TerminationStatusCode
    primal_status::MOI.ResultStatusCode
    raw_status_string::String
    solved::Bool

    function Optimizer()
        m = new()
        m.inner = raw_optimizer()
        m.model = model(m.inner)
        m.variable_info =
            MOI.Utilities.CleverDicts.CleverDict{MOI.VariableIndex,VariableInfo}()
        m.constraint_info = Dict{MOI.ConstraintIndex,ConstraintInfo}()
        m.name = ""
        m.objective_sense = MOI.FEASIBILITY_SENSE
        m.objective_function_type = nothing
        m.objective_function = nothing
        m.silent = false
        m.time_limit = nothing
        m.options = Dict{String,Any}()
        m.termination_status = MOI.OPTIMIZE_NOT_CALLED
        m.primal_status = MOI.NO_SOLUTION
        m.raw_status_string = ""
        m.solved = false
        return m
    end
end

function MOI.empty!(m::Optimizer)
    # The previous HexalyOptimizer's finalizer will release the C handle
    # when GC runs.
    m.inner = raw_optimizer()
    m.model = model(m.inner)
    empty!(m.variable_info)
    empty!(m.constraint_info)
    m.name = ""
    m.objective_sense = MOI.FEASIBILITY_SENSE
    m.objective_function_type = nothing
    m.objective_function = nothing
    m.termination_status = MOI.OPTIMIZE_NOT_CALLED
    m.primal_status = MOI.NO_SOLUTION
    m.raw_status_string = ""
    m.solved = false
    return
end

function MOI.is_empty(m::Optimizer)
    !isempty(m.name) && return false
    !isempty(m.variable_info) && return false
    !isempty(m.constraint_info) && return false
    m.objective_sense != MOI.FEASIBILITY_SENSE && return false
    m.objective_function_type !== nothing && return false
    m.objective_function !== nothing && return false
    m.solved && return false
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

MOI.get(m::Optimizer, ::MOI.Name) = m.name

function MOI.set(m::Optimizer, ::MOI.Name, name::String)
    m.name = name
    return
end

# Silent / Verbosity

MOI.supports(::Optimizer, ::MOI.Silent) = true
MOI.get(m::Optimizer, ::MOI.Silent) = m.silent
function MOI.set(m::Optimizer, ::MOI.Silent, silent::Bool)
    m.silent = silent
    return
end

# Time limit

MOI.supports(::Optimizer, ::MOI.TimeLimitSec) = true
MOI.get(m::Optimizer, ::MOI.TimeLimitSec) = m.time_limit

function MOI.set(m::Optimizer, ::MOI.TimeLimitSec, ::Nothing)
    m.time_limit = nothing
    return
end

function MOI.set(m::Optimizer, ::MOI.TimeLimitSec, value::Real)
    m.time_limit = Float64(value)
    return
end

# Raw optimizer attributes (mapped to Hexaly `param` settings)

MOI.supports(::Optimizer, ::MOI.RawOptimizerAttribute) = true

function MOI.get(m::Optimizer, attr::MOI.RawOptimizerAttribute)
    return get(m.options, attr.name, nothing)
end

function MOI.set(m::Optimizer, attr::MOI.RawOptimizerAttribute, value)
    m.options[attr.name] = value
    return
end

# Objective support

function MOI.supports(
    ::Optimizer,
    ::MOI.ObjectiveFunction{F},
) where {
    F<:Union{
        MOI.VariableIndex,
        MOI.ScalarAffineFunction{Float64},
        MOI.ScalarAffineFunction{Int},
    },
}
    return true
end

MOI.supports(::Optimizer, ::MOI.ObjectiveSense) = true

MOI.get(m::Optimizer, ::MOI.ObjectiveSense) = m.objective_sense

function MOI.set(m::Optimizer, ::MOI.ObjectiveSense, sense::MOI.OptimizationSense)
    m.objective_sense = sense
    return
end

function MOI.get(m::Optimizer, ::MOI.ObjectiveFunctionType)
    return m.objective_function_type
end

function MOI.get(m::Optimizer, ::MOI.ObjectiveFunction{F}) where {F}
    if m.objective_function_type !== F
        error("Objective function type is $(m.objective_function_type), not $F.")
    end
    return m.objective_function::F
end

function MOI.set(
    m::Optimizer,
    ::MOI.ObjectiveFunction{F},
    f::F,
) where {
    F<:Union{
        MOI.VariableIndex,
        MOI.ScalarAffineFunction{Float64},
        MOI.ScalarAffineFunction{Int},
    },
}
    m.objective_function_type = F
    m.objective_function = f
    return
end

function MOI.get(m::Optimizer, ::MOI.ListOfModelAttributesSet)
    attributes = Any[MOI.ObjectiveSense()]
    typ = m.objective_function_type
    if typ !== nothing
        push!(attributes, MOI.ObjectiveFunction{typ}())
    end
    if !isempty(m.name)
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

function _apply_params!(m::Optimizer)
    p = param(m.inner)
    tl = m.time_limit === nothing ? _DEFAULT_TIME_LIMIT :
        max(1, round(Int, m.time_limit))
    time_limit!(p, tl)
    verbosity!(p, m.silent ? 0 : 1)
    for (k, v) in m.options
        try
            set_param!(p, k, v)
        catch err
            @warn "Hexaly: could not set parameter $(k)=$(v)" error = err
        end
    end
    return
end

function _map_status(::Optimizer, status::Cint)
    if status == HX_SS_OPTIMAL
        return MOI.OPTIMAL, MOI.FEASIBLE_POINT, "OPTIMAL"
    elseif status == HX_SS_FEASIBLE
        return MOI.LOCALLY_SOLVED, MOI.FEASIBLE_POINT, "FEASIBLE"
    elseif status == HX_SS_INFEASIBLE
        return MOI.INFEASIBLE, MOI.NO_SOLUTION, "INFEASIBLE"
    elseif status == HX_SS_INCONSISTENT
        return MOI.INFEASIBLE, MOI.NO_SOLUTION, "INCONSISTENT"
    else
        return MOI.OTHER_ERROR, MOI.NO_SOLUTION, "UNKNOWN ($(Int(status)))"
    end
end

# Optimize

function MOI.optimize!(m::Optimizer)
    # Build objective (before closing the model). Hexaly requires at least
    # one objective, even for feasibility problems, so we supply a constant
    # zero objective when none is set.
    if m.objective_function !== nothing &&
       m.objective_sense != MOI.FEASIBILITY_SENSE
        obj_expr = _build_objective_expression(m)
        if m.objective_sense == MOI.MIN_SENSE
            minimize!(m.model, obj_expr)
        else
            maximize!(m.model, obj_expr)
        end
    else
        minimize!(m.model, create_constant(m.model, 0))
    end

    if !is_closed(m.model)
        close!(m.model)
    end

    _apply_params!(m)

    try
        solve!(m.inner)
    catch err
        m.termination_status = MOI.OTHER_ERROR
        m.primal_status = MOI.NO_SOLUTION
        m.raw_status_string = sprint(showerror, err)
        m.solved = true
        return
    end

    sol = solution(m.inner)
    status = solution_status(sol)
    t, p, s = _map_status(m, status)
    m.termination_status = t
    m.primal_status = p
    m.raw_status_string = s
    m.solved = true
    return
end

# Solution getters

MOI.get(m::Optimizer, ::MOI.TerminationStatus) = m.termination_status

function MOI.get(m::Optimizer, attr::MOI.PrimalStatus)
    if attr.result_index != 1
        return MOI.NO_SOLUTION
    end
    return m.primal_status
end

MOI.get(::Optimizer, ::MOI.DualStatus) = MOI.NO_SOLUTION

MOI.get(m::Optimizer, ::MOI.RawStatusString) = m.raw_status_string

function MOI.get(m::Optimizer, ::MOI.ResultCount)
    return m.primal_status == MOI.NO_SOLUTION ? 0 : 1
end

function MOI.get(m::Optimizer, attr::MOI.VariablePrimal, vi::MOI.VariableIndex)
    MOI.check_result_index_bounds(m, attr)
    info = _info(m, vi)
    return value(info.variable; is_integer = info.is_integer)
end

function MOI.get(m::Optimizer, attr::MOI.ObjectiveValue)
    MOI.check_result_index_bounds(m, attr)
    if m.objective_function === nothing ||
       m.objective_sense == MOI.FEASIBILITY_SENSE
        return 0.0
    end
    return _evaluate_objective(m)
end

function _evaluate_objective(m::Optimizer)
    f = m.objective_function
    if f isa MOI.VariableIndex
        info = _info(m, f)
        return value(info.variable; is_integer = info.is_integer)
    elseif f isa MOI.ScalarNonlinearFunction
        # Hexaly's first objective expression carries the solved value.
        # Type (int vs double) is auto-detected from the expression.
        return Float64(value(get_objective(m.model, 0)))
    else
        # ScalarAffineFunction
        T = typeof(f).parameters[1]
        val = f.constant
        for t in f.terms
            info = _info(m, t.variable)
            v = value(info.variable; is_integer = info.is_integer)
            val += t.coefficient * v
        end
        if T <: Integer
            return round(Int, val)
        end
        return val
    end
end

function MOI.get(m::Optimizer, ::MOI.SolveTimeSec)
    if !m.solved
        return 0.0
    end
    return running_time(statistics(m.inner))
end

# Number of variables / constraints (MOI bookkeeping)

MOI.get(m::Optimizer, ::MOI.NumberOfVariables) = length(m.variable_info)

function MOI.get(m::Optimizer, ::MOI.ListOfVariableIndices)
    return sort!(collect(keys(m.variable_info)); by = v -> v.value)
end

function MOI.get(m::Optimizer, ::MOI.NumberOfConstraints{F,S}) where {F,S}
    n = 0
    for (_, info) in m.constraint_info
        if info.f isa F && info.set isa S
            n += 1
        end
    end
    return n
end

function MOI.get(m::Optimizer, ::MOI.ListOfConstraintIndices{F,S}) where {F,S}
    indices = MOI.ConstraintIndex{F,S}[]
    for (ci, info) in m.constraint_info
        if info.f isa F && info.set isa S
            push!(indices, ci)
        end
    end
    return sort!(indices; by = c -> c.value)
end

function MOI.get(m::Optimizer, ::MOI.ListOfConstraintTypesPresent)
    types = Set{Tuple{Type,Type}}()
    for (_, info) in m.constraint_info
        push!(types, (typeof(info.f), typeof(info.set)))
    end
    return collect(types)
end
