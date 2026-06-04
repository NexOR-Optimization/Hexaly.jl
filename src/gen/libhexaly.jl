# Copyright (c) 2025 Benoît Legat and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

# Disable JuliaFormatter for this file.
#!format:off


const hxmmembertype = Cint

mutable struct hxoptimizer_ end

mutable struct hxarray_ end

mutable struct hxcollection_ end

mutable struct hxevaluationpoint_ end

mutable struct hxarguments_ end

mutable struct hxphase_ end

mutable struct hxattrs_ end

mutable struct hxsolution_ end

const hxoptimizer = Ptr{hxoptimizer_}

const hxcollection = Ptr{hxcollection_}

const hxarray = Ptr{hxarray_}

const hxevaluationpoint = Ptr{hxevaluationpoint_}

const hxarguments = Ptr{hxarguments_}

const hxphase = Ptr{hxphase_}

const hxattrs = Ptr{hxattrs_}

const hxsolution = Ptr{hxsolution_}

const hxsolutionstatus = Cint

const hxstate = Cint

const hxoperator = Cint

const hxobjdirection = Cint

const hxcallbacktype = Cint

const hxerrorcode = Cint

const hxdouble = Cdouble

const hxint = Clonglong

mutable struct hxmodeler_ end

mutable struct hxmref_ end

const hxmodeler = Ptr{hxmodeler_}

const hxmref = Ptr{hxmref_}

const hxmtyperef = Csize_t

const hxmtype = Cint

struct hxinterval
    start::hxint
    _end::hxint
end

@cenum hxvaluetype::UInt32 begin
    HXVT_BOOL = 1
    HXVT_INT = 2
    HXVT_DOUBLE = 4
    HXVT_ARRAY = 8
    HXVT_COLLECTION = 16
    HXVT_FUNCTION = 32
    HXVT_INTERVAL = 64
end

@cenum hxattrtype::UInt32 begin
    HXAVT_BOOL = 0
    HXAVT_INT = 1
    HXAVT_LONG_LONG = 2
    HXAVT_DOUBLE = 3
    HXAVT_STRING = 4
end

@cenum hxloggermode::Int32 begin
    HXLM_STDOUT = -1
    HXLM_TEXT = 0
    HXLM_TTY = 1
    HXLM_ANSI = 2
    HXML_ANSI_STYLING = 3
end

struct hxerror
    code::hxerrorcode
    message::Ptr{Cchar}
    filename::Ptr{Cchar}
    funcname::Ptr{Cchar}
    lineno::Cint
    exdata::Ptr{Cvoid}
end

struct hxcallbackparams
    iterationBetweenTicks::Clonglong
    timeBetweenTicks::Cint
    system::Bool
end

struct hxmdata
    data::NTuple{16, UInt8}
end

function Base.getproperty(x::Ptr{hxmdata}, f::Symbol)
    f === :ref && return Ptr{hxmref}(x + 0)
    f === :intValue && return Ptr{hxint}(x + 0)
    f === :dblValue && return Ptr{hxdouble}(x + 0)
    f === :type && return Ptr{hxmtyperef}(x + 8)
    return getfield(x, f)
end

function Base.getproperty(x::hxmdata, f::Symbol)
    r = Ref{hxmdata}(x)
    ptr = Base.unsafe_convert(Ptr{hxmdata}, r)
    fptr = getproperty(ptr, f)
    GC.@preserve r unsafe_load(fptr)
end

function Base.setproperty!(x::Ptr{hxmdata}, f::Symbol, v)
    unsafe_store!(getproperty(x, f), v)
end

function Base.propertynames(x::hxmdata, private::Bool = false)
    (:ref, :intValue, :dblValue, :type, if private
            fieldnames(typeof(x))
        else
            ()
        end...)
end

@cenum hxmstdfd::UInt32 begin
    HXMFD_STDOUT = 1
    HXMFD_STDERR = 2
end

@cenum hxmmoduleittype::UInt32 begin
    HXMODULE_IT_TYPE_ALL = 0
    HXMODULE_IT_TYPE_UNLOCKED = 1
end

@cenum hxmnativeresourcetype::UInt32 begin
    HXM_NATIVE_RES_TYPE_ALL = 0
    HXM_NATIVE_RES_TYPE_OS = 1
    HXM_NATIVE_RES_TYPE_VM = 2
end

# typedef void ( * hxexceptioncallback ) ( hxerrorcode code , const char * message , const char * filename , const char * funcname , int lineno , void * exdata , void * userData )
const hxexceptioncallback = Ptr{Cvoid}

# typedef hxint ( * hxintnativefunction ) ( hxoptimizer optimizer , hxarguments arguments , void * userData )
const hxintnativefunction = Ptr{Cvoid}

# typedef hxdouble ( * hxdoublenativefunction ) ( hxoptimizer optimizer , hxarguments arguments , void * userData )
const hxdoublenativefunction = Ptr{Cvoid}

# typedef void ( * hxarraynativefunction ) ( hxoptimizer optimizer , hxarguments arguments , hxarray result , void * userData )
const hxarraynativefunction = Ptr{Cvoid}

# typedef void ( * hxcallback ) ( hxoptimizer optimizer , hxcallbacktype type , void * userData )
const hxcallback = Ptr{Cvoid}

# typedef void ( * hxlogwriter ) ( hxoptimizer optimizer , const char * message , int length , void * userData )
const hxlogwriter = Ptr{Cvoid}

# typedef void ( * hxmodelhook ) ( int expressionId , void * userData )
const hxmodelhook = Ptr{Cvoid}

# typedef void ( * hxmwriter ) ( hxmodeler modeler , const char * content , int length , void * userData )
const hxmwriter = Ptr{Cvoid}

# typedef void ( * hxmflusher ) ( hxmodeler modeler , void * userData )
const hxmflusher = Ptr{Cvoid}

# typedef hxmdata ( * hxmfunctor ) ( hxmodeler modeler , const hxmdata * args , int nbArgs , void * userData )
const hxmfunctor = Ptr{Cvoid}

# typedef void ( * hxmfunctor2 ) ( hxmodeler modeler , const hxmdata * args , int nbArgs , hxmdata * result , void * userData )
const hxmfunctor2 = Ptr{Cvoid}

struct hxmodellistener
    expression_created::hxmodelhook
    constraint_added::hxmodelhook
    constraint_removed::hxmodelhook
    objective_added::hxmodelhook
    objective_removed::hxmodelhook
end

# no prototype is found for this function at entrypoint.h:260:31, please use with caution
function hx_create_optimizer()
    ccall((:hx_create_optimizer, libhexaly), hxoptimizer, ())
end

function hx_delete_optimizer(optimizer)
    ccall((:hx_delete_optimizer, libhexaly), Cvoid, (hxoptimizer,), optimizer)
end

