using Hexaly
using Test
import MathOptVRP

# The routes are read back from the `Partition` variables themselves: a
# truck's column holds the clients it visits followed by `0`s, so
# `MathOptVRP.Tests` needs nothing Hexaly-specific to recover them. See
# `Hexaly._add_list_variables!` for the trailing `0` sentinel.
MathOptVRP.Tests.runtests(Hexaly.Optimizer)
