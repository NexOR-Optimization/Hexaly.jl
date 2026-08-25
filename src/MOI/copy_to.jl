# Ordered variant of MOI.Utilities.default_copy_to. Definitions of derived
# route values must arrive after route constructors and scalar domains, but
# before constraints and objectives that consume their output variables.

_is_definition_set(::Type{<:MathOptVRP.IsEmpty}) = true
_is_definition_set(::Type{<:MathOptVRP.SumGetIndex}) = true
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

    # Variable domains first, route-value definitions second, consumers last.
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

    # Constraint attributes can only be copied after all constraint indices
    # have entered the index map.
    for (F, S) in all_types
        MOI.Utilities.pass_attributes(
            dest,
            src,
            index_map,
            MOI.get(src, MOI.ListOfConstraintIndices{F,S}()),
        )
    end

    # Unlike default_copy_to, delay model attributes (particularly the
    # objective) until expression-defining constraints have been processed.
    MOI.Utilities.pass_attributes(dest, src, index_map)
    MOI.Utilities.final_touch(dest, index_map)
    return index_map
end
