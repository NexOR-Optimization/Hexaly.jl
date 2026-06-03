# Copyright (c) 2025 Benoît Legat and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.
#
# Locate `libhexaly145.so` (.dylib / .dll on macOS / Windows) and emit
# `deps.jl` with `const libhexaly = "..."`. Mirrors the layout used by
# `Gurobi.jl/deps/build.jl`.

using Libdl

const DEPS_FILE = joinpath(@__DIR__, "deps.jl")

if isfile(DEPS_FILE)
    rm(DEPS_FILE)
end

if Sys.WORD_SIZE != 64
    error("Hexaly.jl does not support 32-bit Julia. Please install a 64-bit Julia.")
end

function write_depsfile(path)
    open(DEPS_FILE, "w") do io
        println(io, "const libhexaly = \"$(escape_string(path))\"")
    end
    return
end

# Supported `libhexaly` aliases, newest first. The number is the same as in
# `hx_version_code()` (major*10 + minor), so `145` is Hexaly 14.5.
const ALIASES = ["hexaly145", "hexaly144", "hexaly143", "hexaly142",
                 "hexaly141", "hexaly140", "hexaly135"]

# Versioned directories the `.run` installer creates on Linux (and the
# matching `/Library/...` / `C:\Program Files\...` defaults elsewhere).
const VERSION_DIRS = ["hexaly_14_5", "hexaly_14_4", "hexaly_14_3", "hexaly_14_2",
                      "hexaly_14_1", "hexaly_14_0", "hexaly_13_5"]

function _candidate_paths()
    paths = String[]
    root = get(ENV, "HEXALY_HOME", nothing)
    for a in ALIASES
        if root !== nothing
            if Sys.isunix()
                push!(paths, joinpath(root, "bin", "lib$a.so"))
                push!(paths, joinpath(root, "lib", "lib$a.so"))
                push!(paths, joinpath(root, "lib$a.so"))  # bare layout
            end
            if Sys.iswindows()
                push!(paths, joinpath(root, "bin", "$a.$(Libdl.dlext)"))
                push!(paths, joinpath(root, "$a.$(Libdl.dlext)"))
            end
            if Sys.isapple()
                push!(paths, joinpath(root, "bin", "lib$a.dylib"))
                push!(paths, joinpath(root, "lib", "lib$a.dylib"))
                push!(paths, joinpath(root, "lib$a.dylib"))
            end
        end
        # Standard `.run` installer locations.
        for v in VERSION_DIRS
            if Sys.isunix()
                push!(paths, joinpath("/opt", v, "bin", "lib$a.so"))
            end
            if Sys.isapple()
                push!(paths, joinpath("/Library", v, "bin", "lib$a.dylib"))
            end
            if Sys.iswindows()
                push!(paths, joinpath("C:\\Program Files", v, "bin", "$a.$(Libdl.dlext)"))
            end
        end
        # Bare names — let dlopen search the system loader paths.
        push!(paths, "lib$a.$(Libdl.dlext)")
        push!(paths, "lib$a")
    end
    return paths
end

function _try_local_install()
    for l in _candidate_paths()
        if Libdl.dlopen_e(l) != C_NULL
            write_depsfile(l)
            return true
        end
    end
    return false
end

function _print_HEXALY_HOME_help()
    println("""
    You should set the `HEXALY_HOME` environment variable to point to the
    install location, then re-run `Pkg.build("Hexaly")`. Examples:

    ```
    # On Linux, this might be:
    ENV["HEXALY_HOME"] = "/opt/hexaly_14_5"

    # On macOS:
    ENV["HEXALY_HOME"] = "/Library/hexaly_14_5"

    # On Windows:
    ENV["HEXALY_HOME"] = "C:\\\\Program Files\\\\hexaly_14_5"

    import Pkg
    Pkg.build("Hexaly")
    ```

    The `HEXALY_HOME` directory should contain a `bin/` subdirectory with
    `libhexaly145.so` / `libhexaly145.dylib` / `hexaly145.dll`.
    """)
end

function diagnose_hexaly_install()
    println("""

    **Unable to locate Hexaly installation. Running some common diagnostics.**

    Hexaly.jl looks for any of the following library versions:
    """)
    println.(" - ", ALIASES)
    println("""

    Did you download and install Hexaly Optimizer from hexaly.com?
    Installing Hexaly.jl via the Julia package manager is _not_ sufficient!
    """)
    if haskey(ENV, "HEXALY_HOME")
        root = ENV["HEXALY_HOME"]
        dir = joinpath(root, Sys.iswindows() ? "bin" : "bin")
        println("""
        Found HEXALY_HOME = $root

        Looking for the Hexaly shared library in:
            $dir

        Contents:
        """)
        try
            for file in readdir(dir)
                println(" - ", joinpath(dir, file))
            end
            println("""

            We were looking for (but could not find) a file named like
            `libhexaly145.so`, `libhexaly145.dylib`, or `hexaly145.dll`.
            """)
        catch ex
            if ex isa SystemError
                println("""
                Could not read `$dir`. Is `HEXALY_HOME` correct?
                """)
            else
                rethrow(ex)
            end
        end
        _print_HEXALY_HOME_help()
    else
        _print_HEXALY_HOME_help()
    end
    return error("""
    Unable to locate Hexaly installation. Set `HEXALY_HOME` and re-run
    `Pkg.build("Hexaly")`.
    """)
end

if haskey(ENV, "HEXALY_JL_SKIP_LIB_CHECK")
    # Emit a placeholder so the package is loadable (e.g. for docs / CI
    # without the solver) but not usable.
    write_depsfile("__skipped_installation__")
elseif get(ENV, "JULIA_REGISTRYCI_AUTOMERGE", "false") == "true"
    write_depsfile("__skipped_installation__")
else
    if !_try_local_install()
        diagnose_hexaly_install()
    end
end
