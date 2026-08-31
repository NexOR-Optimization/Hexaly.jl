# Time windows over the logical sequence `[first; route; last]`.

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{<:Union{MOI.VectorOfVariables,MOI.VectorAffineFunction}},
    ::Type{<:MathOptVRP.TimeWindows},
)
    return true
end

function MOI.supports_add_constrained_variables(
    ::Optimizer,
    ::Type{<:MathOptVRP.TimeWindows},
)
    return false
end

function _time_windows_items(m::Optimizer, f, s, offset)
    items = _normalize_sum_distances_items(f)
    length(items) == MOI.dimension(s) || error(
        "MathOptVRP.TimeWindows expected $(MOI.dimension(s)) entries; got $(length(items)).",
    )
    route_end_raw = items[offset + 1]
    route_end_raw isa MOI.VariableIndex || error("route_end must be a variable.")
    sequence = items[(offset + 2):end]
    first_node = first(sequence)
    last_node = last(sequence)
    first_node isa Real && last_node isa Real || error(
        "first_node and last_node must be constant node indices.",
    )
    route = sequence[2:(end-1)]
    all(x -> x isa MOI.VariableIndex, route) || error(
        "route entries must be Partition proxy variables.",
    )
    seq = _info(m, first(route)).parent_list
    seq !== nothing || error("route entries have no parent Hexaly list.")
    all(_info(m, x).parent_list === seq for x in route) || error(
        "route entries must belong to one Hexaly list.",
    )
    return items, _expression!(m, route_end_raw), seq,
        round(Int, first_node) - 1, round(Int, last_node) - 1
end

function _time_windows_data(m::Optimizer, s)
    md = m.model
    travel = array(md, [array(md, round.(Int, s.travel[i, :]))
        for i in axes(s.travel, 1)])
    return travel, array(md, round.(Int, s.earliest)),
        array(md, round.(Int, s.latest)), array(md, round.(Int, s.service))
end

function MOI.add_constraint(
    m::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::MathOptVRP.TimeWindows{MathOptVRP.WITHOUT_START_TIME},
)
    _, route_end, seq, first_node, last_node = _time_windows_items(m, f, s, 0)
    md = m.model
    c = count_(md, seq)
    travel, earliest, latest, service = _time_windows_data(m, s)
    node_at = p -> iif(md, eq(md, p, 0), first_node,
        iif(md, eq(md, p, sum(md, c, 1)), last_node,
            at(md, seq, sub(md, p, 1))))
    end_time = array(md,
        range_(md, 0, sum(md, c, 2)),
        lambda_function(md, (p, previous_end) -> begin
            node = node_at(p)
            start = iif(md, eq(md, p, 0), at(md, earliest, node),
                max(md, at(md, earliest, node),
                    sum(md, previous_end,
                        at(md, travel, node_at(sub(md, p, 1)), node))))
            sum(md, start, at(md, service, node))
        end; nargs = 2),
        0,
    )
    _add_hexaly_constraint!(m, and_(md,
        range_(md, 0, sum(md, c, 2)),
        lambda_function(md, p -> begin
            node = node_at(p)
            leq(md, sub(md, at(md, end_time, p), at(md, service, node)),
                at(md, latest, node))
        end; nargs = 1),
    ))
    _add_hexaly_constraint!(m,
        geq(md, route_end, at(md, end_time, sum(md, c, 1))))
    return _record_time_windows!(m, f, s)
end

function MOI.add_constraint(
    m::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::MathOptVRP.TimeWindows{MathOptVRP.WITH_START_TIME},
)
    n = length(s.service)
    items, route_end, seq, first_node, last_node =
        _time_windows_items(m, f, s, n)
    all(x -> x isa MOI.VariableIndex, items[1:n]) || error(
        "start_time entries must be variables.",
    )
    md = m.model
    starts = array(md, [_expression!(m, x) for x in items[1:n]])
    c = count_(md, seq)
    travel, earliest, latest, service = _time_windows_data(m, s)

    for node = 0:(n-1)
        present = or_(md, eq(md, first_node, node), eq(md, last_node, node),
            contains_(md, seq, node))
        _add_hexaly_constraint!(m,
            or_(md, present, eq(md, at(md, starts, node), 0)))
    end
    _add_hexaly_constraint!(m, and_(md,
        range_(md, 0, c),
        lambda_function(md, p -> begin
            node = at(md, seq, p)
            ready = iif(md, eq(md, p, 0),
                sum(md, at(md, starts, first_node), at(md, service, first_node),
                    at(md, travel, first_node, node)),
                sum(md, at(md, starts, at(md, seq, sub(md, p, 1))),
                    at(md, service, at(md, seq, sub(md, p, 1))),
                    at(md, travel, at(md, seq, sub(md, p, 1)), node)))
            and_(md,
                geq(md, at(md, starts, node),
                    max(md, at(md, earliest, node), ready)),
                leq(md, at(md, starts, node), at(md, latest, node)))
        end; nargs = 1),
    ))
    _add_hexaly_constraint!(m, and_(md,
        geq(md, at(md, starts, first_node), at(md, earliest, first_node)),
        leq(md, at(md, starts, first_node), at(md, latest, first_node))))
    previous = iif(md, gt(md, c, 0), at(md, seq, sub(md, c, 1)), first_node)
    previous_start = at(md, starts, previous)
    repeated_last = or_(md, eq(md, first_node, last_node),
        contains_(md, seq, last_node))
    # A repeated final node has no second externally visible start-time slot:
    # `start_time[node]` denotes its first occurrence. Keep this occurrence
    # time internal so `route_end` remains a completion bound, not a proxy for
    # the final start time.
    repeated_start = _new_float(m, minimum(s.earliest), maximum(s.latest))
    final_start = iif(md, repeated_last,
        repeated_start,
        at(md, starts, last_node))
    _add_hexaly_constraint!(m, and_(md,
        geq(md, final_start,
            max(md, at(md, earliest, last_node),
                sum(md, previous_start, at(md, service, previous),
                    at(md, travel, previous, last_node)))),
        leq(md, final_start, at(md, latest, last_node)),
        geq(md, route_end,
            sum(md, final_start, at(md, service, last_node)))))
    return _record_time_windows!(m, f, s)
end

function _record_time_windows!(m, f, s)
    ci = MOI.ConstraintIndex{typeof(f),typeof(s)}(length(m.constraint_info) + 1)
    m.constraint_info[ci] = ConstraintInfo(ci, nothing, f, s)
    return ci
end
