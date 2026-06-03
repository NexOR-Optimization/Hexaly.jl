# Hexaly-specific implementations of the `MathOptVRP` vector sets. The
# set definitions, JuMP `build_variable` overloads and `MOI.dimension`
# methods live in `MathOptVRP`; here we only provide the
# `MOI.add_constrained_variables` / `MOI.add_constraint` methods that
# realise each set with Hexaly's Python modelling API.

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

# ── MathOptVRP.List ────────────────────────────────────────────────────

function MOI.supports_add_constrained_variables(
    ::Optimizer,
    ::Type{MathOptVRP.List},
)
    return true
end

function MOI.add_constrained_variables(model::Optimizer, set::MathOptVRP.List)
    n = set.dimension
    hx_list = model.model.list(Py(n))
    # `MathOptVRP.List(n)` is a permutation of `0:n-1`; a bare
    # `model.list(n)` only enforces distinctness with a variable length
    # in `0..n`. Pin the length so the solver can't pick a shorter list
    # (which would be optimal under `sum_distances`).
    model.model.constraint(model.model.count(hx_list) == Py(n))
    indices = _add_list_variables!(model, hx_list, n)
    cindex = MOI.ConstraintIndex{MOI.VectorOfVariables,MathOptVRP.List}(
        length(model.constraint_info) + 1,
    )
    model.constraint_info[cindex] =
        ConstraintInfo(cindex, hx_list, MOI.VectorOfVariables(indices), set)
    return indices, cindex
end

# ── MathOptVRP.Partition ───────────────────────────────────────────────

function MOI.supports_add_constrained_variables(
    ::Optimizer,
    ::Type{MathOptVRP.Partition},
)
    return true
end

function MOI.add_constrained_variables(model::Optimizer, set::MathOptVRP.Partition)
    m = model.model
    lists = Py[m.list(Py(set.num_clients)) for _ = 1:(set.num_trucks)]
    m.constraint(m.partition(pylist(lists)))
    indices = MOI.VariableIndex[]
    for hx_list in lists
        col_indices = _add_list_variables!(model, hx_list, set.num_clients)
        append!(indices, col_indices)
    end
    cindex = MOI.ConstraintIndex{MOI.VectorOfVariables,MathOptVRP.Partition}(
        length(model.constraint_info) + 1,
    )
    model.constraint_info[cindex] =
        ConstraintInfo(cindex, nothing, MOI.VectorOfVariables(indices), set)
    return indices, cindex
end

# ── MathOptVRP.PartitionPD ─────────────────────────────────────────────

function MOI.supports_add_constrained_variables(
    ::Optimizer,
    ::Type{MathOptVRP.PartitionPD},
)
    return true
end

function MOI.add_constrained_variables(model::Optimizer, set::MathOptVRP.PartitionPD)
    m = model.model
    n_total = MathOptVRP._pd_n_total(set)
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
    cindex = MOI.ConstraintIndex{MOI.VectorOfVariables,MathOptVRP.PartitionPD}(
        length(model.constraint_info) + 1,
    )
    model.constraint_info[cindex] =
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

function MOI.add_constraint(
    model::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::MathOptVRP.TimeWindows,
)
    items = _normalize_sum_distances_items(f)
    length(items) == MOI.dimension(s) || error(
        "MathOptVRP.TimeWindows expected `length([t; depot_start; nodes; depot_end]) ",
        "== $(MOI.dimension(s))`; got $(length(items)).",
    )
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
    first_pl = _info(model, var_items[1]).parent_list
    first_pl !== nothing || error(
        "MathOptVRP.TimeWindows: node variables have no parent Hexaly list.",
    )
    all(_info(model, vi).parent_list === first_pl for vi in var_items) || error(
        "MathOptVRP.TimeWindows: all node variables must belong to the same Hexaly list.",
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

    # Makespan: t >= end_time[c-1] + travel[seq[c-1], depot_end] (or 0
    # if the truck stays at the depot).
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

# ── MathOptVRP.Capacity ────────────────────────────────────────────────
# No depot prefix needed: load starts at 0 at the depot and only changes
# at visited customers.

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{<:Union{MOI.VectorOfVariables,MOI.VectorAffineFunction}},
    ::Type{<:MathOptVRP.Capacity},
)
    return true
end

function MOI.add_constraint(
    model::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::MathOptVRP.Capacity,
)
    items = _normalize_sum_distances_items(f)
    length(items) == MOI.dimension(s) || error(
        "MathOptVRP.Capacity expected `length(nodes) == $(MOI.dimension(s))`; ",
        "got $(length(items)).",
    )
    all(it -> it isa MOI.VariableIndex, items) || error(
        "MathOptVRP.Capacity: every item must be a `MOI.VariableIndex` backed by ",
        "a Hexaly list.",
    )
    first_pl = _info(model, items[1]).parent_list
    first_pl !== nothing || error(
        "MathOptVRP.Capacity: variables have no parent Hexaly list.",
    )
    all(_info(model, vi).parent_list === first_pl for vi in items) || error(
        "MathOptVRP.Capacity: all node variables must belong to the same Hexaly list.",
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

# ── MathOptVRP.CapacitatedTimeWindows ──────────────────────────────────
# Same `[t; depot_start; nodes; depot_end]` layout as TimeWindows but
# also posts the per-position capacity constraint and uses the affine
# service time `fixed_time + slope * |delta[v]|`.

function MOI.supports_constraint(
    ::Optimizer,
    ::Type{<:Union{MOI.VectorOfVariables,MOI.VectorAffineFunction}},
    ::Type{<:MathOptVRP.CapacitatedTimeWindows},
)
    return true
end

function MOI.add_constraint(
    model::Optimizer,
    f::Union{MOI.VectorOfVariables,MOI.VectorAffineFunction},
    s::MathOptVRP.CapacitatedTimeWindows,
)
    items = _normalize_sum_distances_items(f)
    length(items) == MOI.dimension(s) || error(
        "MathOptVRP.CapacitatedTimeWindows expected ",
        "`length([t; depot_start; nodes; depot_end]) == $(MOI.dimension(s))`; ",
        "got $(length(items)).",
    )
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
    first_pl = _info(model, var_items[1]).parent_list
    first_pl !== nothing || error(
        "MathOptVRP.CapacitatedTimeWindows: node variables have no parent Hexaly list.",
    )
    all(_info(model, vi).parent_list === first_pl for vi in var_items) || error(
        "MathOptVRP.CapacitatedTimeWindows: all node variables must belong to the same ",
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
    service_vals = round.(Int, s.fixed_time .+ s.slope .* abs.(s.delta))
    service_arr = m.array(pylist(service_vals))

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
