# Realisation of the 1-based MathOptVRP routing sets with Hexaly's C API.

# Create `n` MOI variables backed by `hx_list[0..n-1]`, each tagged with
# `parent_list = hx_list` so the objective handler can recover the list.
#
# A list may be shorter than `n` (the parts of a partition have a variable
# count), but the MOI variables exist for every position. The trailing zero
# is MathOptVRP's sentinel; real Hexaly list elements are offset by one.
function _add_list_variables!(m::Optimizer, hx_list::HxExpression, n::Int)
    md = m.model
    indices = MOI.VariableIndex[]
    for i = 0:(n-1)
        raw_elem = iif(
            md,
            lt(md, i, count_(md, hx_list)),
            at(md, hx_list, i),
            -1,
        )
        elem = sum(md, raw_elem, 1)
        info = VariableInfo(
            MOI.VariableIndex(0),
            elem;
            is_integer = true,
            parent_list = hx_list,
        )
        info.lb = 0.0
        info.ub = Float64(n)
        idx = MOI.Utilities.CleverDicts.add_item(m.variable_info, info)
        _info(m, idx).index = idx
        push!(indices, idx)
    end
    return indices
end

# ── MathOptVRP.Permutation ──────────────────────────────────────────

function MOI.supports_add_constrained_variables(
    ::Optimizer,
    ::Type{MathOptVRP.Permutation},
)
    return true
end

function MOI.add_constrained_variables(m::Optimizer, set::MathOptVRP.Permutation)
    n = set.dimension
    hx_list = list!(m.model, n)
    # Pin the list's count so the solver can't pick a shorter list.
    _add_hexaly_constraint!(m, eq(m.model, count_(m.model, hx_list), n))
    indices = _add_list_variables!(m, hx_list, n)
    cindex = MOI.ConstraintIndex{MOI.VectorOfVariables,MathOptVRP.Permutation}(
        length(m.constraint_info) + 1,
    )
    m.constraint_info[cindex] =
        ConstraintInfo(cindex, hx_list, MOI.VectorOfVariables(indices), set)
    return indices, cindex
end

# ── MathOptVRP.Partition ────────────────────────────────────────────

function MOI.supports_add_constrained_variables(
    ::Optimizer,
    ::Type{MathOptVRP.Partition},
)
    return true
end

function MOI.add_constrained_variables(m::Optimizer, set::MathOptVRP.Partition)
    md = m.model
    lists = HxExpression[list!(md, set.num_clients) for _ = 1:(set.num_trucks)]
    _add_hexaly_constraint!(m, partition(md, lists))
    indices = MOI.VariableIndex[]
    for hx_list in lists
        col_indices = _add_list_variables!(m, hx_list, set.num_clients)
        append!(indices, col_indices)
    end
    cindex = MOI.ConstraintIndex{MOI.VectorOfVariables,MathOptVRP.Partition}(
        length(m.constraint_info) + 1,
    )
    m.constraint_info[cindex] =
        ConstraintInfo(cindex, nothing, MOI.VectorOfVariables(indices), set)
    return indices, cindex
end

# ── MathOptVRP.PartitionPD ──────────────────────────────────────────

_pd_n_total(s::MathOptVRP.PartitionPD) =
    s.num_services + 2 * s.num_pickup_deliveries

function MOI.supports_add_constrained_variables(
    ::Optimizer,
    ::Type{MathOptVRP.PartitionPD},
)
    return true
end

function MOI.add_constrained_variables(m::Optimizer, set::MathOptVRP.PartitionPD)
    md = m.model
    n_total = _pd_n_total(set)
    lists = HxExpression[list!(md, n_total) for _ = 1:(set.num_trucks)]
    _add_hexaly_constraint!(m, partition(md, lists))
    for k = 0:(set.num_pickup_deliveries-1)
        p = set.num_services + k
        d = set.num_services + set.num_pickup_deliveries + k
        for seq in lists
            _add_hexaly_constraint!(m,
                eq(md, contains_(md, seq, p), contains_(md, seq, d)))
            _add_hexaly_constraint!(m,
                leq(md, index_of(md, seq, p), index_of(md, seq, d)))
        end
    end
    indices = MOI.VariableIndex[]
    for hx_list in lists
        col_indices = _add_list_variables!(m, hx_list, n_total)
        append!(indices, col_indices)
    end
    cindex = MOI.ConstraintIndex{MOI.VectorOfVariables,MathOptVRP.PartitionPD}(
        length(m.constraint_info) + 1,
    )
    m.constraint_info[cindex] =
        ConstraintInfo(cindex, nothing, MOI.VectorOfVariables(indices), set)
    return indices, cindex
