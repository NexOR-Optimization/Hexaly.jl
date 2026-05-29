# `Hexaly.List` — a vector set backed by a Hexaly `model.list(n)` decision
# variable. The n MOI variables exposed by the set are the elements of the
# list; their values are a permutation of `0:n-1`.

struct List <: MOI.AbstractVectorSet
    dimension::Int
end

MOI.dimension(s::List) = s.dimension

function MOI.supports_add_constrained_variables(::Optimizer, ::Type{List})
    return true
end

function MOI.add_constrained_variables(model::Optimizer, set::List)
    n = set.dimension
    hx_list = model.model.list(Py(n))
    # `Hexaly.List(n)` semantically means "a permutation of `0:n-1`" — a
    # bare `model.list(n)` only requires distinctness, with the length free
    # between 0 and n. Force the length so the optimizer can't pick a
    # shorter list (which is optimal under `sum_distances` since shorter
    # closed tours have lower cost).
    model.model.constraint(model.model.count(hx_list) == Py(n))
    indices = _add_list_variables!(model, hx_list, n)
    cindex =
        MOI.ConstraintIndex{MOI.VectorOfVariables,List}(length(model.constraint_info) + 1)
    model.constraint_info[cindex] =
        ConstraintInfo(cindex, hx_list, MOI.VectorOfVariables(indices), set)
    return indices, cindex
end

# Create `n` MOI variables backed by `hx_list[0..n-1]`, each tagged with
# `parent_list = hx_list` so the objective handler can recover the list.
function _add_list_variables!(model::Optimizer, hx_list::Py, n::Int)
    indices = MOI.VariableIndex[]
    for i = 0:(n-1)
        elem = hx_list[Py(i)]
        info = VariableInfo(
            MOI.VariableIndex(0),
            elem;
            is_integer = true,
            parent_list = hx_list,
        )
        info.lb = 0.0
        info.ub = Float64(n - 1)
        idx = MOI.Utilities.CleverDicts.add_item(model.variable_info, info)
        _info(model, idx).index = idx
        push!(indices, idx)
    end
    return indices
end

# `Hexaly.Partition` — `num_trucks` lists of size `num_clients`, with a
# `model.partition` constraint forcing each value in `0:num_clients-1` to
# appear in exactly one truck's list. The flat MOI representation lays out
# variables column-major: nodes[1..num_clients, 1], nodes[1..num_clients, 2], …

struct Partition <: MOI.AbstractVectorSet
    num_clients::Int
    num_trucks::Int
end

MOI.dimension(s::Partition) = s.num_clients * s.num_trucks

function MOI.supports_add_constrained_variables(::Optimizer, ::Type{Partition})
    return true
end

# JuMP needs an explicit `build_variable` for the 2D-matrix-in-vector-set form
# `@variable(model, x[1:nc, 1:nt] in Partition(nc, nt))`.
function JuMP.build_variable(
    error_fn::Function,
    variables::Matrix{<:JuMP.AbstractVariable},
    set::Partition,
)
    size(variables) == (set.num_clients, set.num_trucks) || error_fn(
        "Hexaly.Partition: expected a `$(set.num_clients) × $(set.num_trucks)` ",
        "variable matrix, got `$(size(variables))`.",
    )
    return JuMP.VariablesConstrainedOnCreation(
        vec(variables),
        set,
        JuMP.ArrayShape(size(variables)),
    )
end

function MOI.add_constrained_variables(model::Optimizer, set::Partition)
    m = model.model
    lists = Py[m.list(Py(set.num_clients)) for _ = 1:(set.num_trucks)]
    m.constraint(m.partition(pylist(lists)))
    indices = MOI.VariableIndex[]
    for hx_list in lists
        col_indices = _add_list_variables!(model, hx_list, set.num_clients)
        append!(indices, col_indices)
    end
    cindex = MOI.ConstraintIndex{MOI.VectorOfVariables,Partition}(
        length(model.constraint_info) + 1,
    )
    model.constraint_info[cindex] =
        ConstraintInfo(cindex, nothing, MOI.VectorOfVariables(indices), set)
    return indices, cindex
end

