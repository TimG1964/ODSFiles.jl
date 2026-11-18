# Colours given by users: a hex value, a Colors.jl colour name, or a Colors.jl `Colorant`,
# normalised to "AARRGGBB". Each back end writes that in its own form: XLSX as `rgb`
# attributes, ODF as `#rrggbb` (as in `fo:background-color="#ffff00"`, F-013).
#
# Adapted from XLSX.jl 0.13.4 (src/xlsx-colors.jl: `get_colorant`, `get_color`),
# MIT License, Copyright (c) 2018-2026 Felipe Noronha Tavares and other contributors.
# See records/provenance.md. Changes from XLSX.jl:
#   - XLSXError → SheetCoreError; the error message no longer offers theme colours, which
#     are Excel's (XLSX.jl keeps its `SchemeColor` handling on its side)
#   - new: `odf_color` and `parse_odf_color`

# Check if a string is a valid named color in Colors.jl and convert to "FFRRGGBB" if it is.
get_colorant(color_symb::Symbol) = get_colorant(String(color_symb))
function get_colorant(color_string::String)
    try
        c = parse(Colors.Colorant, color_string)
        rgb = Colors.hex(c, :RRGGBB)
        return "FF" * rgb
    catch e
        e isa ArgumentError || rethrow()   # Colors.jl's error for an unrecognised color
        return nothing
    end
end

"""
    get_color(c) -> String

A colour as `"AARRGGBB"`, from a hex string (`"FF0000"`, `"#FF0000"` or `"FFFF0000"`),
a Colors.jl colour name as a `String` or `Symbol`, or a Colors.jl `Colorant`.
"""
get_color(s::Symbol)::String = get_color(String(s))
function get_color(str::AbstractString)::String
    h = lstrip(str, '#')
    occursin(r"^[0-9A-F]{8}$"i, h) && return uppercase(h)          # AARRGGBB
    occursin(r"^[0-9A-F]{6}$"i, h) && return "FF" * uppercase(h)   # RRGGBB, opaque
    s = replace(lowercase(str), "grey" => "gray")
    c = get_colorant(s)
    isnothing(c) && throw(SheetCoreError(
        "Invalid color specified: $str. Give a color name from Colors.jl, a hex " *
        "color as RRGGBB or AARRGGBB (with or without a leading #), or a Colors.jl `Colorant`."))
    return c
end
get_color(c::Colors.Colorant)::String = uppercase(Colors.hex(c, :AARRGGBB))

"""
    odf_color(c) -> String

A colour in ODF's form, `#rrggbb` in lower case (ODF colours have no transparency, so an
alpha channel is dropped). Takes anything [`get_color`](@ref) does.
"""
odf_color(c)::String = "#" * lowercase(get_color(c)[3:8])

"""
    parse_odf_color(s) -> Union{String,Nothing}

An ODF colour attribute (`#rrggbb`) as `"FFRRGGBB"`, or `nothing` for `transparent` and
other values that are not a colour.
"""
function parse_odf_color(s::AbstractString)::Union{String,Nothing}
    occursin(r"^#[0-9a-fA-F]{6}$", s) || return nothing
    return "FF" * uppercase(s[2:7])
end