function hx_state(optimizer)
    ccall((:hx_state, libhexaly), hxstate, (hxoptimizer,), optimizer)
end

function hx_solve(optimizer)
    ccall((:hx_solve, libhexaly), Cvoid, (hxoptimizer,), optimizer)
end

function hx_stop(optimizer)
    ccall((:hx_stop, libhexaly), Cvoid, (hxoptimizer,), optimizer)
end

function hx_save_environment(optimizer, filename)
    ccall((:hx_save_environment, libhexaly), Cvoid, (hxoptimizer, Ptr{Cchar}), optimizer, filename)
end

function hx_load_environment(optimizer, filename)
    ccall((:hx_load_environment, libhexaly), Cvoid, (hxoptimizer, Ptr{Cchar}), optimizer, filename)
end

function hx_stats(optimizer)
    ccall((:hx_stats, libhexaly), hxattrs, (hxoptimizer,), optimizer)
end

function hx_params(optimizer)
    ccall((:hx_params, libhexaly), hxattrs, (hxoptimizer,), optimizer)
end

function hx_best_solution(optimizer)
    ccall((:hx_best_solution, libhexaly), hxsolution, (hxoptimizer,), optimizer)
end

function hx_to_string(optimizer, str, strSize)
    ccall((:hx_to_string, libhexaly), Cint, (hxoptimizer, Ptr{Cchar}, Cint), optimizer, str, strSize)
end

function hx_compute_iis(optimizer)
    ccall((:hx_compute_iis, libhexaly), Cvoid, (hxoptimizer,), optimizer)
end

function hx_iis_cause(optimizer, causeIndex)
    ccall((:hx_iis_cause, libhexaly), Cint, (hxoptimizer, Cint), optimizer, causeIndex)
end

function hx_iis_nb_causes(optimizer)
    ccall((:hx_iis_nb_causes, libhexaly), Cint, (hxoptimizer,), optimizer)
end

function hx_iis_to_string(optimizer, str, strSize)
    ccall((:hx_iis_to_string, libhexaly), Cint, (hxoptimizer, Ptr{Cchar}, Cint), optimizer, str, strSize)
end

function hx_add_callback(optimizer, type, callback, userData)
    ccall((:hx_add_callback, libhexaly), Cvoid, (hxoptimizer, hxcallbacktype, hxcallback, Ptr{Cvoid}), optimizer, type, callback, userData)
end

function hx_add_callback_2(optimizer, type, callback, params, userdata)
    ccall((:hx_add_callback_2, libhexaly), Cvoid, (hxoptimizer, hxcallbacktype, hxcallback, Ptr{hxcallbackparams}, Ptr{Cvoid}), optimizer, type, callback, params, userdata)
end

function hx_remove_callback(optimizer, type, callback)
    ccall((:hx_remove_callback, libhexaly), Bool, (hxoptimizer, hxcallbacktype, hxcallback), optimizer, type, callback)
end

function hx_remove_callback_2(optimizer, type, callback, userData)
    ccall((:hx_remove_callback_2, libhexaly), Bool, (hxoptimizer, hxcallbacktype, hxcallback, Ptr{Cvoid}), optimizer, type, callback, userData)
end

function hx_set_log_writer(optimizer, writer, userData, mode)
    ccall((:hx_set_log_writer, libhexaly), Cvoid, (hxoptimizer, hxlogwriter, Ptr{Cvoid}, hxloggermode), optimizer, writer, userData, mode)
end

function hx_log_writer(optimizer, writer, userData, mode)
    ccall((:hx_log_writer, libhexaly), Bool, (hxoptimizer, Ptr{hxlogwriter}, Ptr{Ptr{Cvoid}}, Ptr{hxloggermode}), optimizer, writer, userData, mode)
end

function hx_add_phase(optimizer)
    ccall((:hx_add_phase, libhexaly), hxphase, (hxoptimizer,), optimizer)
end

function hx_phase(optimizer, phaseId)
    ccall((:hx_phase, libhexaly), hxphase, (hxoptimizer, Cint), optimizer, phaseId)
end

function hx_nb_phases(optimizer)
    ccall((:hx_nb_phases, libhexaly), Cint, (hxoptimizer,), optimizer)
end

function hx_phase_params(phase)
    ccall((:hx_phase_params, libhexaly), hxattrs, (hxphase,), phase)
end

function hx_phase_to_string(phase, str, strSize)
    ccall((:hx_phase_to_string, libhexaly), Cint, (hxphase, Ptr{Cchar}, Cint), phase, str, strSize)
end

function hx_attrs_is_defined(attrs, attrName)
    ccall((:hx_attrs_is_defined, libhexaly), Bool, (hxattrs, Ptr{Cchar}), attrs, attrName)
end

function hx_attrs_type(attrs, attrName)
    ccall((:hx_attrs_type, libhexaly), hxattrtype, (hxattrs, Ptr{Cchar}), attrs, attrName)
end

function hx_attrs_get_bool(attrs, attrName)
    ccall((:hx_attrs_get_bool, libhexaly), Bool, (hxattrs, Ptr{Cchar}), attrs, attrName)
end

function hx_attrs_set_bool(attrs, attrName, value)
    ccall((:hx_attrs_set_bool, libhexaly), Cvoid, (hxattrs, Ptr{Cchar}, Bool), attrs, attrName, value)
end

function hx_attrs_get_int(attrs, attrName)
    ccall((:hx_attrs_get_int, libhexaly), Cint, (hxattrs, Ptr{Cchar}), attrs, attrName)
end

function hx_attrs_set_int(attrs, attrName, value)
    ccall((:hx_attrs_set_int, libhexaly), Cvoid, (hxattrs, Ptr{Cchar}, Cint), attrs, attrName, value)
end

function hx_attrs_get_llong(attrs, attrName)
    ccall((:hx_attrs_get_llong, libhexaly), Clonglong, (hxattrs, Ptr{Cchar}), attrs, attrName)
end

function hx_attrs_set_llong(attrs, attrName, value)
    ccall((:hx_attrs_set_llong, libhexaly), Cvoid, (hxattrs, Ptr{Cchar}, Clonglong), attrs, attrName, value)
end

function hx_attrs_get_double(attrs, attrName)
    ccall((:hx_attrs_get_double, libhexaly), Cdouble, (hxattrs, Ptr{Cchar}), attrs, attrName)
end

function hx_attrs_set_double(attrs, attrName, value)
    ccall((:hx_attrs_set_double, libhexaly), Cvoid, (hxattrs, Ptr{Cchar}, Cdouble), attrs, attrName, value)
end

function hx_attrs_get_string(attrs, attrName, str, strSize)
    ccall((:hx_attrs_get_string, libhexaly), Cint, (hxattrs, Ptr{Cchar}, Ptr{Cchar}, Cint), attrs, attrName, str, strSize)
