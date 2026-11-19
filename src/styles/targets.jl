# What a formatting setter applies to (phase 4): XLSX.jl's address forms, resolved to blocks
# of cells, whole columns or whole rows on one or more sheets.
#
# The forms are XLSX.jl 0.13.4's (src/cellformat-helpers.jl, `_percell_address_methods`):
# a cell, a range, a column range, a row range, a list of ranges, a defined name, a
# sheet-qualified reference (on a sheet or on the file), `CellRef`/`CellRange`, and
# `(rows, cols)` with integers, ranges, vectors or `:`. Unlike XLSX.jl's, nothing is clipped
# to the used area, and empty cells are formatted (D-033): `"A:C"`, `(ws, :, 2)` and
# `(ws, :)` are whole columns, `"3:5"` and `(ws, 3, :)` whole rows.

"""
    FormatBlock(kind, rows, cols)

A part of a sheet to format: a block of cells (`kind = :cells`), whole columns (`:cols`, with
`cols`) or whole rows (`:rows`, with `rows`).
"""
struct FormatBlock
    kind::Symbol
    rows::UnitRange{Int}
    cols::UnitRange{Int}
end
_cellblock(rows, cols) = FormatBlock(:cells, first(rows):last(rows), first(cols):last(cols))
_colblock(cols) = FormatBlock(:cols, 1:0, first(cols):last(cols))
_rowblock(rows) = FormatBlock(:rows, first(rows):last(rows), 1:0)

const FormatTargets = Vector{Pair{Worksheet,Vector{FormatBlock}}}
_on(ws::Worksheet, blocks::Vector{FormatBlock}) = FormatTargets([ws => blocks])

"""
    format_targets(ws_or_xf, ref...) -> Vector{Pair{Worksheet, Vector{FormatBlock}}}

The parts of the sheets that a formatting setter's address names.
"""
function format_targets end

format_targets(ws::Worksheet, ref::CellRef) = _on(ws, [_cellblock(row_number(ref):row_number(ref), column_number(ref):column_number(ref))])
format_targets(ws::Worksheet, rng::CellRange) =
    _on(ws, [_cellblock(row_number(rng.start):row_number(rng.stop), column_number(rng.start):column_number(rng.stop))])
format_targets(ws::Worksheet, rng::ColumnRange) = _on(ws, [_colblock(rng.start:rng.stop)])
format_targets(ws::Worksheet, rng::RowRange) = _on(ws, [_rowblock(rng.start:rng.stop)])
function format_targets(ws::Worksheet, nc::NonContiguousRange)
    do_sheet_names_match(ws, nc)
    blocks = FormatBlock[]
    for r in nc.rng
        append!(blocks, last(only(format_targets(ws, r))))
    end
    return _on(ws, blocks)
end
format_targets(ws::Worksheet, s::SheetCellRef) = (do_sheet_names_match(ws, s); format_targets(ws, s.cellref))
format_targets(ws::Worksheet, s::SheetCellRange) = (do_sheet_names_match(ws, s); format_targets(ws, s.rng))
format_targets(ws::Worksheet, s::SheetColumnRange) = (do_sheet_names_match(ws, s); format_targets(ws, s.colrng))
format_targets(ws::Worksheet, s::SheetRowRange) = (do_sheet_names_match(ws, s); format_targets(ws, s.rowrng))
format_targets(ws::Worksheet, ref::AbstractString) = _check_targets(ref_chooser(format_targets, ws, ref), ref)

format_targets(xf::ODSFile, s::SheetCellRef) = format_targets(getsheet(xf, s.sheet), s.cellref)
format_targets(xf::ODSFile, s::SheetCellRange) = format_targets(getsheet(xf, s.sheet), s.rng)
format_targets(xf::ODSFile, s::SheetColumnRange) = format_targets(getsheet(xf, s.sheet), s.colrng)
format_targets(xf::ODSFile, s::SheetRowRange) = format_targets(getsheet(xf, s.sheet), s.rowrng)
format_targets(xf::ODSFile, s::NonContiguousRange) = format_targets(getsheet(xf, s.sheet), s)
format_targets(xf::ODSFile, ref::AbstractString) = _check_targets(ref_chooser(format_targets, xf, ref), ref)

# A defined name that is a constant resolves to its value, not to cells.
function _check_targets(t, ref)
    t isa FormatTargets && return t
    throw(ODSError("Can only format cells, but `$ref` is a constant: $(repr(t))."))
end

# The index forms
const _Index = Union{Integer,AbstractVector{<:Integer}}

# Sorted, distinct indices as contiguous runs.
function _index_runs(x::_Index, max::Int, what::AbstractString)
    v = x isa Integer ? [Int(x)] : sort!(unique(Int.(collect(x))))
    isempty(v) && return UnitRange{Int}[]
    (first(v) >= 1 && last(v) <= max) || throw(ODSError("$what $(x) is outside the sheet (1 to $max)."))
    runs = UnitRange{Int}[]
    for i in v
        if !isempty(runs) && last(runs[end]) + 1 == i
            runs[end] = first(runs[end]):i
        else
            push!(runs, i:i)
        end
    end
    return runs
end
_row_runs(x) = _index_runs(x, SheetCore.MAX_ROWS, "Row")
_col_runs(x) = _index_runs(x, SheetCore.MAX_COLS, "Column")

format_targets(ws::Worksheet, ::Colon) = format_targets(ws, :, :)
format_targets(ws::Worksheet, ::Colon, ::Colon) = _on(ws, [_colblock(1:SheetCore.MAX_COLS)])
format_targets(ws::Worksheet, ::Colon, col::_Index) = _on(ws, [_colblock(c) for c in _col_runs(col)])
format_targets(ws::Worksheet, row::_Index, ::Colon) = _on(ws, [_rowblock(r) for r in _row_runs(row)])
format_targets(ws::Worksheet, row::_Index, col::_Index) =
    _on(ws, [_cellblock(r, c) for r in _row_runs(row) for c in _col_runs(col)])

# Whether the targets are one cell (then a setter returns its new style's name).
function _single_cell(t::FormatTargets)
    length(t) == 1 || return nothing
    ws, blocks = only(t)
    (length(blocks) == 1 && blocks[1].kind === :cells && length(blocks[1].rows) == 1 && length(blocks[1].cols) == 1) || return nothing
    return (ws, first(blocks[1].rows), first(blocks[1].cols))
end

# The first cell of the targets (for the uniform setters): the top-left cell of the first block.
function _first_cell(t::FormatTargets)
    isempty(t) && throw(ODSError("No cells to format."))
    ws, blocks = t[1]
    isempty(blocks) && throw(ODSError("No cells to format."))
    b = blocks[1]
    return (ws, b.kind === :cols ? 1 : first(b.rows), b.kind === :rows ? 1 : first(b.cols))
end

#
# A single cell, for the getters
#

"""
    format_cell(ws_or_xf, ref...) -> (ws, row, col)

The one cell a formatting getter's address names: a cell (`"A1"`, `CellRef`, `(row, col)`),
a sheet-qualified cell, or a defined name for one cell.
"""
function format_cell(x::Union{Worksheet,ODSFile}, ref...)
    t = format_targets(x, ref...)
    c = _single_cell(t)
    c === nothing && throw(ODSError("A formatting getter takes a single cell, not $(join(repr.(ref), ", "))."))
    return c
end