# `Hexaly.PartitionPD` — `num_trucks` lists of size `n_total = num_services +
# 2 * num_pickup_deliveries`, with a `model.partition` plus, for each
# pickup/delivery pair `(p, d)`, two constraints per truck:
#   - `contains(seq, p) == contains(seq, d)` (same truck holds both, or neither)
#   - `index(seq, p) <= index(seq, d)`        (pickup precedes delivery)
#
# Indices follow the user-facing convention on the JuMP matrix `x[i, t]`:
#   - `1 <= i <= num_services`                          → service
#   - `num_services <  i <= num_services + num_pd`      → pickup k = i - num_services
#   - `num_services + num_pd <  i <= n_total`           → delivery for pickup
#                                                         k = i - num_services - num_pd
# In Hexaly's 0-indexed list values this means service `0..num_services-1`,
# pickup `num_services..num_services+num_pd-1`, delivery
# `num_services+num_pd..n_total-1`, with pickup `k` paired to delivery
# `num_services+num_pd+k` for `k = 0..num_pd-1`.

struct PartitionPD <: MOI.AbstractVectorSet
    num_services::Int
    num_pickup_deliveries::Int
    num_trucks::Int
end

_pd_n_total(s::PartitionPD) = s.num_services + 2 * s.num_pickup_deliveries

MOI.dimension(s::PartitionPD) = _pd_n_total(s) * s.num_trucks

function MOI.supports_add_constrained_variables(::Optimizer, ::Type{PartitionPD})
    return true
end

function JuMP.build_variable(
    error_fn::Function,
    variables::Matrix{<:JuMP.AbstractVariable},
    set::PartitionPD,
)
    n_total = _pd_n_total(set)
    size(variables) == (n_total, set.num_trucks) || error_fn(
        "Hexaly.PartitionPD: expected a `$n_total × $(set.num_trucks)` ",
        "variable matrix, got `$(size(variables))`.",
    )
    return JuMP.VariablesConstrainedOnCreation(
        vec(variables),
        set,
        JuMP.ArrayShape(size(variables)),
    )
end

function MOI.add_constrained_variables(model::Optimizer, set::PartitionPD)
    m = model.model
    n_total = _pd_n_total(set)
    lists = Py[m.list(Py(n_total)) for _ = 1:(set.num_trucks)]
    m.constraint(m.partition(pylist(lists)))
    for k = 0:(set.num_pickup_deliveries-1)
        p = set.num_services + k
        d = set.num_services + set.num_pickup_deliveries + k
        for seq in lists
            m.constraint(m.contains(seq, Py(p)) == m.contains(seq, Py(d)))
            m.constraint(m.index(seq, Py(p)) <= m.index(seq, Py(d)))
        end
    end
    indices = MOI.VariableIndex[]
    for hx_list in lists
        col_indices = _add_list_variables!(model, hx_list, n_total)
        append!(indices, col_indices)
    end
    cindex = MOI.ConstraintIndex{MOI.VectorOfVariables,PartitionPD}(
        length(model.constraint_info) + 1,
    )
    model.constraint_info[cindex] =
        ConstraintInfo(cindex, nothing, MOI.VectorOfVariables(indices), set)
    return indices, cindex
end

# `Hexaly.TimeWindows(travel, earliest, latest, service)` — a vector
# constraint on `[t; depot_start; nodes; depot_end]` where:
#   - `t` is the truck's total-time decision variable;
#   - `depot_start` / `depot_end` are constant Hexaly indices (typically the
#     same depot, but the API allows different start/end depots);
#   - `nodes` is a column of variables backed by the same Hexaly list (a
#     column of a `Partition` / `PartitionPD`).
# The constraint enforces, for every customer `i` actually visited by the
# truck:
#
#   end_time[0]  = max(earliest[seq[0]], travel[depot_start, seq[0]]) + service
#   end_time[i]  = max(earliest[seq[i]], end_time[i-1] + travel[seq[i-1], seq[i]]) + service
#   for all i: end_time[i] - service <= latest[seq[i]]
#
# plus the makespan
#
#   total_time = (c > 0) ? end_time[c-1] + travel[seq[c-1], depot_end] : 0
#   t >= total_time
#
# so that `@objective(model, Min, sum(t))` minimises the total trucking time
# (travel + waiting + service + return to depot), not just the distance.

struct TimeWindows{T<:Real} <: MOI.AbstractVectorSet
    travel::Matrix{T}
    earliest::Vector{T}
    latest::Vector{T}
    service::T
