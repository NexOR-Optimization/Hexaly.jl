# MathOptVRP.VehicleSchedule and MathOptVRP.SumDistances. The times of the
# schedule are derived by a recursion over each trip's list, as the earliest
# schedule given the decisions: the start of each trip, the break, and a wait
# before the service of the nodes whose start time another constraint reads
# (see `_schedule_referenced` in `copy_to.jl`).

for SetType in (MathOptVRP.VehicleSchedule, MathOptVRP.SumDistances)
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

function _route_list(m::Optimizer, route_vars, name)
    all(it -> it isa MOI.VariableIndex, route_vars) || error(
        "$name: route entries must be Partition proxy variables.",
    )
    route = _info(m, first(route_vars)).parent_list
    route !== nothing || error("$name: route variables have no parent Hexaly list.")
    all(_info(m, vi).parent_list === route for vi in route_vars) || error(
        "$name: the variables of a route must belong to the same Hexaly list.",
    )
    return route
end

_int_matrix(md, matrix) =
    array(md, [array(md, round.(Int, matrix[i, :])) for i in axes(matrix, 1)])

function MOI.add_constraint(
    m::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::MathOptVRP.SumDistances,
)
    items = _normalize_sum_distances_items(f)
    length(items) == MOI.dimension(s) || error(
        "MathOptVRP.SumDistances expected $(MOI.dimension(s)) entries; got $(length(items)).",
    )
    output = items[1]
    output isa MOI.VariableIndex || error("MathOptVRP.SumDistances: total must be a variable.")
    route = _route_list(m, items[2:end], "MathOptVRP.SumDistances")
    md = m.model
    distance = _int_matrix(md, s.distance)
    first_node, last_node = s.first - 1, s.last - 1
    c = count_(md, route)
    inner = sum(md, range_(md, 1, c), lambda_function(md,
        i -> at(md, distance, at(md, route, sub(md, i, 1)), at(md, route, i));
        nargs = 1))
    total = iif(md, gt(md, c, 0),
        sum(md,
            at(md, distance, first_node, at(md, route, 0)),
            inner,
            at(md, distance, at(md, route, sub(md, c, 1)), last_node)),
        0)
    _info(m, output).is_integer = true
    _define_expression!(m, output, total)
    return _record_definition!(m, f, s)
end