end

# ── MathOptVRP.TimeWindows ─────────────────────────────────────────────
# Layout: `[t; depot_start; nodes...; depot_end]`. Posts the per-customer
# time-window constraint and the makespan linkage `t >= total_time`.

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{<:Union{MOI.VectorOfVariables,MOI.VectorAffineFunction}},
    ::Type{<:MathOptVRP.TimeWindows},
)
    return true
end

# These sets constrain node variables that a `Partition` / `PartitionPD`
# already created; they cannot create any. Without this, MOI's default
# infers `supports_add_constrained_variables` from the `VectorOfVariables`
# constraint above and `copy_to` builds the variables from this set instead
# of from the partition, leaving them without a backing Hexaly list.
function MOI.supports_add_constrained_variables(
    ::Optimizer,
    ::Type{<:MathOptVRP.TimeWindows},
)
    return false
end

function MOI.add_constraint(
    m::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::MathOptVRP.TimeWindows,
)
    items = _normalize_sum_distances_items(f)
    length(items) == MOI.dimension(s) || error(
        "MathOptVRP.TimeWindows expected `length([t; depot_start; nodes; depot_end]) ",
        "== $(MOI.dimension(s))`; got $(length(items)).",
    )
    # Item 1 is the user's `t` variable, items 2..end are node values.
    _shift_to_zero_based!(items, 2)
    items[1] isa MOI.VariableIndex || error(
        "MathOptVRP.TimeWindows: first item must be the total-time `t` variable.",
    )
    items[2] isa Real || error(
        "MathOptVRP.TimeWindows: second item must be the constant `depot_start` index.",
    )
    items[end] isa Real || error(
        "MathOptVRP.TimeWindows: last item must be the constant `depot_end` index.",
    )
    t_vi = items[1]
    depot_start = round(Int, items[2])
    depot_end = round(Int, items[end])
    var_items = @view items[3:(end-1)]
    all(it -> it isa MOI.VariableIndex, var_items) || error(
        "MathOptVRP.TimeWindows: items 3..end-1 must be node `MOI.VariableIndex` values ",
        "backed by a Hexaly list.",
    )
    first_pl = _info(m, var_items[1]).parent_list
    first_pl !== nothing || error(
        "MathOptVRP.TimeWindows: node variables have no parent Hexaly list.",
    )
    all(_info(m, vi).parent_list === first_pl for vi in var_items) || error(
        "MathOptVRP.TimeWindows: all node variables must belong to the same Hexaly list.",
    )

    md = m.model
    t_var = _info(m, t_vi).variable
    seq = first_pl
    c = count_(md, seq)
    service = round(Int, s.service)
    n_rows = size(s.travel, 1)
    dist_arr = array(md,
        [array(md, round.(Int, s.travel[i, :])) for i = 1:n_rows])
    earliest_arr = array(md, round.(Int, s.earliest))
    latest_arr = array(md, round.(Int, s.latest))

    end_time = array(md,
        range_(md, 0, c),
        lambda_function(md,
            (i, prev) -> iif(md,
                eq(md, i, 0),
                sum(md,
                    max(md,
                        at(md, earliest_arr, at(md, seq, 0)),
                        at(md, dist_arr, depot_start, at(md, seq, 0)),
                    ),
                    service,
                ),
                sum(md,
                    max(md,
                        at(md, earliest_arr, at(md, seq, i)),
                        sum(md, prev, at(md, dist_arr, at(md, seq, sub(md, i, 1)), at(md, seq, i))),
                    ),
                    service,
                ),
            ); nargs = 2,
        ),
        0,
    )

    _add_hexaly_constraint!(m,
        and_(md,
            range_(md, 0, c),
            lambda_function(md,
                i -> leq(md,
                    sub(md, at(md, end_time, i), service),
                    at(md, latest_arr, at(md, seq, i)),
                ); nargs = 1,
            ),
        ),
    )

    total_time = iif(md,
        gt(md, c, 0),
        sum(md, at(md, end_time, sub(md, c, 1)),
            at(md, dist_arr, at(md, seq, sub(md, c, 1)), depot_end)),
        0,
    )
    _add_hexaly_constraint!(m, geq(md, t_var, total_time))

    cindex = MOI.ConstraintIndex{typeof(f),typeof(s)}(
        length(m.constraint_info) + 1,
    )
    m.constraint_info[cindex] = ConstraintInfo(cindex, nothing, f, s)
    return cindex