end

function hx_attrs_set_string(attrs, attrName, value)
    ccall((:hx_attrs_set_string, libhexaly), Cvoid, (hxattrs, Ptr{Cchar}, Ptr{Cchar}), attrs, attrName, value)
end

function hx_attrs_to_string(attrs, str, strSize)
    ccall((:hx_attrs_to_string, libhexaly), Cint, (hxattrs, Ptr{Cchar}, Cint), attrs, str, strSize)
end

function hx_close(optimizer)
    ccall((:hx_close, libhexaly), Cvoid, (hxoptimizer,), optimizer)
end

function hx_open(optimizer)
    ccall((:hx_open, libhexaly), Cvoid, (hxoptimizer,), optimizer)
end

function hx_is_closed(optimizer)
    ccall((:hx_is_closed, libhexaly), Bool, (hxoptimizer,), optimizer)
end

function hx_create_int_constant(optimizer, value)
    ccall((:hx_create_int_constant, libhexaly), Cint, (hxoptimizer, hxint), optimizer, value)
end

function hx_create_double_constant(optimizer, value)
    ccall((:hx_create_double_constant, libhexaly), Cint, (hxoptimizer, hxdouble), optimizer, value)
end

function hx_create_int_const_array(optimizer, values, nbValues)
    ccall((:hx_create_int_const_array, libhexaly), Cint, (hxoptimizer, Ptr{hxint}, Cint), optimizer, values, nbValues)
end

function hx_create_double_const_array(optimizer, values, nbValues)
    ccall((:hx_create_double_const_array, libhexaly), Cint, (hxoptimizer, Ptr{hxdouble}, Cint), optimizer, values, nbValues)
end

function hx_create_int_external_function(optimizer, func, userData)
    ccall((:hx_create_int_external_function, libhexaly), Cint, (hxoptimizer, hxintnativefunction, Ptr{Cvoid}), optimizer, func, userData)
end

function hx_create_double_external_function(optimizer, func, userData)
    ccall((:hx_create_double_external_function, libhexaly), Cint, (hxoptimizer, hxdoublenativefunction, Ptr{Cvoid}), optimizer, func, userData)
end

function hx_create_double_array_external_function(optimizer, func, userData)
    ccall((:hx_create_double_array_external_function, libhexaly), Cint, (hxoptimizer, hxarraynativefunction, Ptr{Cvoid}), optimizer, func, userData)
end

function hx_create_int_array_external_function(optimizer, func, userData)
    ccall((:hx_create_int_array_external_function, libhexaly), Cint, (hxoptimizer, hxarraynativefunction, Ptr{Cvoid}), optimizer, func, userData)
end

function hx_create_expression(optimizer, op)
    ccall((:hx_create_expression, libhexaly), Cint, (hxoptimizer, hxoperator), optimizer, op)
end

function hx_create_expression_1(optimizer, op, op1)
    ccall((:hx_create_expression_1, libhexaly), Cint, (hxoptimizer, hxoperator, Cint), optimizer, op, op1)
end

function hx_create_expression_2(optimizer, op, op1, op2)
    ccall((:hx_create_expression_2, libhexaly), Cint, (hxoptimizer, hxoperator, Cint, Cint), optimizer, op, op1, op2)
end

function hx_create_expression_3(optimizer, op, op1, op2, op3)
    ccall((:hx_create_expression_3, libhexaly), Cint, (hxoptimizer, hxoperator, Cint, Cint, Cint), optimizer, op, op1, op2, op3)
end

function hx_create_expression_n(optimizer, op, operands, nbOperands)
    ccall((:hx_create_expression_n, libhexaly), Cint, (hxoptimizer, hxoperator, Ptr{Cint}, Cint), optimizer, op, operands, nbOperands)
end

function hx_nb_expressions(optimizer)
    ccall((:hx_nb_expressions, libhexaly), Cint, (hxoptimizer,), optimizer)
end

function hx_nb_constraints(optimizer)
    ccall((:hx_nb_constraints, libhexaly), Cint, (hxoptimizer,), optimizer)
end

function hx_nb_objectives(optimizer)
    ccall((:hx_nb_objectives, libhexaly), Cint, (hxoptimizer,), optimizer)
end

function hx_nb_decisions(optimizer)
    ccall((:hx_nb_decisions, libhexaly), Cint, (hxoptimizer,), optimizer)
end

function hx_nb_operands(optimizer)
    ccall((:hx_nb_operands, libhexaly), Cint, (hxoptimizer,), optimizer)
end

function hx_constraint(optimizer, constraintPos)
    ccall((:hx_constraint, libhexaly), Cint, (hxoptimizer, Cint), optimizer, constraintPos)
end

function hx_add_constraint(optimizer, exprId)
    ccall((:hx_add_constraint, libhexaly), Cvoid, (hxoptimizer, Cint), optimizer, exprId)
end

function hx_remove_constraint(optimizer, constraintPos)
    ccall((:hx_remove_constraint, libhexaly), Cvoid, (hxoptimizer, Cint), optimizer, constraintPos)
end

function hx_remove_constraint_with_expr(optimizer, exprId)
    ccall((:hx_remove_constraint_with_expr, libhexaly), Cvoid, (hxoptimizer, Cint), optimizer, exprId)
end

function hx_objective(optimizer, objectivePos)
    ccall((:hx_objective, libhexaly), Cint, (hxoptimizer, Cint), optimizer, objectivePos)
end

function hx_objective_direction(optimizer, objectivePos)
    ccall((:hx_objective_direction, libhexaly), hxobjdirection, (hxoptimizer, Cint), optimizer, objectivePos)
end

function hx_add_objective(optimizer, exprId, direction)
    ccall((:hx_add_objective, libhexaly), Cvoid, (hxoptimizer, Cint, hxobjdirection), optimizer, exprId, direction)
end

function hx_remove_objective(optimizer, objectivePos)
    ccall((:hx_remove_objective, libhexaly), Cvoid, (hxoptimizer, Cint), optimizer, objectivePos)
end

function hx_decision(optimizer, decisionPos)
    ccall((:hx_decision, libhexaly), Cint, (hxoptimizer, Cint), optimizer, decisionPos)
end

function hx_expression_with_name(optimizer, name)
    ccall((:hx_expression_with_name, libhexaly), Cint, (hxoptimizer, Ptr{Cchar}), optimizer, name)
end

function hx_expr_is_objective(optimizer, exprId)
    ccall((:hx_expr_is_objective, libhexaly), Bool, (hxoptimizer, Cint), optimizer, exprId)
end

function hx_expr_is_decision(optimizer, exprId)
    ccall((:hx_expr_is_decision, libhexaly), Bool, (hxoptimizer, Cint), optimizer, exprId)
end