end

MOI.dimension(s::TimeWindows) = length(s.earliest) + 3

# `TimeWindows` is logically immutable after construction (the travel
# matrix and the earliest/latest vectors are read-only data we copy into
# Hexaly arrays at constraint posting time), so a shallow copy is safe
# and lets MOI's `CachingOptimizer` store the set in its internal model.
Base.copy(s::TimeWindows) = s

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{<:Union{MOI.VectorOfVariables,MOI.VectorAffineFunction}},
    ::Type{<:TimeWindows},
)
    return true
end

function MOI.add_constraint(
    model::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::TimeWindows,
)
    items = _normalize_sum_distances_items(f)
    length(items) == MOI.dimension(s) || error(
        "Hexaly.TimeWindows expected `length([t; depot_start; nodes; depot_end]) == ",
        "$(MOI.dimension(s))`; got $(length(items)).",
    )
    items[1] isa MOI.VariableIndex || error(
        "Hexaly.TimeWindows: first item must be the total-time `t` variable.",
    )
    items[2] isa Real || error(
        "Hexaly.TimeWindows: second item must be the constant `depot_start` index.",
    )
    items[end] isa Real || error(
        "Hexaly.TimeWindows: last item must be the constant `depot_end` index.",
    )
    t_vi = items[1]
    depot_start = round(Int, items[2])
    depot_end = round(Int, items[end])
    var_items = @view items[3:(end-1)]
    all(it -> it isa MOI.VariableIndex, var_items) || error(
        "Hexaly.TimeWindows: items 3..end-1 must be node `MOI.VariableIndex` values ",
        "backed by a Hexaly list (a column of a `Hexaly.Partition` / `Hexaly.PartitionPD`).",
    )
    first_pl = _info(model, var_items[1]).parent_list
    first_pl !== nothing || error(
        "Hexaly.TimeWindows: node variables have no parent Hexaly list.",
    )
    all(_info(model, vi).parent_list === first_pl for vi in var_items) || error(
        "Hexaly.TimeWindows: all node variables must belong to the same Hexaly list.",
    )

    m = model.model
    t_var = _info(model, t_vi).variable
    seq = first_pl
    c = m.count(seq)
    service = round(Int, s.service)
    n_rows = size(s.travel, 1)
    dist_arr =
        m.array(pylist([pylist(round.(Int, s.travel[i, :])) for i = 1:n_rows]))
    earliest_arr = m.array(pylist(round.(Int, s.earliest)))
    latest_arr = m.array(pylist(round.(Int, s.latest)))

    end_time = m.array(
        m.range(0, c),
        m.lambda_function(
            pyfunc(
                (i, prev) -> m.iif(
                    i == 0,
                    m.max(
                        m.at(earliest_arr, seq[0]),
                        m.at(dist_arr, Py(depot_start), seq[0]),
                    ) + Py(service),
                    m.max(
                        m.at(earliest_arr, seq[i]),
                        prev + m.at(dist_arr, seq[i-1], seq[i]),
                    ) + Py(service),
                );
                wrap = "lambda f: lambda i, prev: f(i, prev)",
            ),
        ),
        Py(0),
    )

    m.constraint(
        m.and_(
            m.range(0, c),
            m.lambda_function(
                pyfunc(
                    i -> end_time[i] - Py(service) <= m.at(latest_arr, seq[i]);
                    wrap = "lambda f: lambda i: f(i)",
                ),
            ),
        ),
    )

    # Makespan: t >= end_time[c-1] + travel[seq[c-1], depot_end] (or 0 if
    # the truck stays at the depot).
    total_time = m.iif(
        c > 0,
        end_time[c-1] + m.at(dist_arr, seq[c-1], Py(depot_end)),
        Py(0),
    )
    m.constraint(t_var >= total_time)

    cindex = MOI.ConstraintIndex{typeof(f),typeof(s)}(
        length(model.constraint_info) + 1,
    )
    model.constraint_info[cindex] = ConstraintInfo(cindex, nothing, f, s)
    return cindex
end

<<<<<<< HEAD
# `Hexaly.Capacity(delta, capacity)` — a vector constraint on the column of
# variables for one truck (no depot prefix, since load starts at 0 at the
# depot and only changes at visited customers). The constraint enforces:
#
#   load[0] = delta[seq[0]]
#   load[i] = load[i-1] + delta[seq[i]]      for i >= 1
#   for all i: load[i] <= capacity
#
# `delta` has length `n_total` and is indexed by the Hexaly 0-indexed node
# value (typically `+q` at a pickup and `-q` at the paired delivery).

