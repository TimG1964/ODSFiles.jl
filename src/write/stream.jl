# Streaming a new file row by row: `streamods`, `addsheet!(::StreamWriter, …)`, `writerow!`,
# `writerows!`. content.xml is deflated into the package as rows are written, so memory is
# bounded by the zip writer's buffer, however many rows there are.
#
# The API follows XLSX.jl 0.13.4 (src/streamwrite.jl `streamxlsx`, `StreamWriter`,
# `StreamSheet`, `addsheet!`, `writerow!`, `writerows!`), MIT License, Copyright (c)
# 2018-2026 Felipe Noronha Tavares and other contributors. All sheets share one content.xml
# in ODS, so a sheet is finished when the next one is added.

# The rows not yet passed to the zip, and the zip's content.xml entry, shared by the writer
# and its sheets. A flush hands the bytes to the zip (`take!`) and wraps the same memory in
# a new buffer, so it is not allocated again for each chunk (as XLSX.jl's writer does).
mutable struct _StreamBuffer
    io::IOBuffer
    zip::IO
end

function _flush!(b::_StreamBuffer)
    v = take!(b.io)
    write(b.zip, v)
    b.io = IOBuffer(v; read = false, write = true, truncate = true)
    return nothing
end

"""
    StreamSheet

A sheet being written by [`streamods`](@ref). Write rows to it in order with
[`writerow!`](@ref) and [`writerows!`](@ref).
"""
mutable struct StreamSheet
    name::String
    buf::_StreamBuffer
    styles::StyleIndex
    row::Int               # the last row written
    isopen::Bool
    display::Bool          # display text in typed cells (D-029)
end

"""
    StreamWriter

A file being written by [`streamods`](@ref). Add sheets to it with `addsheet!`.
"""
mutable struct StreamWriter
    buf::_StreamBuffer
    styles::StyleIndex
    names::Vector{String}
    current::Union{Nothing,StreamSheet}
    display::Bool
end

Base.show(io::IO, s::StreamWriter) = print(io, "StreamWriter(", length(s.names), " sheets)")
Base.show(io::IO, sh::StreamSheet) = print(io, "StreamSheet(\"", sh.name, "\", ", sh.row, " rows written", sh.isopen ? ")" : ", closed)")

# The typed styles are declared before the body (they come before it in content.xml), so
# streamed files always carry all four.
function _stream_styles()
    st = StyleIndex()
    foreach(k -> typed_style_id(st, k), (:date, :datetime, :time, :boolean))
    return st
end

"""
    streamods(f, dest; overwrite=false, version="1.4")

Write a new file to `dest` (a path or an `IO`) row by row, in bounded memory. `f` gets a
[`StreamWriter`](@ref): add sheets with `addsheet!(s, name; columns)` (a header row) or
`addsheet!(s, name, table)` (a Tables.jl table, header and rows), and write rows with
[`writerow!`](@ref) and [`writerows!`](@ref). The format follows the extension (`.ods`,
`.ots`; flat `.fods` is not streamed). `display_text=false` leaves out the display text of
number, date, time and boolean cells, as in [`writeods`](@ref).

```julia
streamods("big.ods") do s
    sh = addsheet!(s, "data"; columns = ["n", "square"])
    for n in 1:1_000_000
        writerow!(sh, (n, n^2))
    end
end
```
"""
function streamods(f::Function, dest::Union{AbstractString,IO}; overwrite::Bool = false,
                   version::AbstractString = DEFAULT_ODF_VERSION, display_text::Bool = true)
    _check_overwrite(dest, overwrite)
    _check_version(version)
    fmt = dest isa AbstractString ? lowercase(splitext(dest)[2]) : ".ods"
    fmt == ".fods" && throw(ODSError("Flat XML (.fods) files can't be streamed; write them with `writeods`."))
    mt = fmt == ".ots" ? MEDIATYPE_OTS : MEDIATYPE_ODS
    styles = _stream_styles()
    others = [PackagePart("styles.xml", new_styles_xml(version)), PackagePart("meta.xml", new_meta_xml(version))]
    manifest = manifest_xml(vcat([PackagePart("content.xml", "")], others), mt, version)
    produce(w) = begin
        ZipArchives.zip_newfile(w, "content.xml"; compress = true)
        print(w, _XMLDECL, "<office:document-content", _NS_DECL, " office:version=\"", version, "\">",
              "<office:automatic-styles>", typed_styles_xml(styles), "</office:automatic-styles>",
              "<office:body><office:spreadsheet>")
        sw = StreamWriter(_StreamBuffer(IOBuffer(), w), styles, String[], nothing, display_text)
        f(sw)
        isempty(sw.names) && addsheet!(sw, "Sheet1")
        _close_sheet!(sw)
        _flush!(sw.buf)
        print(w, "</office:spreadsheet></office:body></office:document-content>")
        ZipArchives.zip_commitfile(w)
        _append_parts!(w, others, manifest)
    end
    if dest isa AbstractString
        open(io -> _write_mimetype_zip(io, mt), dest, "w")
        ZipArchives.zip_append_archive(produce, dest)
        return abspath(dest)
    else
        buf = IOBuffer()
        _write_mimetype_zip(buf, mt)
        ZipArchives.zip_append_archive(produce, buf)
        write(dest, take!(buf))
        return nothing
    end
