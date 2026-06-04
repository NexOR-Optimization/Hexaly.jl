# Copyright (c) 2025 Benoît Legat and contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

# !!! note
#
#     Run this script as `julia --project=. gen.jl`
#
#     The Hexaly headers ship with the Linux/Windows/macOS installer (e.g.
#     `Hexaly_14_5_*.run`). Copy `<install>/include` to `../include` next to
#     this `gen/` directory before running. `entrypoint.h` is the public C
#     ABI — everything `libhexaly145.so` exports lives here.
#
#     `entrypoint.h` is C++-clean but uses bare `enum`/`struct` tags in a
#     handful of places (e.g. `hxloggermode`, `hxmodellistener`), which is
#     invalid as pure C. We patch those declarations into `typedef enum`/
#     `typedef struct` forms before handing the header to `Clang.Generators`.

using Clang.Generators

const hexaly_include = joinpath(@__DIR__, "..", "include")

"""
    add_typedefs(src::String) -> String

Rewrite `enum NAME { ... };` and `struct NAME { ... };` into the equivalent
`typedef enum NAME { ... } NAME;` / `typedef struct NAME { ... } NAME;` form,
so bare tag uses elsewhere in the header parse cleanly as C.
"""
function add_typedefs(src::AbstractString)
    out = IOBuffer()
    i = firstindex(src)
    while i <= lastindex(src)
        m = match(r"(enum|struct)\s+(\w+)\s*\{"s, src, i)
        m === nothing && (write(out, SubString(src, i)); break)
        # Copy everything before the match
        write(out, SubString(src, i, prevind(src, m.offset)))
        kind, name = m.captures[1], m.captures[2]
        # Find matching closing brace
        depth, j = 1, m.offset + ncodeunits(m.match)
        while j <= lastindex(src) && depth > 0
            c = src[j]
            depth += (c == '{') - (c == '}')
            j = nextind(src, j)
        end
        body = SubString(src, m.offset, prevind(src, j))  # `kind NAME { ... }`
        # Skip whitespace after `}` to see if there's already a typedef name
        k = j
        while k <= lastindex(src) && isspace(src[k])
            k = nextind(src, k)
        end
        if k <= lastindex(src) && src[k] == ';'
            write(out, "typedef ", body, " ", name, ";")
            i = nextind(src, k)
        else
            write(out, body)
            i = j
        end
    end
    s = String(take!(out))
    # Also patch the bare-tag opaque-pointer typedefs:
    #   `typedef NAME_* X;`  ->  `typedef struct NAME_* X;`
    s = replace(s, r"typedef\s+(\w+_)\s*\*\s*(\w+)\s*;" => s"typedef struct \1* \2;")
    # Inject typedefs/includes the C branch omits (the C++ branch pulls them in
    # via <climits> / "modeler/hxmmembertype.h").
    return replace(s,
        "#include \"symbols.h\"" =>
        "#include \"symbols.h\"\n#include <stddef.h>\ntypedef int hxmmembertype;\n",
    )
end

const tmp_include = mktempdir()
# Mirror the include layout under a temp dir so includes still resolve.
cp(hexaly_include, joinpath(tmp_include, "include"); force=true)
const patched_entrypoint = joinpath(tmp_include, "include", "entrypoint.h")
write(patched_entrypoint, add_typedefs(read(patched_entrypoint, String)))

options = load_options(joinpath(@__DIR__, "generate.toml"))
options["general"]["output_file_path"] =
    joinpath(@__DIR__, "..", "src", "gen", "libhexaly.jl")
options["general"]["prologue_file_path"] = joinpath(@__DIR__, "prologue.jl")
mkpath(dirname(options["general"]["output_file_path"]))

build!(
    create_context(
        [patched_entrypoint],
        vcat(get_default_args(), "-I$(joinpath(tmp_include, "include"))"),
        options,
    ),
)