function hx_expr_is_constraint(optimizer, exprId)
    ccall((:hx_expr_is_constraint, libhexaly), Bool, (hxoptimizer, Cint), optimizer, exprId)
end

function hx_expr_operator(optimizer, exprId)
    ccall((:hx_expr_operator, libhexaly), hxoperator, (hxoptimizer, Cint), optimizer, exprId)
end

function hx_expr_type(optimizer, exprId)
    ccall((:hx_expr_type, libhexaly), hxvaluetype, (hxoptimizer, Cint), optimizer, exprId)
end

function hx_expr_subtype(optimizer, exprId)
    ccall((:hx_expr_subtype, libhexaly), hxvaluetype, (hxoptimizer, Cint), optimizer, exprId)
end

function hx_expr_attrs(optimizer, exprId)
    ccall((:hx_expr_attrs, libhexaly), hxattrs, (hxoptimizer, Cint), optimizer, exprId)
end

function hx_expr_nb_operands(optimizer, exprId)
    ccall((:hx_expr_nb_operands, libhexaly), Cint, (hxoptimizer, Cint), optimizer, exprId)
end

function hx_expr_operand(optimizer, exprId, operandPos)
    ccall((:hx_expr_operand, libhexaly), Cint, (hxoptimizer, Cint, Cint), optimizer, exprId, operandPos)
end

function hx_expr_set_operand(optimizer, exprId, operandPos, operandId)
    ccall((:hx_expr_set_operand, libhexaly), Cvoid, (hxoptimizer, Cint, Cint, Cint), optimizer, exprId, operandPos, operandId)
end

function hx_expr_add_operand(optimizer, exprId, operandId)
    ccall((:hx_expr_add_operand, libhexaly), Cvoid, (hxoptimizer, Cint, Cint), optimizer, exprId, operandId)
end

function hx_expr_add_operands(optimizer, exprId, operands, nbOperands)
    ccall((:hx_expr_add_operands, libhexaly), Cvoid, (hxoptimizer, Cint, Ptr{Cint}, Cint), optimizer, exprId, operands, nbOperands)
end

function hx_expr_add_int_operands(optimizer, exprId, operands, nbOperands)
    ccall((:hx_expr_add_int_operands, libhexaly), Cvoid, (hxoptimizer, Cint, Ptr{hxint}, Cint), optimizer, exprId, operands, nbOperands)
end

function hx_expr_add_double_operands(optimizer, exprId, operands, nbOperands)
    ccall((:hx_expr_add_double_operands, libhexaly), Cvoid, (hxoptimizer, Cint, Ptr{hxdouble}, Cint), optimizer, exprId, operands, nbOperands)
end

function hx_expr_reserve_operands(arg1, exprId, nbOperands)
    ccall((:hx_expr_reserve_operands, libhexaly), Cvoid, (hxoptimizer, Cint, Cint), arg1, exprId, nbOperands)
end

function hx_expr_flags(optimizer, exprId)
    ccall((:hx_expr_flags, libhexaly), Cint, (hxoptimizer, Cint), optimizer, exprId)
end

function hx_expr_set_flags(optimizer, exprId, mask, flags)
    ccall((:hx_expr_set_flags, libhexaly), Cvoid, (hxoptimizer, Cint, Cint, Cint), optimizer, exprId, mask, flags)
end

function hx_expr_name(optimizer, exprId, str, strSize)
    ccall((:hx_expr_name, libhexaly), Cint, (hxoptimizer, Cint, Ptr{Cchar}, Cint), optimizer, exprId, str, strSize)
end

function hx_expr_set_name(optimizer, exprId, name)
    ccall((:hx_expr_set_name, libhexaly), Cvoid, (hxoptimizer, Cint, Ptr{Cchar}), optimizer, exprId, name)
end

function hx_expr_to_string(optimizer, exprId, str, strSize)
    ccall((:hx_expr_to_string, libhexaly), Cint, (hxoptimizer, Cint, Ptr{Cchar}, Cint), optimizer, exprId, str, strSize)
end

function hx_model_to_string(optimizer, str, strSize)
    ccall((:hx_model_to_string, libhexaly), Cint, (hxoptimizer, Ptr{Cchar}, Cint), optimizer, str, strSize)
end

function hx_int_objective_threshold(optimizer, objectivePos)
    ccall((:hx_int_objective_threshold, libhexaly), hxint, (hxoptimizer, Cint), optimizer, objectivePos)
end

function hx_double_objective_threshold(optimizer, objectivePos)
    ccall((:hx_double_objective_threshold, libhexaly), hxdouble, (hxoptimizer, Cint), optimizer, objectivePos)
end

function hx_set_int_objective_threshold(optimizer, objectivePos, threshold)
    ccall((:hx_set_int_objective_threshold, libhexaly), Cvoid, (hxoptimizer, Cint, hxint), optimizer, objectivePos, threshold)
end

function hx_set_double_objective_threshold(optimizer, objectivePos, threshold)
    ccall((:hx_set_double_objective_threshold, libhexaly), Cvoid, (hxoptimizer, Cint, hxdouble), optimizer, objectivePos, threshold)
end

function hx_set_model_listener(optimizer, listener, userdata)
    ccall((:hx_set_model_listener, libhexaly), Cvoid, (hxoptimizer, hxmodellistener, Ptr{Cvoid}), optimizer, listener, userdata)
end

function hx_create_evaluation_point(optimizer, functionId)
    ccall((:hx_create_evaluation_point, libhexaly), hxevaluationpoint, (hxoptimizer, Cint), optimizer, functionId)
end

function hx_nb_evaluation_points(optimizer, functionId)
    ccall((:hx_nb_evaluation_points, libhexaly), Cint, (hxoptimizer, Cint), optimizer, functionId)
end

function hx_evaluation_point(optimizer, functionId, pos)
    ccall((:hx_evaluation_point, libhexaly), hxevaluationpoint, (hxoptimizer, Cint, Cint), optimizer, functionId, pos)
end

function hx_evaluation_point_return_type(point)
    ccall((:hx_evaluation_point_return_type, libhexaly), hxvaluetype, (hxevaluationpoint,), point)
end

function hx_evaluation_point_int_return_value(point)
    ccall((:hx_evaluation_point_int_return_value, libhexaly), hxint, (hxevaluationpoint,), point)
end

function hx_evaluation_point_double_return_value(point)
    ccall((:hx_evaluation_point_double_return_value, libhexaly), hxdouble, (hxevaluationpoint,), point)
end

function hx_evaluation_point_array_return_value(point)
    ccall((:hx_evaluation_point_array_return_value, libhexaly), hxarray, (hxevaluationpoint,), point)
end

function hx_evaluation_point_set_int_return_value(point, retValue)
    ccall((:hx_evaluation_point_set_int_return_value, libhexaly), Cvoid, (hxevaluationpoint, hxint), point, retValue)