end

# ── MathOptVRP route-side sequence constraints ──────────────────────────────

function _mathoptvrp_parent_list(
    m::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    dimension::Int,
    set_name::AbstractString,
)
    items = _normalize_sum_distances_items(f)
    length(items) == dimension || error(
        "$set_name expected $dimension route-node variables; got $(length(items)).",
    )
    _shift_to_zero_based!(items)
    all(it -> it isa MOI.VariableIndex, items) || error(
        "$set_name: every item must be a `MOI.VariableIndex` backed by a Hexaly list.",
    )
    seq = _info(m, items[1]).parent_list
    seq !== nothing || error("$set_name: variables have no parent Hexaly list.")
    all(_info(m, vi).parent_list === seq for vi in items) || error(
        "$set_name: all node variables must belong to the same Hexaly list.",
    )
    return seq
end

for SetType in (
    MathOptVRP.RouteCompatibility,
    MathOptVRP.RouteOrder,
    MathOptVRP.RouteExtremities,
)
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

function MOI.add_constraint(
    m::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::MathOptVRP.RouteCompatibility,
)
    seq = _mathoptvrp_parent_list(
        m, f, MOI.dimension(s), "MathOptVRP.RouteCompatibility",
    )
    for node in findall(!, s.allowed)
        _add_hexaly_constraint!(m, eq(m.model, contains_(m.model, seq, node - 1), 0))
    end
    cindex = MOI.ConstraintIndex{typeof(f),typeof(s)}(
        length(m.constraint_info) + 1,
    )
    m.constraint_info[cindex] = ConstraintInfo(cindex, nothing, f, s)
    return cindex
end

function MOI.add_constraint(
    m::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::MathOptVRP.RouteOrder,
)
    seq = _mathoptvrp_parent_list(
        m, f, MOI.dimension(s), "MathOptVRP.RouteOrder",
    )
    md = m.model
    for p in findall(s.before), q in findall(s.after)
        both = and_(md, contains_(md, seq, p - 1), contains_(md, seq, q - 1))
        _add_hexaly_constraint!(m, or_(md, not_(md, both),
            lt(md, index_of(md, seq, p - 1), index_of(md, seq, q - 1))))
    end
    cindex = MOI.ConstraintIndex{typeof(f),typeof(s)}(
        length(m.constraint_info) + 1,
    )
    m.constraint_info[cindex] = ConstraintInfo(cindex, nothing, f, s)
    return cindex
end

function MOI.add_constraint(
    m::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::MathOptVRP.RouteExtremities,
)
    seq = _mathoptvrp_parent_list(
        m, f, MOI.dimension(s), "MathOptVRP.RouteExtremities",
    )
    md = m.model
    others = findall(!, s.members)
    for p in findall(s.members)
        isempty(others) && continue
        pairwise_before = [or_(md, not_(md, contains_(md, seq, q - 1)),
            lt(md, index_of(md, seq, p - 1), index_of(md, seq, q - 1)))
            for q in others]
        pairwise_after = [or_(md, not_(md, contains_(md, seq, q - 1)),
            lt(md, index_of(md, seq, q - 1), index_of(md, seq, p - 1)))
            for q in others]
        before = length(pairwise_before) == 1 ? pairwise_before[1] :
            and_(md, pairwise_before...)
        after = length(pairwise_after) == 1 ? pairwise_after[1] :
            and_(md, pairwise_after...)
        _add_hexaly_constraint!(m, or_(md,
            not_(md, contains_(md, seq, p - 1)), before, after))
    end
    cindex = MOI.ConstraintIndex{typeof(f),typeof(s)}(
        length(m.constraint_info) + 1,
    )
    m.constraint_info[cindex] = ConstraintInfo(cindex, nothing, f, s)
    return cindex
