module Hexaly

import CondaPkg
using CEnum
import MathOptInterface as MOI
import MathOptVRP
import JuMP

# `libhexaly` is the path to `libhexaly145.so`. The generated `gen/libhexaly.jl`
# bindings use it as the ccall library tag. We default it to the bare name
# (so dlopen searches LD_LIBRARY_PATH) and overwrite in `__init__` once the
# CondaPkg env has installed the wheel.
libhexaly = "libhexaly145"

include("gen/libhexaly.jl")
include("c_wrapper.jl")

function __init__()
    try
        global libhexaly = _find_libhexaly()
    catch
        @info "Installing Hexaly Python wheel (provides libhexaly145.so) from pip.hexaly.com..."
        python = CondaPkg.which("python")
        run(`$python -m pip install hexaly --extra-index-url https://pip.hexaly.com -q`)
        global libhexaly = _find_libhexaly()
    end
    return
end

"""
    version()

Return the Hexaly Optimizer version as a `VersionNumber`.
"""
function version()
    # `hx_version_code` returns major*10 + minor (e.g. 145 for 14.5).
    code = Int(hx_version_code())
    return VersionNumber(code ÷ 10, code % 10)
end

"""
    has_license()::Bool

Return `true` if a Hexaly license is available (either via `HX_LICENSE_CONTENT`,
`HX_LICENSE_PATH`, a `license.dat` in the working directory, or the default
`/opt/hexaly_*/license.dat`).
"""
function has_license()
    !isempty(get(ENV, "HX_LICENSE_CONTENT", "")) && return true
    path = get(ENV, "HX_LICENSE_PATH", "")
    !isempty(path) && isfile(path) && return true
    isfile("license.dat") && return true
    for ver in ("14_5", "14_4", "14_3", "14_2", "14_1", "14_0", "13_5")
        isfile(joinpath("/opt", "hexaly_$(ver)", "license.dat")) && return true
    end
    return false
end

"""
    raw_optimizer()

Create a new `HexalyOptimizer` instance backed by the C ABI.
"""
raw_optimizer() = HexalyOptimizer()

include("MOI/wrapper.jl")
include("MOI/parse.jl")
include("MOI/wrapper_variables.jl")
include("MOI/wrapper_constraints.jl")
include("MOI/wrapper_constraints_singlevar.jl")
include("MOI/wrapper_constraints_linear.jl")
include("MOI/wrapper_constraints_cp.jl")
include("MOI/list.jl")
include("MOI/sum_distances_objective.jl")

end # module Hexaly
