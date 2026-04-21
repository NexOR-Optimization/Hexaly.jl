# Hexaly.jl

[![Build Status](https://github.com/NexOR-Optimization/Hexaly.jl/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/NexOR-Optimization/Hexaly.jl/actions?query=workflow%3ACI)

> [!WARNING]
> This package is still a work in progress in early stage of development.

[Hexaly.jl](https://github.com/NexOR-Optimization/Hexaly.jl) is a wrapper for the
[Hexaly Optimizer](https://www.hexaly.com/).

It provides two layers of access:

1. A thin wrapper over the Hexaly Python API (via `PythonCall.jl`), exposed as
   `Hexaly.raw_optimizer()`.
2. A [MathOptInterface](https://jump.dev/MathOptInterface.jl) (MOI) wrapper
   exposed as `Hexaly.Optimizer`, which makes Hexaly usable from
   [JuMP](https://jump.dev/JuMP.jl).

## Installation

```julia
import Pkg
Pkg.add(url = "https://github.com/NexOR-Optimization/Hexaly.jl")
```

Hexaly requires a license. See [Hexaly's documentation](https://www.hexaly.com/docs/)
for instructions.

## Affiliation

This wrapper is maintained by NexOR Optimization and is not officially supported
by Hexaly.

## Use with JuMP

To use Hexaly with JuMP, use `Hexaly.Optimizer`:

```julia
using JuMP, Hexaly

model = Model(Hexaly.Optimizer)
set_attribute(model, "time_limit", 10)  # in seconds
set_silent(model)

@variable(model, 0 <= x <= 3, Int)
@variable(model, 0 <= y <= 3, Int)
@constraint(model, x + y <= 4)
@objective(model, Max, 3x + 2y)
optimize!(model)

@show value(x), value(y), objective_value(model)
```

## Raw Python API

```julia
using Hexaly
using Hexaly.PythonCall

optimizer = Hexaly.raw_optimizer()
m = optimizer.model
x = m.int(0, 10)
m.constraint(x >= 3)
m.minimize(x)
m.close()

optimizer.param.time_limit = 5
optimizer.solve()
@show pyconvert(Int, x.value)
```

## Supported MOI features

- Variables:
  - Unconstrained (float)
  - `MOI.Integer`, `MOI.ZeroOne`
  - `MOI.EqualTo`, `MOI.LessThan`, `MOI.GreaterThan`, `MOI.Interval`
    (integer or float)
- Constraints:
  - `MOI.VariableIndex` in bound sets (integer or float)
  - `MOI.ScalarAffineFunction` in `MOI.{EqualTo, LessThan, GreaterThan}`
  - `MOI.VectorOfVariables` in `MOI.AllDifferent`
  - `MOI.VectorOfVariables` in `MOI.Circuit`
  - `MOI.VectorOfVariables` in `MOI.BinPacking`
- Objectives:
  - `MOI.VariableIndex`
  - `MOI.ScalarAffineFunction`
- Options:
  - `MOI.Silent`
  - `MOI.TimeLimitSec`
  - `MOI.RawOptimizerAttribute("<hexaly-param>")`