end

# ── MathOptVRP.Capacity ────────────────────────────────────────────────

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{<:Union{MOI.VectorOfVariables,MOI.VectorAffineFunction}},
    ::Type{<:MathOptVRP.Capacity},
)
    return true
end

# These sets constrain node variables that a `Partition` / `PartitionPD`
# already created; they cannot create any. Without this, MOI's default
# infers `supports_add_constrained_variables` from the `VectorOfVariables`
# constraint above and `copy_to` builds the variables from this set instead
# of from the partition, leaving them without a backing Hexaly list.
function MOI.supports_add_constrained_variables(
    ::Optimizer,
    ::Type{<:MathOptVRP.Capacity},
)
    return false
end

function MOI.add_constraint(
    m::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::MathOptVRP.Capacity,
)
    items = _normalize_sum_distances_items(f)
    length(items) == MOI.dimension(s) || error(
        "MathOptVRP.Capacity expected `length(nodes) == $(MOI.dimension(s))`; ",
        "got $(length(items)).",
    )
    _shift_to_zero_based!(items)
    all(it -> it isa MOI.VariableIndex, items) || error(
        "MathOptVRP.Capacity: every item must be a `MOI.VariableIndex` backed by ",
        "a Hexaly list.",
    )
    first_pl = _info(m, items[1]).parent_list
    first_pl !== nothing || error(
        "MathOptVRP.Capacity: variables have no parent Hexaly list.",
    )
    all(_info(m, vi).parent_list === first_pl for vi in items) || error(
        "MathOptVRP.Capacity: all node variables must belong to the same Hexaly list.",
    )

    md = m.model
    seq = first_pl
    c = count_(md, seq)
    capacity = round(Int, s.capacity)
    delta_arr = array(md, round.(Int, s.delta))

    load = array(md,
        range_(md, 0, c),
        lambda_function(md,
            (i, prev) -> iif(md,
                eq(md, i, 0),
                at(md, delta_arr, at(md, seq, 0)),
                sum(md, prev, at(md, delta_arr, at(md, seq, i))),
            ); nargs = 2,
        ),
        0,
    )

    _add_hexaly_constraint!(m,
        and_(md,
            range_(md, 0, c),
            lambda_function(md,
                i -> leq(md, at(md, load, i), capacity); nargs = 1,
            ),
        ),
    )

    cindex = MOI.ConstraintIndex{typeof(f),typeof(s)}(
        length(m.constraint_info) + 1,
    )
    m.constraint_info[cindex] = ConstraintInfo(cindex, nothing, f, s)
    return cindex
end

# ── MathOptVRP.CapacitatedTimeWindows ──────────────────────────────────

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{<:Union{MOI.VectorOfVariables,MOI.VectorAffineFunction}},
    ::Type{<:MathOptVRP.CapacitatedTimeWindows},
)
    return true
end

# These sets constrain node variables that a `Partition` / `PartitionPD`
# already created; they cannot create any. Without this, MOI's default
# infers `supports_add_constrained_variables` from the `VectorOfVariables`
# constraint above and `copy_to` builds the variables from this set instead
# of from the partition, leaving them without a backing Hexaly list.
function MOI.supports_add_constrained_variables(
    ::Optimizer,
    ::Type{<:MathOptVRP.CapacitatedTimeWindows},
)
    return false
end

