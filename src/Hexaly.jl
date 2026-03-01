module Hexaly

import CondaPkg
using PythonCall

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
    Optimizer()

Create a new `HexalyOptimizer` Python object.
"""
Optimizer() = hexaly_optimizer.HexalyOptimizer()

end # module Hexaly
