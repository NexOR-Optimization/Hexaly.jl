module Hexaly

import CondaPkg
using PythonCall
import MathOptInterface as MOI

const hexaly_optimizer = PythonCall.pynew()

function __init__()
    # The `hexaly` pip package is only available from a custom index
    # (https://pip.hexaly.com), which CondaPkg cannot handle natively.
    # We install it on first use via pip in the CondaPkg environment.
    try
        PythonCall.pycopy!(hexaly_optimizer, pyimport("hexaly.optimizer"))
    catch
        @info "Installing Hexaly Python package from pip.hexaly.com..."
        python = CondaPkg.which("python")
        run(`$python -m pip install hexaly --extra-index-url https://pip.hexaly.com -q`)
        PythonCall.pycopy!(hexaly_optimizer, pyimport("hexaly.optimizer"))
    end
end

"""
    version()

Return the Hexaly Optimizer version as a `VersionNumber`.
"""
function version()
    HxVersion = hexaly_optimizer.HxVersion
    major = pyconvert(Int, HxVersion.get_major_version_number())
    minor = pyconvert(Int, HxVersion.get_minor_version_number())
    return VersionNumber(major, minor)
end

"""
    has_license()::Bool

Return `true` if a Hexaly license is available (either via `HX_LICENSE_CONTENT`
or a license file on disk).
"""
function has_license()
    HxVersion = hexaly_optimizer.HxVersion
    content = pyconvert(String, HxVersion.license_content)
    if !isempty(content)
        return true
    end
    path = pyconvert(String, HxVersion.license_path)
    return isfile(path)
end

"""
    raw_optimizer()

Create a new raw `HexalyOptimizer` Python object. This is the low-level
Hexaly Python API. For MOI/JuMP use, prefer [`Optimizer`](@ref).
"""
raw_optimizer() = hexaly_optimizer.HexalyOptimizer()

include("MOI/wrapper.jl")
include("MOI/parse.jl")
include("MOI/wrapper_variables.jl")
include("MOI/wrapper_constraints.jl")
include("MOI/wrapper_constraints_singlevar.jl")
include("MOI/wrapper_constraints_linear.jl")
include("MOI/wrapper_constraints_cp.jl")

end # module Hexaly