function MOI.add_constraint(
    m::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::MathOptVRP.CapacitatedTimeWindows,
)
    items = _normalize_sum_distances_items(f)
    length(items) == MOI.dimension(s) || error(
        "MathOptVRP.CapacitatedTimeWindows expected ",
        "`length([t; depot_start; nodes; depot_end]) == $(MOI.dimension(s))`; ",
        "got $(length(items)).",
    )
    # Item 1 is the user's `t` variable, items 2..end are node values.
    _shift_to_zero_based!(items, 2)
    items[1] isa MOI.VariableIndex || error(
        "MathOptVRP.CapacitatedTimeWindows: first item must be the total-time ",
        "`t` variable.",
    )
    items[2] isa Real || error(
        "MathOptVRP.CapacitatedTimeWindows: second item must be the constant ",
        "`depot_start` index.",
    )
    items[end] isa Real || error(
        "MathOptVRP.CapacitatedTimeWindows: last item must be the constant ",
        "`depot_end` index.",
    )
    t_vi = items[1]
    depot_start = round(Int, items[2])
    depot_end = round(Int, items[end])
    var_items = @view items[3:(end-1)]
    all(it -> it isa MOI.VariableIndex, var_items) || error(
        "MathOptVRP.CapacitatedTimeWindows: items 3..end-1 must be node ",
        "`MOI.VariableIndex` values backed by a Hexaly list.",
    )
    first_pl = _info(m, var_items[1]).parent_list
    first_pl !== nothing || error(
        "MathOptVRP.CapacitatedTimeWindows: node variables have no parent Hexaly list.",
    )
    all(_info(m, vi).parent_list === first_pl for vi in var_items) || error(
        "MathOptVRP.CapacitatedTimeWindows: all node variables must belong to the same ",
        "Hexaly list.",
    )

    md = m.model
    t_var = _info(m, t_vi).variable
    seq = first_pl
    c = count_(md, seq)
    capacity = round(Int, s.capacity)
    n_rows = size(s.travel, 1)
    travel_arr = array(md,
        [array(md, round.(Int, s.travel[i, :])) for i = 1:n_rows])
    earliest_arr = array(md, round.(Int, s.earliest))
    latest_arr = array(md, round.(Int, s.latest))
    delta_arr = array(md, round.(Int, s.delta))
    service_vals = round.(Int, s.fixed_time .+ s.slope .* abs.(s.delta))
    service_arr = array(md, service_vals)

    load = array(md,
        range_(md, 0, c),
        lambda_function(md,
            (i, prev) -> iif(md,
                eq(md, i, 0),
                at(md, delta_arr, at(md, seq, 0)),
                sum(md, prev, at(md, delta_arr, at(md, seq, i))),
            ); nargs = 2,
        ),
        0,
    )

    _add_hexaly_constraint!(m,
        and_(md,
            range_(md, 0, c),
            lambda_function(md,
                i -> leq(md, at(md, load, i), capacity); nargs = 1,
            ),
        ),
    )

    end_time = array(md,
        range_(md, 0, c),
        lambda_function(md,
            (i, prev) -> iif(md,
                eq(md, i, 0),
                sum(md,
                    max(md,
                        at(md, earliest_arr, at(md, seq, 0)),
                        at(md, travel_arr, depot_start, at(md, seq, 0)),
                    ),
                    at(md, service_arr, at(md, seq, 0)),
                ),
                sum(md,
                    max(md,
                        at(md, earliest_arr, at(md, seq, i)),
                        sum(md, prev, at(md, travel_arr, at(md, seq, sub(md, i, 1)), at(md, seq, i))),
                    ),
                    at(md, service_arr, at(md, seq, i)),
                ),
            ); nargs = 2,
        ),
        0,
    )

    _add_hexaly_constraint!(m,
        and_(md,
            range_(md, 0, c),
            lambda_function(md,
                i -> leq(md,
                    sub(md, at(md, end_time, i), at(md, service_arr, at(md, seq, i))),
                    at(md, latest_arr, at(md, seq, i)),
                ); nargs = 1,
            ),
        ),
    )

    total_time = iif(md,
        gt(md, c, 0),
        sum(md, at(md, end_time, sub(md, c, 1)),
            at(md, travel_arr, at(md, seq, sub(md, c, 1)), depot_end)),
        0,
    )
    _add_hexaly_constraint!(m, geq(md, t_var, total_time))

    cindex = MOI.ConstraintIndex{typeof(f),typeof(s)}(
        length(m.constraint_info) + 1,
    )
    m.constraint_info[cindex] = ConstraintInfo(cindex, nothing, f, s)
    return cindex
end