end

function _close_sheet!(s::StreamWriter)
    sh = s.current
    (sh === nothing || !sh.isopen) && return
    sh.row == 0 && print(s.buf.io, _EMPTY_ROW)
    print(s.buf.io, "</table:table>")
    sh.isopen = false
    return
end

"""
    addsheet!(s::StreamWriter, name=""; columns=nothing) -> StreamSheet
    addsheet!(s::StreamWriter, name, table) -> StreamSheet

Start the next sheet of a streamed file, finishing the one before. `columns` writes a header
row; a Tables.jl `table` writes its header and all its rows.
"""
function addsheet!(s::StreamWriter, name::AbstractString = ""; columns = nothing)
    _close_sheet!(s)
    if isempty(name)
        n = length(s.names) + 1
        while any(x -> _same_sheetname(x, "Sheet$n"), s.names); n += 1; end
        name = "Sheet$n"
    end
    for c in _BAD_SHEETNAME_CHARS
        occursin(c, name) && throw(ODSError("The sheet name `$name` holds `$c`, which LibreOffice does not allow in sheet names."))
    end
    any(x -> _same_sheetname(x, name), s.names) && throw(ODSError("There is already a sheet named `$name`."))
    push!(s.names, String(name))
    io = s.buf.io
    print(io, "<table:table table:name=\""); _escape_attr(io, name); print(io, "\">")
    # the width is not known in advance; a wide column definition costs nothing (F-028)
    print(io, "<table:table-column table:number-columns-repeated=\"", SheetCore.MAX_COLS, "\"/>")
    sh = StreamSheet(String(name), s.buf, s.styles, 0, true, s.display)
    s.current = sh
    columns === nothing || writerow!(sh, [string(c) for c in columns])
    return sh
end

function addsheet!(s::StreamWriter, name::AbstractString, table)
    sh = addsheet!(s, name; columns = collect(String, string.(Tables.columnnames(Tables.columns(table)))))
    writerows!(sh, table)
    return sh
end

"""
    writerow!(sh::StreamSheet, row)

Write the next row of a streamed sheet: a tuple, `NamedTuple` or vector of values (`missing`
or `nothing` leave a cell empty).
"""
function writerow!(sh::StreamSheet, row::Union{Tuple,NamedTuple,AbstractVector})
    sh.isopen || throw(ODSError("Can't write to sheet `$(sh.name)`: it is closed. A streamed sheet is closed when the next sheet is added, and when `streamods` returns."))
    length(row) > SheetCore.MAX_COLS && throw(ODSError("A row of $(length(row)) values is wider than a sheet ($(SheetCore.MAX_COLS) columns)."))
    sh.row >= SheetCore.MAX_ROWS && throw(ODSError("A sheet holds at most $(SheetCore.MAX_ROWS) rows."))
    io = sh.buf.io
    print(io, "<table:table-row>")
    gap = 0
    any = false
    for v in values(row)
        if v === missing || v === nothing
            gap += 1
            continue
        end
        gap > 0 && write_cell(io, nothing, sh.styles; repeat = gap)
        gap = 0
        _stream_cell!(io, sh, v)
        any = true
    end
    any || print(io, "<table:table-cell/>")
    print(io, "</table:table-row>")
    sh.row += 1
    position(io) > (1 << 20) && _flush!(sh.buf)
    return nothing
end

# A function barrier: specialised on the value's type, the cell is encoded and written
# without boxing its stored form (phase 3).
function _stream_cell!(io::IOBuffer, sh::StreamSheet, v)
    d = encode_value(v, choose_style(sh.styles, 0, v))
    d === nothing || write_cell(io, d, sh.styles; display = sh.display)
    return nothing
end
writerow!(::StreamSheet, row) = throw(ODSError("`writerow!` takes a row as a tuple, `NamedTuple` or vector, got `$(typeof(row))`."))

"""
    writerows!(sh::StreamSheet, table)

Write every row of a Tables.jl table (without its header) to a streamed sheet.
"""
function writerows!(sh::StreamSheet, table)
    Tables.istable(table) || throw(ODSError("$(typeof(table)) is not a Tables.jl table."))
    for r in Tables.rows(table)
        names = Tables.columnnames(r)
        writerow!(sh, [Tables.getcolumn(r, n) for n in names])
    end
    return nothing
end