function MOI.add_constraint(
    m::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::MathOptVRP.VehicleSchedule,
)
    name = "MathOptVRP.VehicleSchedule"
    n = length(s.service)
    items = _normalize_sum_distances_items(f)
    length(items) == MOI.dimension(s) || error(
        "$name expected $(MOI.dimension(s)) entries; got $(length(items)).",
    )
    all(it -> it isa MOI.VariableIndex, items) ||
        error("$name: every entry must be a variable.")
    T = s.num_trips
    trip_start, trip_end = items[1:T], items[(T+1):(2T)]
    taken_vi, break_vi = items[2T+1], items[2T+2]
    offset = 2T + 2
    visit = items[(offset+1):(offset+n)]
    routes = [
        _route_list(m, items[(offset+n*t+1):(offset+n*(t+1))], name) for t = 1:T
    ]
    md = m.model
    depot = s.depot - 1
    travel = _int_matrix(md, s.travel)
    earliest = array(md, round.(Int, s.earliest))
    latest = array(md, round.(Int, s.latest))
    service = array(md, round.(Int, s.service))

    taken = _expression!(m, taken_vi)
    break_start = _expression!(m, break_vi)
    break_end = sum(md, break_start, round(Int, s.break_length))
    _add_hexaly_constraint!(m, or_(md, not_(md, taken), and_(md,
        geq(md, break_start, round(Int, s.break_from)),
        leq(md, break_start, round(Int, s.break_to)))))
    # The end of an activity of `duration` starting at `start`, postponed
    # after the break when it would overlap it.
    activity_end(start, duration) = sum(md,
        iif(md, and_(md, taken, lt(md, start, break_end),
                gt(md, sum(md, start, duration), break_start)),
            break_end, start),
        duration)

    waits = [
        visit[i] in m.schedule_referenced ?
        int!(md, 0, max(0, round(Int, s.latest[i] - s.earliest[i]))) : nothing
        for i = 1:n
    ]
    wait = any(!isnothing, waits) ?
        array(md, HxExpression[w === nothing ? create_constant(md, 0) : w
            for w in waits]) : nothing

    day_earliest, day_latest = round(Int, s.day_earliest), round(Int, s.day_latest)
    starts = [int!(md, day_earliest, day_latest) for _ in routes]
    ends = HxExpression[]
    visit_ends = HxExpression[]
    for (t, route) in enumerate(routes)
        c = count_(md, route)
        ready = t == 1 && !iszero(s.first_service) ?
            activity_end(starts[t], round(Int, s.first_service)) : starts[t]
        ends_t = array(md, range_(md, 0, c), lambda_function(md, (i, previous) -> begin
            node = at(md, route, i)
            from = iif(md, eq(md, i, 0), depot, at(md, route, sub(md, i, 1)))
            arrival = activity_end(iif(md, eq(md, i, 0), ready, previous),
                at(md, travel, from, node))
            start = max(md, at(md, earliest, node), arrival)
            if wait !== nothing
                start = sum(md, start, at(md, wait, node))
            end
            activity_end(start, at(md, service, node))
        end; nargs = 2), 0)
        push!(visit_ends, ends_t)
        _add_hexaly_constraint!(m, and_(md, range_(md, 0, c), lambda_function(md,
            i -> begin
                node = at(md, route, i)
                leq(md, sub(md, at(md, ends_t, i), at(md, service, node)),
                    at(md, latest, node))
            end; nargs = 1)))
        back = activity_end(at(md, ends_t, sub(md, c, 1)),
            at(md, travel, at(md, route, sub(md, c, 1)), depot))
        push!(ends, iif(md, gt(md, c, 0), back, starts[t]))
        _add_hexaly_constraint!(m, leq(md, ends[t], day_latest))
        if t > 1
            reload_terms = HxExpression[
                prod(md, round(Int, s.reload[i]), contains_(md, route, i - 1))
                for i = 1:n if !iszero(round(Int, s.reload[i]))
            ]
            if !iszero(s.reload_fixed)
                push!(reload_terms,
                    prod(md, round(Int, s.reload_fixed), gt(md, c, 0)))
            end
            reload = isempty(reload_terms) ? create_constant(md, 0) :
                sum(md, reload_terms...)
            _add_hexaly_constraint!(m,
                geq(md, starts[t], activity_end(ends[t-1], reload)))
        end
    end
    _add_hexaly_constraint!(m, or_(md, not_(md, taken), and_(md,
        geq(md, break_start, starts[1]), leq(md, break_end, ends[end]))))

    for t = 1:T
        _info(m, trip_start[t]).is_integer = true
        _info(m, trip_end[t]).is_integer = true
        _define_expression!(m, trip_start[t], starts[t])
        _define_expression!(m, trip_end[t], ends[t])
    end
    for i = 1:n
        terms = HxExpression[
            iif(md, contains_(md, route, i - 1),
                sub(md, at(md, visit_ends[t], index_of(md, route, i - 1)),
                    round(Int, s.service[i])),
                0)
            for (t, route) in enumerate(routes)
        ]
        _info(m, visit[i]).is_integer = true
        _define_expression!(m, visit[i],
            length(terms) == 1 ? terms[1] : sum(md, terms...))
    end
    return _record_definition!(m, f, s)
end

function _record_definition!(m::Optimizer, f, s)
    index = MOI.ConstraintIndex{typeof(f),typeof(s)}(length(m.constraint_info) + 1)
    m.constraint_info[index] = ConstraintInfo(index, nothing, f, s)
    return index
end