end

function hx_evaluation_point_set_double_return_value(point, retValue)
    ccall((:hx_evaluation_point_set_double_return_value, libhexaly), Cvoid, (hxevaluationpoint, hxdouble), point, retValue)
end

function hx_evaluation_point_set_int_array_return_value(point, retValues, size)
    ccall((:hx_evaluation_point_set_int_array_return_value, libhexaly), Cvoid, (hxevaluationpoint, Ptr{hxint}, Cint), point, retValues, size)
end

function hx_evaluation_point_set_double_array_return_value(point, retValues, size)
    ccall((:hx_evaluation_point_set_double_array_return_value, libhexaly), Cvoid, (hxevaluationpoint, Ptr{hxdouble}, Cint), point, retValues, size)
end

function hx_evaluation_point_nb_arguments(point)
    ccall((:hx_evaluation_point_nb_arguments, libhexaly), Cint, (hxevaluationpoint,), point)
end

function hx_evaluation_point_argument_type(point, pos)
    ccall((:hx_evaluation_point_argument_type, libhexaly), hxvaluetype, (hxevaluationpoint, Cint), point, pos)
end

function hx_evaluation_point_int_argument(point, pos)
    ccall((:hx_evaluation_point_int_argument, libhexaly), hxint, (hxevaluationpoint, Cint), point, pos)
end

function hx_evaluation_point_double_argument(point, pos)
    ccall((:hx_evaluation_point_double_argument, libhexaly), hxdouble, (hxevaluationpoint, Cint), point, pos)
end

function hx_evaluation_point_set_int_argument(point, pos, value)
    ccall((:hx_evaluation_point_set_int_argument, libhexaly), Cvoid, (hxevaluationpoint, Cint, hxint), point, pos, value)
end

function hx_evaluation_point_set_double_argument(point, pos, value)
    ccall((:hx_evaluation_point_set_double_argument, libhexaly), Cvoid, (hxevaluationpoint, Cint, hxdouble), point, pos, value)
end

function hx_evaluation_point_add_int_argument(point, value)
    ccall((:hx_evaluation_point_add_int_argument, libhexaly), Cvoid, (hxevaluationpoint, hxint), point, value)
end

function hx_evaluation_point_add_double_argument(point, value)
    ccall((:hx_evaluation_point_add_double_argument, libhexaly), Cvoid, (hxevaluationpoint, hxdouble), point, value)
end

function hx_solution_status(solution)
    ccall((:hx_solution_status, libhexaly), hxsolutionstatus, (hxsolution,), solution)
end

function hx_solution_clear(solution)
    ccall((:hx_solution_clear, libhexaly), Cvoid, (hxsolution,), solution)
end

function hx_solution_is_violated(solution, exprId)
    ccall((:hx_solution_is_violated, libhexaly), Bool, (hxsolution, Cint), solution, exprId)
end

function hx_solution_is_undefined(solution, exprId)
    ccall((:hx_solution_is_undefined, libhexaly), Bool, (hxsolution, Cint), solution, exprId)
end

function hx_solution_int_objective_bound(solution, objectivePos)
    ccall((:hx_solution_int_objective_bound, libhexaly), hxint, (hxsolution, Cint), solution, objectivePos)
end

function hx_solution_double_objective_bound(solution, objectivePos)
    ccall((:hx_solution_double_objective_bound, libhexaly), hxdouble, (hxsolution, Cint), solution, objectivePos)
end

function hx_solution_objective_gap(solution, objectivePos)
    ccall((:hx_solution_objective_gap, libhexaly), hxdouble, (hxsolution, Cint), solution, objectivePos)
end

function hx_solution_int_value(solution, exprId)
    ccall((:hx_solution_int_value, libhexaly), hxint, (hxsolution, Cint), solution, exprId)
end

function hx_solution_double_value(solution, exprId)
    ccall((:hx_solution_double_value, libhexaly), hxdouble, (hxsolution, Cint), solution, exprId)
end

function hx_solution_interval_value(solution, exprId)
    ccall((:hx_solution_interval_value, libhexaly), hxinterval, (hxsolution, Cint), solution, exprId)
end

function hx_solution_collection_value(solution, exprId)
    ccall((:hx_solution_collection_value, libhexaly), hxcollection, (hxsolution, Cint), solution, exprId)
end

function hx_solution_array_value(solution, exprId)
    ccall((:hx_solution_array_value, libhexaly), hxarray, (hxsolution, Cint), solution, exprId)
end

function hx_solution_set_int_value(solution, exprId, value)
    ccall((:hx_solution_set_int_value, libhexaly), Cvoid, (hxsolution, Cint, hxint), solution, exprId, value)
end

function hx_solution_set_double_value(solution, exprId, value)
    ccall((:hx_solution_set_double_value, libhexaly), Cvoid, (hxsolution, Cint, hxdouble), solution, exprId, value)
end

function hx_solution_set_interval_value(solution, exprId, interval)
    ccall((:hx_solution_set_interval_value, libhexaly), Cvoid, (hxsolution, Cint, hxinterval), solution, exprId, interval)
end

function hx_solution_collection_clear(solution, exprId)
    ccall((:hx_solution_collection_clear, libhexaly), Cvoid, (hxsolution, Cint), solution, exprId)
end

function hx_solution_collection_add(solution, exprId, val)
    ccall((:hx_solution_collection_add, libhexaly), Cvoid, (hxsolution, Cint, hxint), solution, exprId, val)
end

function hx_solution_collection_add_all(solution, exprId, values, nbValues)
    ccall((:hx_solution_collection_add_all, libhexaly), Cvoid, (hxsolution, Cint, Ptr{hxint}, Cuint), solution, exprId, values, nbValues)
end

function hx_solution_collection_add_all_32_bits(solution, exprId, values, nbValues)
    ccall((:hx_solution_collection_add_all_32_bits, libhexaly), Cvoid, (hxsolution, Cint, Ptr{Cint}, Cuint), solution, exprId, values, nbValues)
end

function hx_interval_to_string(interval, str, strSize)
    ccall((:hx_interval_to_string, libhexaly), Cint, (hxinterval, Ptr{Cchar}, Cint), interval, str, strSize)
end

function hx_collection_count(collection)
    ccall((:hx_collection_count, libhexaly), Cint, (hxcollection,), collection)
end

function hx_collection_get(collection, pos)
    ccall((:hx_collection_get, libhexaly), hxint, (hxcollection, Cint), collection, pos)
end

function hx_collection_contains(collection, value)
    ccall((:hx_collection_contains, libhexaly), Bool, (hxcollection, hxint), collection, value)
end

function hx_collection_copy(collection, output, size)
    ccall((:hx_collection_copy, libhexaly), Cvoid, (hxcollection, Ptr{hxint}, Cint), collection, output, size)
