# Text widths for autofitting columns: the width of each printable ASCII character as a
# fraction of the font size, for a few common fonts, and the width of a text from them.
#
# Adapted from XLSX.jl 0.13.4 (src/cellformats/autofit.jl, the font-independent parts,
# and src/data/charwidths.tsv, copied unchanged to core/data/),
# MIT License, Copyright (c) 2018-2026 Felipe Noronha Tavares and other contributors.
# See records/provenance.md. Changes from XLSX.jl:
#   - left out: `_style_font` and `autofitColumns`, which read XLSX styles and set widths
#   - XLSXError → SheetCoreError
#
# The widths were measured from Excel 365 (Windows, 144 dpi). Turning a text width into a
# column width is the back end's job: Excel counts columns in widths of the default
# font's widest digit (plus `_AUTOFIT_PADDING`), while ODF gives column widths as lengths.
# How LibreOffice's optimal width compares is Q-010.

const _CHAR_WIDTHS_PATH = joinpath(@__DIR__, "data", "charwidths.tsv")
include_dependency(_CHAR_WIDTHS_PATH)

function _read_char_widths(path::AbstractString)::Dict{Tuple{String,Bool},Vector{Float64}}
    widths = Dict{Tuple{String,Bool},Vector{Float64}}()
    for line in eachline(path)
        startswith(line, '#') && continue
        font, bold, ems = split(line, '\t')
        widths[(lowercase(font), bold == "true")] = parse.(Float64, split(ems))
    end
    return widths
end

const _CHAR_WIDTHS = _read_char_widths(_CHAR_WIDTHS_PATH)

# The room Excel's autofit leaves beyond the text, in digit widths (measured).
const _AUTOFIT_PADDING = 0.29

# The character widths of a font: its own, those of the longest family name it begins
# with (Calibri's for "Calibri Light"), or else Calibri's.
function _font_widths(name::AbstractString, bold::Bool)::Vector{Float64}
    key = lowercase(name)
    best, bestlen = _CHAR_WIDTHS[("calibri", bold)], 0
    for ((font, b), w) in _CHAR_WIDTHS
        b == bold && startswith(key, font) && length(font) > bestlen && ((best, bestlen) = (w, length(font)))
    end
    return best
end

# A character's width as a fraction of the font size. Characters outside the table are
# taken as wide as `n`, or as two digits if they take two columns (as CJK ones do).
function _char_em(widths::Vector{Float64}, c::Char)::Float64
    ' ' <= c <= '~' && return widths[Int(c) - 31]
    tw = textwidth(c)
    tw == 0 && return 0.0
    return tw >= 2 ? 2 * widths[Int('0') - 31] : widths[Int('n') - 31]
end

# The width of the widest line of `text`, as a fraction of the font size.
_text_em(widths::Vector{Float64}, text::AbstractString) =
    maximum(line -> sum(c -> _char_em(widths, c), line; init=0.0), eachsplit(text, '\n'))

"""
    text_width_points(text, font = "Calibri", size = 11.0; bold = false) -> Float64

The width of the widest line of `text` in points, in the given font. Fonts without a
table of their own are measured as the nearest one by name, or as Calibri.
"""
text_width_points(text::AbstractString, font::AbstractString = "Calibri", size::Real = 11.0;
                  bold::Bool = false)::Float64 =
    _text_em(_font_widths(font, bold), text) * Float64(size)

# The columns `cols` names, or `nothing` for all.
_autofit_columns(::Colon) = nothing
_autofit_columns(c::Integer) = Set(Int(c))
_autofit_columns(cs::AbstractVector{<:Integer}) = Set{Int}(cs)
function _autofit_columns(s::AbstractString)
    cols = Set{Int}()
    for part in split(s, ',')
        part = strip(part)
        if occursin(':', part)
            r = ColumnRange(part)
            union!(cols, r.start:r.stop)
        else
            is_valid_column_name(part) || throw(SheetCoreError("Invalid column: `$part`. Give columns as letters (`\"B\"`, `\"B:D\"`), numbers or `:`."))
            push!(cols, decode_column_number(part))
        end
    end
    return cols
end
_autofit_columns(cols) = throw(SheetCoreError("Columns are given as `:`, a number, a range or vector of numbers, or letters such as `\"B:D\"`, not `$(typeof(cols))`."))
