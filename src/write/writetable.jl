# Writing tables: `writetable!` into a sheet, `writetable` to a new file.
#
# Signatures follow XLSX.jl 0.13.4 (src/writetable.jl `writetable!`, `writetable` and its
# sheet forms; src/tables_interface.jl the Tables.jl forms), MIT License, Copyright (c)
# 2018-2026 Felipe Noronha Tavares and other contributors. XLSX.jl's Excel-table and layout
# keywords (`as_table`, `table_name`, `table_style`, `totals`, `column_widths`,
# `column_formats`, `freeze_header`) belong to later phases (formatting, database ranges).

"""
    writetable!(sheet, data, columnnames; anchor_cell="A1", write_columnnames=true)
    writetable!(sheet, table; anchor_cell="A1", write_columnnames=true)

Write a table into `sheet`, with its column names as a header row (unless
`write_columnnames=false`) and its top-left cell at `anchor_cell`. `data` is a vector of
columns and `columnnames` their names; or `table` is any Tables.jl table.
"""
function writetable!(ws::Worksheet, data, columnnames; anchor_cell::Union{AbstractString,CellRef} = CellRef("A1"),
                     write_columnnames::Bool = true)
    _require_writable(ws, "write a table")
    anchor = anchor_cell isa CellRef ? anchor_cell : CellRef(String(anchor_cell))
    nrows = SheetCore._check_table_shape(data, columnnames)
    r0, c0 = row_number(anchor), column_number(anchor)
    last_row = r0 + nrows - (write_columnnames ? 0 : 1)
    last_col = c0 + length(data) - 1
    (last_row <= SheetCore.MAX_ROWS && last_col <= SheetCore.MAX_COLS) ||
        throw(ODSError("The table doesn't fit in the sheet from $(anchor): it would end at row $last_row, column $last_col."))
    if write_columnnames
        for (j, name) in enumerate(columnnames)
            _set_cell!(ws, r0, c0 + j - 1, string(name))
        end
        r0 += 1
    end
    for (j, col) in enumerate(data)
        _write_column!(ws, col, r0, c0 + j - 1)
    end
    return nothing
end

# A function barrier: the column's element type is known inside.
function _write_column!(ws::Worksheet, col, r0::Int, c::Int)
    for (i, v) in enumerate(col)
        _set_cell!(ws, r0 + i - 1, c, v)
    end
end
writetable!(ws::Worksheet, table; kw...) = writetable!(ws, SheetCore._table_to_arrays(table)...; kw...)

"""
    writetable(filename, data, columnnames; overwrite=false, sheetname="", anchor_cell="A1", streaming=false)
    writetable(filename, table; overwrite=false, sheetname="", anchor_cell="A1", streaming=false)
    writetable(filename, "Sheet1" => table1, "Sheet2" => table2, ...; overwrite=false, streaming=false)
    writetable(filename, [(sheetname, data, columnnames), ...]; overwrite=false, streaming=false)
    writetable(filename; overwrite=false, streaming=false, Sheet1=(data, columnnames), ...)

Write tables to a new file (a path or an `IO`), one per sheet, each with a header row.
The format follows the file's extension (`.ods`, `.ots`, `.fods`). An existing file is only
replaced with `overwrite=true`. With `streaming=true`, rows are written as they are produced,
in bounded memory ([`streamods`](@ref)); `anchor_cell` is then not available.
`display_text=false` leaves out the display text of number, date, time and boolean cells
(smaller files, faster writes; see [`writeods`](@ref)).
"""
function writetable(filename::Union{AbstractString,IO}, data, columnnames; overwrite::Bool = false,
                    sheetname::AbstractString = "", anchor_cell::Union{AbstractString,CellRef} = CellRef("A1"),
                    streaming::Bool = false, display_text::Bool = true)
    return _write_sheets(filename, [(String(sheetname), data, columnnames)]; overwrite, streaming, anchor_cell, display_text)
end

function writetable(filename::Union{AbstractString,IO}, x; overwrite::Bool = false, sheetname::AbstractString = "",
                    anchor_cell::Union{AbstractString,CellRef} = CellRef("A1"), streaming::Bool = false,
                    display_text::Bool = true)
    if SheetCore._is_sheet_spec_vector(x)
        return _write_sheets(filename, SheetCore._normalize_sheet_specs(x); overwrite, streaming, display_text)
    end
    data, names = SheetCore._table_to_arrays(x)
    return _write_sheets(filename, [(String(sheetname), data, names)]; overwrite, streaming, anchor_cell, display_text)
end

function writetable(filename::Union{AbstractString,IO}, tables::Pair...; overwrite::Bool = false, streaming::Bool = false,
                    display_text::Bool = true)
    specs = Tuple{String,Vector{Any},Vector{Any}}[]
    for p in tables
        data, names = SheetCore._table_to_arrays(p.second)
        push!(specs, (SheetCore._sheetname_string(p.first), Any[c for c in data], Any[n for n in names]))
    end
    return _write_sheets(filename, specs; overwrite, streaming, display_text)
end
writetable(filename::Union{AbstractString,IO}, tables::AbstractVector{<:Pair}; kw...) = writetable(filename, tables...; kw...)

function writetable(filename::Union{AbstractString,IO}; overwrite::Bool = false, streaming::Bool = false,
                    display_text::Bool = true, kw...)
    isempty(kw) && throw(ODSError("No tables to write: give them as `sheetname = (data, columnnames)`."))
    specs = Tuple{String,Any,Any}[]
    for (name, spec) in kw
        (spec isa Tuple && length(spec) == 2) || throw(ODSError(
            "Keyword `$name` must be a `(data, columnnames)` tuple, got `$(typeof(spec))`. To write a Tables.jl table, use `writetable(filename, :$name => table)`."))
        push!(specs, (String(name), spec[1], spec[2]))
    end
    return _write_sheets(filename, specs; overwrite, streaming, display_text)
end

function _write_sheets(filename, specs; overwrite::Bool, streaming::Bool, anchor_cell = CellRef("A1"), display_text::Bool = true)
    _check_overwrite(filename, overwrite)
    if streaming
        (anchor_cell == CellRef("A1") || anchor_cell == "A1") ||
            throw(ODSError("`anchor_cell` can't be used with `streaming=true`: streamed sheets start at A1."))
        streamods(filename; overwrite, display_text) do s
            for (name, data, names) in specs
                nrows = SheetCore._check_table_shape(data, names)
                sh = addsheet!(s, name; columns = names)
                row = Vector{Any}(undef, length(data))
                for i in 1:nrows
                    for j in eachindex(data)
                        row[j] = data[j][i]
                    end
                    writerow!(sh, row)
                end
            end
        end
        return filename isa AbstractString ? abspath(filename) : nothing
    end
    xf = newods(isempty(specs[1][1]) ? "" : specs[1][1])
    for (k, (name, data, names)) in enumerate(specs)
        ws = k == 1 ? xf[1] : addsheet!(xf, name)
        writetable!(ws, data, names; anchor_cell = k == 1 ? anchor_cell : CellRef("A1"))
    end
    return writeods(filename, xf; overwrite, display_text)
end