end

function hx_collection_to_string(collection, str, strSize)
    ccall((:hx_collection_to_string, libhexaly), Cint, (hxcollection, Ptr{Cchar}, Cint), collection, str, strSize)
end

function hx_array_count(array)
    ccall((:hx_array_count, libhexaly), Cint, (hxarray,), array)
end

function hx_array_type(array)
    ccall((:hx_array_type, libhexaly), hxvaluetype, (hxarray,), array)
end

function hx_array_get_int(array, pos)
    ccall((:hx_array_get_int, libhexaly), hxint, (hxarray, Cint), array, pos)
end

function hx_array_get_double(array, pos)
    ccall((:hx_array_get_double, libhexaly), hxdouble, (hxarray, Cint), array, pos)
end

function hx_array_get_interval(array, pos)
    ccall((:hx_array_get_interval, libhexaly), hxinterval, (hxarray, Cint), array, pos)
end

function hx_array_get_array(array, pos)
    ccall((:hx_array_get_array, libhexaly), hxarray, (hxarray, Cint), array, pos)
end

function hx_array_get_collection(array, pos)
    ccall((:hx_array_get_collection, libhexaly), hxcollection, (hxarray, Cint), array, pos)
end

function hx_array_is_undefined(array, pos)
    ccall((:hx_array_is_undefined, libhexaly), Bool, (hxarray, Cint), array, pos)
end

function hx_array_copy_int(array, output, size)
    ccall((:hx_array_copy_int, libhexaly), Cvoid, (hxarray, Ptr{hxint}, Cint), array, output, size)
end

function hx_array_copy_double(array, output, size)
    ccall((:hx_array_copy_double, libhexaly), Cvoid, (hxarray, Ptr{hxdouble}, Cint), array, output, size)
end

function hx_array_add_int(array, value)
    ccall((:hx_array_add_int, libhexaly), Cvoid, (hxarray, hxint), array, value)
end

function hx_array_add_double(array, value)
    ccall((:hx_array_add_double, libhexaly), Cvoid, (hxarray, hxdouble), array, value)
end

function hx_array_add_interval(array, value)
    ccall((:hx_array_add_interval, libhexaly), Cvoid, (hxarray, hxinterval), array, value)
end

function hx_array_set_int(array, pos, value)
    ccall((:hx_array_set_int, libhexaly), Cvoid, (hxarray, Cint, hxint), array, pos, value)
end

function hx_array_set_double(array, pos, value)
    ccall((:hx_array_set_double, libhexaly), Cvoid, (hxarray, Cint, hxdouble), array, pos, value)
end

function hx_array_set_interval(array, pos, interval)
    ccall((:hx_array_set_interval, libhexaly), Cvoid, (hxarray, Cint, hxinterval), array, pos, interval)
end

function hx_array_clear(array)
    ccall((:hx_array_clear, libhexaly), Cvoid, (hxarray,), array)
end

function hx_array_to_string(array, str, strSize)
    ccall((:hx_array_to_string, libhexaly), Cint, (hxarray, Ptr{Cchar}, Cint), array, str, strSize)
end

function hx_arguments_count(arguments)
    ccall((:hx_arguments_count, libhexaly), Cint, (hxarguments,), arguments)
end

function hx_arguments_type(arguments, pos)
    ccall((:hx_arguments_type, libhexaly), hxvaluetype, (hxarguments, Cint), arguments, pos)
end

function hx_arguments_is_undefined(arguments, pos)
    ccall((:hx_arguments_is_undefined, libhexaly), Bool, (hxarguments, Cint), arguments, pos)
end

function hx_arguments_get_int(arguments, pos)
    ccall((:hx_arguments_get_int, libhexaly), hxint, (hxarguments, Cint), arguments, pos)
end

function hx_arguments_get_double(arguments, pos)
    ccall((:hx_arguments_get_double, libhexaly), hxdouble, (hxarguments, Cint), arguments, pos)
end

function hx_arguments_get_interval(arguments, pos)
    ccall((:hx_arguments_get_interval, libhexaly), hxinterval, (hxarguments, Cint), arguments, pos)
end

function hx_arguments_get_array(arguments, pos)
    ccall((:hx_arguments_get_array, libhexaly), hxarray, (hxarguments, Cint), arguments, pos)
end

function hx_arguments_get_collection(arguments, pos)
    ccall((:hx_arguments_get_collection, libhexaly), hxcollection, (hxarguments, Cint), arguments, pos)
end

# no prototype is found for this function at entrypoint.h:451:23, please use with caution
function hx_version_code()
    ccall((:hx_version_code, libhexaly), Cint, ())
end

# no prototype is found for this function at entrypoint.h:452:27, please use with caution
function hx_globals()
    ccall((:hx_globals, libhexaly), hxattrs, ())
end

function hx_check_modeling(optimizer)
    ccall((:hx_check_modeling, libhexaly), Bool, (hxoptimizer,), optimizer)
end

function hx_check_paused_or_stopped(optimizer)
    ccall((:hx_check_paused_or_stopped, libhexaly), Bool, (hxoptimizer,), optimizer)
end

function hx_check_modeling_or_stopped(optimizer)
    ccall((:hx_check_modeling_or_stopped, libhexaly), Bool, (hxoptimizer,), optimizer)
end

function hx_check_not_running(optimizer)
    ccall((:hx_check_not_running, libhexaly), Bool, (hxoptimizer,), optimizer)
end

function hx_check_stopped(optimizer)
    ccall((:hx_check_stopped, libhexaly), Bool, (hxoptimizer,), optimizer)
end

function hx_check_expr_index(optimizer, exprId)
    ccall((:hx_check_expr_index, libhexaly), Bool, (hxoptimizer, Cint), optimizer, exprId)
end

function hx_check_expr_type(optimizer, exprId, expectedTypes)
    ccall((:hx_check_expr_type, libhexaly), Bool, (hxoptimizer, Cint, hxvaluetype), optimizer, exprId, expectedTypes)
end

function hx_check_expr_subtype(optimizer, exprId, expectedTypes)
    ccall((:hx_check_expr_subtype, libhexaly), Bool, (hxoptimizer, Cint, hxvaluetype), optimizer, exprId, expectedTypes)
end

function hx_check_operator(optimizer, exprId, expectedOperator)
    ccall((:hx_check_operator, libhexaly), Bool, (hxoptimizer, Cint, hxoperator), optimizer, exprId, expectedOperator)
end

# no prototype is found for this function at entrypoint.h:470:29, please use with caution
function hxm_create_modeler()
    ccall((:hxm_create_modeler, libhexaly), hxmodeler, ())
end

function hxm_delete_modeler(modeler)
    ccall((:hxm_delete_modeler, libhexaly), Cvoid, (hxmodeler,), modeler)
end