struct Capacity{T<:Real} <: MOI.AbstractVectorSet
    delta::Vector{T}
    capacity::T
end

MOI.dimension(s::Capacity) = length(s.delta)

Base.copy(s::Capacity) = s

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{<:Union{MOI.VectorOfVariables,MOI.VectorAffineFunction}},
    ::Type{<:Capacity},
)
    return true
end

function MOI.add_constraint(
    model::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::Capacity,
)
    items = _normalize_sum_distances_items(f)
    length(items) == MOI.dimension(s) || error(
        "Hexaly.Capacity expected `length(nodes) == $(MOI.dimension(s))`; ",
        "got $(length(items)).",
    )
    all(it -> it isa MOI.VariableIndex, items) || error(
        "Hexaly.Capacity: every item must be a `MOI.VariableIndex` backed by ",
        "a Hexaly list (a column of a `Hexaly.Partition` / `Hexaly.PartitionPD`).",
    )
    first_pl = _info(model, items[1]).parent_list
    first_pl !== nothing || error(
        "Hexaly.Capacity: variables have no parent Hexaly list.",
    )
    all(_info(model, vi).parent_list === first_pl for vi in items) || error(
        "Hexaly.Capacity: all node variables must belong to the same Hexaly list.",
    )

    m = model.model
    seq = first_pl
    c = m.count(seq)
    capacity = round(Int, s.capacity)
    delta_arr = m.array(pylist(round.(Int, s.delta)))

    load = m.array(
        m.range(0, c),
        m.lambda_function(
            pyfunc(
                (i, prev) -> m.iif(
                    i == 0,
                    m.at(delta_arr, seq[0]),
                    prev + m.at(delta_arr, seq[i]),
                );
                wrap = "lambda f: lambda i, prev: f(i, prev)",
            ),
        ),
        Py(0),
    )

    m.constraint(
        m.and_(
            m.range(0, c),
            m.lambda_function(
                pyfunc(
                    i -> load[i] <= Py(capacity);
                    wrap = "lambda f: lambda i: f(i)",
                ),
            ),
        ),
    )

    cindex = MOI.ConstraintIndex{typeof(f),typeof(s)}(
        length(model.constraint_info) + 1,
    )
    model.constraint_info[cindex] = ConstraintInfo(cindex, nothing, f, s)
    return cindex
end
=======
>>>>>>> d4b0de7 (Add cost prefix)

# `Hexaly.CapacitatedTimeWindows(travel, earliest, latest, fixed_time, slope,
# delta, capacity)` — combined capacity + time-window constraint on
# `[t; depot_start; nodes; depot_end]`. Same layout as `TimeWindows`, but
# the per-node service time is the affine function
# `fixed_time + slope * |delta[v]|` (so service time depends on the load
# handled at that node — that's why capacity and TW must live in one set).

struct CapacitatedTimeWindows{T<:Real} <: MOI.AbstractVectorSet
    travel::Matrix{T}
    earliest::Vector{T}
    latest::Vector{T}
    fixed_time::T
    slope::T
    delta::Vector{T}
    capacity::T
end

MOI.dimension(s::CapacitatedTimeWindows) = length(s.earliest) + 3

Base.copy(s::CapacitatedTimeWindows) = s

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{<:Union{MOI.VectorOfVariables,MOI.VectorAffineFunction}},
    ::Type{<:CapacitatedTimeWindows},
)
    return true
end

