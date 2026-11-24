# Ordered variant of MOI.Utilities.default_copy_to. Definitions of derived
# route values must arrive after route constructors and scalar domains, but
# before constraints and objectives that consume their output variables.

_is_definition_set(::Type{<:MathOptVRP.IsEmpty}) = true
_is_definition_set(::Type{<:MathOptVRP.SumGetIndex}) = true
_is_definition_set(::Type{<:MathOptVRP.SumDistances}) = true
_is_definition_set(::Type{<:MathOptVRP.VehicleSchedule}) = true
_is_definition_set(::Type) = false

function _copy_priority(::Type{MOI.ConstraintIndex{F,S}}) where {F,S}
    if F <: MOI.VariableIndex
        return 0
    elseif _is_definition_set(S)
        return 1
    end
    return 2
end

function _copy_priority(type_pair::Tuple{Type,Type})
    F, S = type_pair
    return _is_definition_set(S) ? 1 : 2
end

function MOI.copy_to(dest::Optimizer, src::MOI.ModelLike)
    MOI.empty!(dest)
    index_map, vis_src, constraints_not_added =
        MOI.Utilities._copy_variables_with_set(dest, src)

    MOI.Utilities.pass_attributes(dest, src, index_map, vis_src)
    _schedule_referenced!(dest, src, index_map)

    # Preserve default_copy_to's constrained-variable handling. Only reorder
    # the constraints it did not use as variable constructors.
    sort!(constraints_not_added; by = cis -> _copy_priority(eltype(cis)))
    for cis in constraints_not_added
        MOI.Utilities._copy_constraints(dest, src, index_map, cis)
    end

    all_types = MOI.get(src, MOI.ListOfConstraintTypesPresent())
    nonvariable_types = filter(all_types) do (F, _)
        return !MOI.Utilities._is_variable_function(F)
    end
    sort!(nonvariable_types; by = _copy_priority)
    for type_pair in nonvariable_types
        MOI.Utilities.pass_nonvariable_constraints(
            dest, src, index_map, [type_pair],
        )
    end

    # Match default_copy_to: constraint attributes are copied only after every
    # constructor and pending constraint has populated the index map.
    for (F, S) in all_types
        MOI.Utilities.pass_attributes(
            dest,
            src,
            index_map,
            MOI.get(src, MOI.ListOfConstraintIndices{F,S}()),
        )
    end

    # Delay model attributes (particularly the objective) until definitions
    # have been processed.
    MOI.Utilities.pass_attributes(dest, src, index_map)
    MOI.Utilities.final_touch(dest, index_map)
    return index_map
end

# The variables read by a constraint other than a definition, by a lower
# bound, or by the objective. Upper bounds and integrality hold for the
# earliest schedule whenever they hold for a later one, so they do not count.
function _schedule_referenced!(dest::Optimizer, src::MOI.ModelLike, index_map)
    referenced = dest.schedule_referenced
    empty!(referenced)
    add(f) = for vi in _variables(f)
        push!(referenced, index_map[vi])
    end
    for (F, S) in MOI.get(src, MOI.ListOfConstraintTypesPresent())
        _is_definition_set(S) && continue
        if F == MOI.VariableIndex
            S <: Union{MOI.LessThan,MOI.Integer,MOI.ZeroOne} && continue
        end
        for ci in MOI.get(src, MOI.ListOfConstraintIndices{F,S}())
            if F == MOI.VariableIndex && !_has_positive_lower(
                MOI.get(src, MOI.ConstraintSet(), ci))
                continue
            end
            add(MOI.get(src, MOI.ConstraintFunction(), ci))
        end
    end
    F = MOI.get(src, MOI.ObjectiveFunctionType())
    if F !== nothing
        add(MOI.get(src, MOI.ObjectiveFunction{F}()))
    end
    return
end

_has_positive_lower(s::MOI.GreaterThan) = s.lower > 0
_has_positive_lower(s::MOI.EqualTo) = s.value > 0
_has_positive_lower(s::MOI.Interval) = s.lower > 0
_has_positive_lower(::MOI.AbstractSet) = true

_variables(f::MOI.VariableIndex) = (f,)
_variables(f::MOI.VectorOfVariables) = f.variables
_variables(f::Union{MOI.ScalarAffineFunction,MOI.ScalarQuadraticFunction}) =
    (t.variable for t in f.terms)
_variables(f::MOI.VectorAffineFunction) = (t.scalar_term.variable for t in f.terms)
function _variables(f::MOI.ScalarNonlinearFunction)
    result = MOI.VariableIndex[]
    stack = Any[f]
    while !isempty(stack)
        arg = pop!(stack)
        if arg isa MOI.ScalarNonlinearFunction
            append!(stack, arg.args)
        elseif arg isa MOI.AbstractFunction
            append!(result, _variables(arg))
        elseif arg isa AbstractVector
            append!(stack, arg)
        end
    end
    return result
end
_variables(::Any) = ()