function hxm_optimizer(modeler)
    ccall((:hxm_optimizer, libhexaly), hxoptimizer, (hxmodeler,), modeler)
end

function hxm_set_std_stream(modeler, fd, writer, flusher, userData)
    ccall((:hxm_set_std_stream, libhexaly), Cvoid, (hxmodeler, hxmstdfd, hxmwriter, hxmflusher, Ptr{Cvoid}), modeler, fd, writer, flusher, userData)
end

function hxm_create_module(modeler, name)
    ccall((:hxm_create_module, libhexaly), hxmdata, (hxmodeler, Ptr{Cchar}), modeler, name)
end

function hxm_load_module_from_file(modeler, name, filepath)
    ccall((:hxm_load_module_from_file, libhexaly), hxmdata, (hxmodeler, Ptr{Cchar}, Ptr{Cchar}), modeler, name, filepath)
end

function hxm_get_module(modeler, name)
    ccall((:hxm_get_module, libhexaly), hxmdata, (hxmodeler, Ptr{Cchar}), modeler, name)
end

function hxm_add_module_lookup_path(modeler, path)
    ccall((:hxm_add_module_lookup_path, libhexaly), Cvoid, (hxmodeler, Ptr{Cchar}), modeler, path)
end

function hxm_clear_module_lookup_paths(modeler)
    ccall((:hxm_clear_module_lookup_paths, libhexaly), Cvoid, (hxmodeler,), modeler)
end

function hxm_module_get(_module, varName)
    ccall((:hxm_module_get, libhexaly), hxmdata, (hxmref, Ptr{Cchar}), _module, varName)
end

function hxm_module_set(_module, varName, data)
    ccall((:hxm_module_set, libhexaly), Cvoid, (hxmref, Ptr{Cchar}, hxmdata), _module, varName, data)
end

function hxm_module_run(_module, optimizer, cmdLine, strSize)
    ccall((:hxm_module_run, libhexaly), Cvoid, (hxmref, hxmref, Ptr{Cchar}, Cint), _module, optimizer, cmdLine, strSize)
end

function hxm_module_run_main(_module, cmdLine, strSize)
    ccall((:hxm_module_run_main, libhexaly), Cvoid, (hxmref, Ptr{Cchar}, Cint), _module, cmdLine, strSize)
end

function hxm_module_create_iterator(_module, type)
    ccall((:hxm_module_create_iterator, libhexaly), hxmdata, (hxmref, hxmmoduleittype), _module, type)
end

function hxm_module_name(_module, str, strSize)
    ccall((:hxm_module_name, libhexaly), Cint, (hxmref, Ptr{Cchar}, Cint), _module, str, strSize)
end

function hxm_eval(_module, input)
    ccall((:hxm_eval, libhexaly), hxmdata, (hxmref, Ptr{Cchar}), _module, input)
end

function hxm_create_map(modeler)
    ccall((:hxm_create_map, libhexaly), hxmdata, (hxmodeler,), modeler)
end

function hxm_map_is_defined(map, key)
    ccall((:hxm_map_is_defined, libhexaly), Bool, (hxmref, hxmdata), map, key)
end

function hxm_map_get(map, key)
    ccall((:hxm_map_get, libhexaly), hxmdata, (hxmref, hxmdata), map, key)
end

function hxm_map_set(map, key, value)
    ccall((:hxm_map_set, libhexaly), Cvoid, (hxmref, hxmdata, hxmdata), map, key, value)
end

function hxm_map_add(map, value)
    ccall((:hxm_map_add, libhexaly), Cvoid, (hxmref, hxmdata), map, value)
end

function hxm_map_clear(map)
    ccall((:hxm_map_clear, libhexaly), Cvoid, (hxmref,), map)
end

function hxm_map_count(map)
    ccall((:hxm_map_count, libhexaly), hxint, (hxmref,), map)
end

function hxm_create_optimizer(modeler)
    ccall((:hxm_create_optimizer, libhexaly), hxmdata, (hxmodeler,), modeler)
end

function hxm_optimizer_handle(optimizer)
    ccall((:hxm_optimizer_handle, libhexaly), hxmdata, (hxmref,), optimizer)
end

function hxm_optimizer_reset(optimizer)
    ccall((:hxm_optimizer_reset, libhexaly), Cvoid, (hxmref,), optimizer)
end

function hxm_create_expr(handle, exprId)
    ccall((:hxm_create_expr, libhexaly), hxmdata, (hxmref, Cint), handle, exprId)
end

function hxm_expr_handle(expr)
    ccall((:hxm_expr_handle, libhexaly), hxmdata, (hxmref,), expr)
end

function hxm_expr_index(expr)
    ccall((:hxm_expr_index, libhexaly), Cint, (hxmref,), expr)
end

function hxm_handle_optimizer(optimizer)
    ccall((:hxm_handle_optimizer, libhexaly), hxoptimizer, (hxmref,), optimizer)
end

function hxm_create_string(modeler, str)
    ccall((:hxm_create_string, libhexaly), hxmdata, (hxmodeler, Ptr{Cchar}), modeler, str)
end

function hxm_create_string_2(modeler, str, strSize)
    ccall((:hxm_create_string_2, libhexaly), hxmdata, (hxmodeler, Ptr{Cchar}, Cint), modeler, str, strSize)
end

function hxm_string(str, dest, destSize)
    ccall((:hxm_string, libhexaly), Cint, (hxmref, Ptr{Cchar}, Cint), str, dest, destSize)
end

function hxm_string_c_str(str)
    ccall((:hxm_string_c_str, libhexaly), Ptr{Cchar}, (hxmref,), str)
end

function hxm_create_function(modeler, funcName, functor, userData)
    ccall((:hxm_create_function, libhexaly), hxmdata, (hxmodeler, Ptr{Cchar}, hxmfunctor, Ptr{Cvoid}), modeler, funcName, functor, userData)
end

function hxm_create_function_2(modeler, funcName, functor, userData)
    ccall((:hxm_create_function_2, libhexaly), hxmdata, (hxmodeler, Ptr{Cchar}, hxmfunctor2, Ptr{Cvoid}), modeler, funcName, functor, userData)
end

function hxm_function_call(_function, args, nbArgs)
    ccall((:hxm_function_call, libhexaly), hxmdata, (hxmref, Ptr{hxmdata}, Cint), _function, args, nbArgs)
end

function hxm_function_name(_function, str, strSize)
    ccall((:hxm_function_name, libhexaly), Cint, (hxmref, Ptr{Cchar}, Cint), _function, str, strSize)
end

function hxm_get_class(value)
    ccall((:hxm_get_class, libhexaly), hxmdata, (hxmdata,), value)
end

function hxm_class_name(clazz, str, strSize)
    ccall((:hxm_class_name, libhexaly), Cint, (hxmref, Ptr{Cchar}, Cint), clazz, str, strSize)