function MOI.add_constraint(
    model::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::CapacitatedTimeWindows,
)
    items = _normalize_sum_distances_items(f)
    length(items) == MOI.dimension(s) || error(
        "Hexaly.CapacitatedTimeWindows expected ",
        "`length([t; depot_start; nodes; depot_end]) == $(MOI.dimension(s))`; ",
        "got $(length(items)).",
    )
    items[1] isa MOI.VariableIndex || error(
        "Hexaly.CapacitatedTimeWindows: first item must be the total-time ",
        "`t` variable.",
    )
    items[2] isa Real || error(
        "Hexaly.CapacitatedTimeWindows: second item must be the constant ",
        "`depot_start` index.",
    )
    items[end] isa Real || error(
        "Hexaly.CapacitatedTimeWindows: last item must be the constant ",
        "`depot_end` index.",
    )
    t_vi = items[1]
    depot_start = round(Int, items[2])
    depot_end = round(Int, items[end])
    var_items = @view items[3:(end-1)]
    all(it -> it isa MOI.VariableIndex, var_items) || error(
        "Hexaly.CapacitatedTimeWindows: items 3..end-1 must be node ",
        "`MOI.VariableIndex` values backed by a Hexaly list.",
    )
    first_pl = _info(model, var_items[1]).parent_list
    first_pl !== nothing || error(
        "Hexaly.CapacitatedTimeWindows: node variables have no parent Hexaly list.",
    )
    all(_info(model, vi).parent_list === first_pl for vi in var_items) || error(
        "Hexaly.CapacitatedTimeWindows: all node variables must belong to the same ",
        "Hexaly list.",
    )

    m = model.model
    t_var = _info(model, t_vi).variable
    seq = first_pl
    c = m.count(seq)
    capacity = round(Int, s.capacity)
    n_rows = size(s.travel, 1)
    travel_arr =
        m.array(pylist([pylist(round.(Int, s.travel[i, :])) for i = 1:n_rows]))
    earliest_arr = m.array(pylist(round.(Int, s.earliest)))
    latest_arr = m.array(pylist(round.(Int, s.latest)))
    delta_arr = m.array(pylist(round.(Int, s.delta)))
    # Pre-compute the per-node affine service time so the Hexaly model only
    # needs an array lookup at each step of the recurrence.
    service_vals = round.(Int, s.fixed_time .+ s.slope .* abs.(s.delta))
    service_arr = m.array(pylist(service_vals))

    # Cumulative load through the route.
    load = m.array(
        m.range(0, c),
        m.lambda_function(
            pyfunc(
                (i, prev) -> m.iif(
                    i == 0,
                    m.at(delta_arr, seq[0]),
                    prev + m.at(delta_arr, seq[i]),
                );
                wrap = "lambda f: lambda i, prev: f(i, prev)",
            ),
        ),
        Py(0),
    )

    # Capacity constraint at every visited position.
    m.constraint(
        m.and_(
            m.range(0, c),
            m.lambda_function(
                pyfunc(
                    i -> load[i] <= Py(capacity);
                    wrap = "lambda f: lambda i: f(i)",
                ),
            ),
        ),
    )

    # End-of-service time, with service[v] = fixed_time + slope * |delta[v]|.
    end_time = m.array(
        m.range(0, c),
        m.lambda_function(
            pyfunc(
                (i, prev) -> m.iif(
                    i == 0,
                    m.max(
                        m.at(earliest_arr, seq[0]),
                        m.at(travel_arr, Py(depot_start), seq[0]),
                    ) + m.at(service_arr, seq[0]),
                    m.max(
                        m.at(earliest_arr, seq[i]),
                        prev + m.at(travel_arr, seq[i-1], seq[i]),
                    ) + m.at(service_arr, seq[i]),
                );
                wrap = "lambda f: lambda i, prev: f(i, prev)",
            ),
        ),
        Py(0),
    )

    # Per-customer time window:  start_service[i] = end_time[i] - service[seq[i]]
    # must satisfy start_service[i] <= latest[seq[i]].
    m.constraint(
        m.and_(
            m.range(0, c),
            m.lambda_function(
                pyfunc(
                    i -> end_time[i] - m.at(service_arr, seq[i]) <=
                         m.at(latest_arr, seq[i]);
                    wrap = "lambda f: lambda i: f(i)",
                ),
            ),
        ),
    )

    # Makespan: t >= end_time[c-1] + travel[seq[c-1], depot_end] (or 0 if
    # the truck stays at the depot).
    total_time = m.iif(
        c > 0,
        end_time[c-1] + m.at(travel_arr, seq[c-1], Py(depot_end)),
        Py(0),
    )
    m.constraint(t_var >= total_time)

    cindex = MOI.ConstraintIndex{typeof(f),typeof(s)}(
        length(model.constraint_info) + 1,
    )
    model.constraint_info[cindex] = ConstraintInfo(cindex, nothing, f, s)
    return cindex
end