end

function hxm_class_is_final(clazz)
    ccall((:hxm_class_is_final, libhexaly), Bool, (hxmref,), clazz)
end

function hxm_class_has_super_class(clazz)
    ccall((:hxm_class_has_super_class, libhexaly), Bool, (hxmref,), clazz)
end

function hxm_class_super_class(clazz)
    ccall((:hxm_class_super_class, libhexaly), hxmdata, (hxmref,), clazz)
end

function hxm_class_is_subclass_of(clazz, parent)
    ccall((:hxm_class_is_subclass_of, libhexaly), Bool, (hxmref, hxmref), clazz, parent)
end

function hxm_class_is_instance_of(clazz, value)
    ccall((:hxm_class_is_instance_of, libhexaly), Bool, (hxmref, hxmdata), clazz, value)
end

function hxm_class_new_instance(clazz, args, nbArgs)
    ccall((:hxm_class_new_instance, libhexaly), hxmdata, (hxmref, Ptr{hxmdata}, Cint), clazz, args, nbArgs)
end

function hxm_class_nb_members(clazz)
    ccall((:hxm_class_nb_members, libhexaly), Cint, (hxmref,), clazz)
end

function hxm_class_member_type(clazz, memberId)
    ccall((:hxm_class_member_type, libhexaly), hxmmembertype, (hxmref, Cint), clazz, memberId)
end

function hxm_class_member_name(clazz, memberId, dest, destSize)
    ccall((:hxm_class_member_name, libhexaly), Cint, (hxmref, Cint, Ptr{Cchar}, Cint), clazz, memberId, dest, destSize)
end

function hxm_class_find_member(clazz, memberName)
    ccall((:hxm_class_find_member, libhexaly), Cint, (hxmref, Ptr{Cchar}), clazz, memberName)
end

function hxm_class_member_id(clazz, memberName)
    ccall((:hxm_class_member_id, libhexaly), Cint, (hxmref, Ptr{Cchar}), clazz, memberName)
end

function hxm_class_member_method(clazz, memberId)
    ccall((:hxm_class_member_method, libhexaly), hxmdata, (hxmref, Cint), clazz, memberId)
end

function hxm_class_member_slot(clazz, memberId)
    ccall((:hxm_class_member_slot, libhexaly), Cint, (hxmref, Cint), clazz, memberId)
end

function hxm_check_class_property(clazz, memberId)
    ccall((:hxm_check_class_property, libhexaly), Cvoid, (hxmref, Cint), clazz, memberId)
end

function hxm_class_member_get_property(clazz, memberId, obj)
    ccall((:hxm_class_member_get_property, libhexaly), hxmdata, (hxmref, Cint, hxmref), clazz, memberId, obj)
end

function hxm_class_member_set_property(clazz, memberId, obj, value)
    ccall((:hxm_class_member_set_property, libhexaly), Cvoid, (hxmref, Cint, hxmref, hxmdata), clazz, memberId, obj, value)
end

function hxm_class_member_is_readonly_property(clazz, memberId)
    ccall((:hxm_class_member_is_readonly_property, libhexaly), Bool, (hxmref, Cint), clazz, memberId)
end

function hxm_class_nb_static_members(clazz)
    ccall((:hxm_class_nb_static_members, libhexaly), Cint, (hxmref,), clazz)
end

function hxm_class_static_member_name(clazz, staticMemberId, dest, destSize)
    ccall((:hxm_class_static_member_name, libhexaly), Cint, (hxmref, Cint, Ptr{Cchar}, Cint), clazz, staticMemberId, dest, destSize)
end

function hxm_class_find_static_member(clazz, staticMemberName)
    ccall((:hxm_class_find_static_member, libhexaly), Cint, (hxmref, Ptr{Cchar}), clazz, staticMemberName)
end

function hxm_class_static_member_id(clazz, staticMemberName)
    ccall((:hxm_class_static_member_id, libhexaly), Cint, (hxmref, Ptr{Cchar}), clazz, staticMemberName)
end

function hxm_class_get_static_member(clazz, staticMemberId)
    ccall((:hxm_class_get_static_member, libhexaly), hxmdata, (hxmref, Cint), clazz, staticMemberId)
end

function hxm_class_set_static_member(clazz, staticMemberId, value)
    ccall((:hxm_class_set_static_member, libhexaly), Cvoid, (hxmref, Cint, hxmdata), clazz, staticMemberId, value)
end

function hxm_check_class_instance(clazz, value)
    ccall((:hxm_check_class_instance, libhexaly), Cvoid, (hxmref, hxmdata), clazz, value)
end

function hxm_inc_ref(ref)
    ccall((:hxm_inc_ref, libhexaly), Cvoid, (hxmref,), ref)
end

function hxm_dec_ref(ref)
    ccall((:hxm_dec_ref, libhexaly), Cvoid, (hxmref,), ref)
end

function hxm_ref_get_slot(ref, slotId)
    ccall((:hxm_ref_get_slot, libhexaly), hxmdata, (hxmref, Cint), ref, slotId)
end

function hxm_ref_set_slot(ref, slotId, value)
    ccall((:hxm_ref_set_slot, libhexaly), Cvoid, (hxmref, Cint, hxmdata), ref, slotId, value)
end

function hxm_type(type)
    ccall((:hxm_type, libhexaly), hxmtype, (hxmtyperef,), type)
end

function hxm_check_type(typeRef, expectedType)
    ccall((:hxm_check_type, libhexaly), Bool, (hxmtyperef, hxmtype), typeRef, expectedType)
end

function hxm_ref_modeler(ref)
    ccall((:hxm_ref_modeler, libhexaly), hxmodeler, (hxmref,), ref)
end

function hxm_close_native_resources(modeler, type)
    ccall((:hxm_close_native_resources, libhexaly), Cvoid, (hxmodeler, hxmnativeresourcetype), modeler, type)
end

function hxm_create_iterator(iterable)
    ccall((:hxm_create_iterator, libhexaly), hxmdata, (hxmref,), iterable)
end

function hxm_iterator_next(iterator, key, value)
    ccall((:hxm_iterator_next, libhexaly), Bool, (hxmref, Ptr{hxmdata}, Ptr{hxmdata}), iterator, key, value)
end

function hx_check_last_error(error)
    ccall((:hx_check_last_error, libhexaly), Bool, (Ptr{hxerror},), error)
end

function hx_set_exception_callback(callback, userData)
    ccall((:hx_set_exception_callback, libhexaly), Cvoid, (hxexceptioncallback, Ptr{Cvoid}), callback, userData)
end

function hx_interrupt(reason, exdata)
    ccall((:hx_interrupt, libhexaly), Cvoid, (Ptr{Cchar}, Ptr{Cvoid}), reason, exdata)
end

