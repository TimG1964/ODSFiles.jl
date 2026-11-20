# The workbook and its sheets (D-020): `ODSFile`, `Worksheet`, `openods`/`readods`,
# sheet lookup, defined names (named ranges and expressions) and `show`.
#
# Adapted from XLSX.jl 0.13.4 (src/read.jl `openxlsx`/`readxlsx`/`parse_file_mode`,
# src/workbook.jl sheet lookup and `show`), MIT License, Copyright (c) 2018-2026 Felipe
# Noronha Tavares and other contributors. Changes: the ODF container and sheet index
# replace the OOXML parts; only mode "r" is available in phase 1 (D-019).

"""
    DefinedName

A named range (`table:named-range`) or named expression (`table:named-expression`).
`scope` is the sheet a local name belongs to, or `nothing` for a workbook name.
`range` is the `table:cell-range-address`, `expression` the `table:expression`.
"""
struct DefinedName
    name::String
    scope::Union{Nothing,String}
    range::Union{Nothing,String}
    expression::Union{Nothing,String}
    base::Union{Nothing,String}
end

"""
    Worksheet

A sheet of an [`ODSFile`](@ref). Index it like a matrix of values (`sheet["A1"]`,
`sheet["A1:B3"]`, `sheet[2, 1]`, `sheet[:]`); see [`getdata`](@ref).
"""
mutable struct Worksheet
    package::Any                      # the ODSFile (typed in accessors; circular)
    name::String
    index::Int
    entry::Union{Nothing,SheetEntry{String}}   # nothing: a sheet made by ODSFiles
    visible::Bool
    store::Union{Nothing,SheetStore}
    localnames::Union{Nothing,Vector{DefinedName}}
    lock::ReentrantLock
    dirty::Dict{Int,Vector{Int}}      # edited cells of a sheet read from a file: row → columns
    formats::Union{Nothing,SheetFormats}   # read on first use by formatting (phase 4)
    rowmap::Union{Nothing,IndexMap}   # rows and columns inserted or deleted since the sheet was read
    colmap::Union{Nothing,IndexMap}   #   (phase 5: original → current lines), or nothing
    opstart::Int                      # operations already in its text (a copy's: those before the copy)
    copied::Bool                      # a copy made by `copysheet!`: its text is its own, not the file's
end

Worksheet(xf, name, index, entry, visible, store, localnames, lock) =
    Worksheet(xf, name, index, entry, visible, store, localnames, lock, Dict{Int,Vector{Int}}(), nothing, nothing, nothing, 0, false)

# Whether the sheet was made by ODSFiles (so it is written whole), not read from the file.
isnewsheet(ws::Worksheet) = ws.entry === nothing

"""
    ODSFile

An opened spreadsheet, as [`openods`](@ref) and [`readods`](@ref) return it. Index it by
sheet name or number (`xf["Sheet1"]`, `xf[1]`), or with a sheet-qualified reference or a
defined name (`xf["Sheet1.A1:B2"]`, `xf["Sheet1!A1"]`, `xf["myrange"]`).
"""
mutable struct ODSFile
    source::String                    # the file path, "IOBuffer"/"IO", or "blank.ods" for a new file
    container::Union{Nothing,ODFContainer}   # nothing: a new file
    content::String                   # content.xml, or the whole flat document ("" if new)
    version::Union{Nothing,String}    # office:version
    styles::StyleIndex
    sheets::Vector{Worksheet}
    names::Vector{DefinedName}
    null_date::Dates.Date             # table:null-date, for day numbers (formulas, formats)
    use_cache::Bool
    writable::Bool                    # opened with mode "w" or "rw", or made by newods
    source_io::Union{Nothing,IO}      # the IO a file was opened from, for saveods
    scanner::Union{Nothing,BodyScanner}   # the sheet index, found as far as needed (phase 3)
    lock::ReentrantLock
    ops::Vector{Any}                  # structural edits since the file was read, in order (phase 5: `RefOp`s)
    gone::Vector{Any}                 # sheets read from the file and deleted since (phase 5)
    extras::Vector{Any}               # database ranges added by sheet copies: (XML, operations already applied)
    objcopies::Vector{Pair{String,String}}   # embedded objects duplicated by sheet copies ("Object 1" => "Object 3")
end

ODSFile(source, container, content, version, styles, sheets, names, null_date, use_cache) =
    ODSFile(source, container, content, version, styles, sheets, names, null_date, use_cache, false, nothing,
            nothing, ReentrantLock(), Any[], Any[], Any[], Pair{String,String}[])
ODSFile(source, container, content, version, styles, sheets, names, null_date, use_cache, writable, source_io) =
    ODSFile(source, container, content, version, styles, sheets, names, null_date, use_cache, writable, source_io,
            nothing, ReentrantLock(), Any[], Any[], Any[], Pair{String,String}[])

#
# The sheet index is built as far as it is needed: `xf["Sheet1"]` or `xf[1]` finds the first
# sheet without scanning past it, while `sheetnames`, `sheetcount` and the workbook's names
# (which follow the sheets in content.xml) scan to the end. Each step skips a whole sheet
# (XML.jl `skip_element!`).
#

# Index one more body item; false when the end is reached.
function _index_next!(xf::ODSFile)
    s = xf.scanner
    (s === nothing || s.done) && return false
    lock(xf.lock) do
        while (item = next_body_item!(s)) !== nothing
            kind, node, name = item
            if kind === :table
                e = SheetEntry(name, length(xf.sheets) + 1, node)
                push!(xf.sheets, Worksheet(xf, e.name, e.index, e, _sheet_visible(e, xf.styles), nothing, nothing, ReentrantLock()))
                return true
            elseif kind === :names
                append!(xf.names, _read_names(node, nothing))
            else
                xf.null_date = _null_date(node)
            end
        end
        return false
    end
end

_index_all!(xf::ODSFile) = (while _index_next!(xf) end; xf)
_sheets(xf::ODSFile) = (_index_all!(xf); xf.sheets)
_wb_names(xf::ODSFile) = (_index_all!(xf); xf.names)

isnewfile(xf::ODSFile) = xf.container === nothing

@inline get_odsfile(ws::Worksheet)::ODSFile = ws.package
@inline is_cache_enabled(ws::Worksheet) = get_odsfile(ws).use_cache
@inline is_cache_enabled(xf::ODSFile) = xf.use_cache

#
# Opening
#

# (read, write) for a file mode, as XLSX.jl's `parse_file_mode`.
function _parse_file_mode(mode::AbstractString)
    m = lowercase(mode)
    m == "r" && return (true, false)
    m == "w" && return (false, true)
    (m == "rw" || m == "wr") && return (true, true)
    throw(ODSError("Couldn't parse file mode $mode."))
end

"""
    openods(source; mode="r", enable_cache=true) -> ODSFile
    openods(f::Function, source; mode="r", enable_cache=true)

Open an OpenDocument spreadsheet (`.ods`, `.fods` or `.ots`, detected from the content)
from a file path or an `IO`. The do-block form passes the file to `f` and returns what `f`
returns.

`content.xml` is read once, and the sheets are located without being parsed.
- `enable_cache=true`: a sheet is parsed into memory the first time one of its cells is
  read; later reads use that copy.
- `enable_cache=false`: every read scans the sheet again, keeping nothing, and stops after
  the last row it needs. Use it with [`eachrow`](@ref Base.eachrow(::Worksheet)) to stream a large sheet.

Modes, as in XLSX.jl:
- `"r"`: read only.
- `"rw"`: read and edit; save with [`saveods`](@ref) or [`writeods`](@ref). Saving patches the
  original file: everything ODSFiles does not edit is kept as it was (D-023).
- `"w"`: start a new, empty spreadsheet (with one sheet, `Sheet1`) that will be written to
  `source`; an existing file there is not read.

Writing modes need `enable_cache=true`. With the do-block form, a file opened for writing
is saved to `source` after `f` returns (not if `f` throws).

See also [`readods`](@ref), [`newods`](@ref).
"""
function openods(f::Function, source::Union{AbstractString,IO}; mode::AbstractString = "r", enable_cache::Bool = true)
    xf = openods(source; mode, enable_cache)
    result = f(xf)
    xf.writable && saveods(xf)
    return result
end

function openods(source::Union{AbstractString,IO}; mode::AbstractString = "r", enable_cache::Bool = true)
    reads, writes = _parse_file_mode(mode)
    writes && !enable_cache && throw(ODSError("Writing a file (mode \"$mode\") needs `enable_cache=true`."))
    name = source isa AbstractString ? String(source) : source isa IOBuffer ? "IOBuffer" : "IO"
    if !reads                      # "w": a new file
        xf = newods()
        xf.source = name
        xf.source_io = source isa IO ? source : nothing
        return xf
    end
    if source isa AbstractString
        isfile(source) || throw(ODSError("File $source not found."))
        bytes = read(source)
    else
        bytes = read(source)
    end
    xf = _open_bytes(bytes, name, enable_cache)
    if writes
        xf.writable = true
        xf.source_io = source isa IO ? source : nothing
    end
    return xf
end

"""
    readods(source) -> ODSFile

Read an OpenDocument spreadsheet from a file path or an `IO`: [`openods`](@ref) with the
cache enabled. Each sheet is parsed the first time it is used.
"""
readods(source::Union{AbstractString,IO}) = openods(source; mode = "r", enable_cache = true)

# A read-only, uncached open for a one-shot read of `sheet` (readtable, readdata): only the
# part of content.xml up to that sheet's end is inflated.
function _open_through(source::Union{AbstractString,IO}, sheet::Union{AbstractString,Integer})
    if source isa AbstractString
        isfile(source) || throw(ODSError("File $source not found."))
    end
    name = source isa AbstractString ? String(source) : source isa IOBuffer ? "IOBuffer" : "IO"
    return _open_bytes(read(source), name, false; through = sheet)
end

# `through`: a sheet (name or number) that is all a one-shot read needs; content.xml is
# then inflated only as far as its end (phase 3). The file is read-only then.
function _open_bytes(bytes::Vector{UInt8}, name::String, enable_cache::Bool;
                     through::Union{Nothing,AbstractString,Integer} = nothing)
    container = try
        open_container(bytes)
    catch e
        e isa ArgumentError || rethrow()
        throw(ODSError("$name is not a readable OpenDocument spreadsheet: $(e.msg)"))
    end
    content = try
        through === nothing || !haspart(container, "content.xml") ? read_xml(container, :content) :
            content_through_sheet(container, through)
    catch e
        e isa ArgumentError || rethrow()
        throw(ODSError("$name is not a readable OpenDocument spreadsheet: $(e.msg)"))
    end
    content === nothing && throw(ODSError("$name has no content.xml."))
    styles_xml = container.flat === nothing ? read_xml(container, :styles) : nothing
    styles = build_style_index(styles_xml, content)
    xf = ODSFile(name, container, content, odf_version(content), styles, Worksheet[], DefinedName[],
                 SheetCore.DEFAULT_NULL_DATE, enable_cache)
    xf.scanner = BodyScanner(content)
    return xf
end

function _sheet_visible(e::SheetEntry, styles::StyleIndex)
    c = XML.Cursor(e.node)
    XML.next!(c)
    for (k, v) in XML.eachattribute!(c)
        k == "table:style-name" && return !(v in styles.hidden_tables)
    end
    return true
end

function _null_date(node)
    node === nothing && return SheetCore.DEFAULT_NULL_DATE
    c = XML.Cursor(node)
    XML.next!(c)
    result = SheetCore.DEFAULT_NULL_DATE
    XML.for_each_child!(c) do ch
        XML.nodetype(ch) === XML.Element || return
        if XML.tag(ch) == "table:null-date"
            for (k, v) in XML.eachattribute!(ch)
                if k == "table:date-value"
                    d = parse_odf_date(v)
                    d === nothing || (result = Dates.Date(d))
                end
            end
        end
        XML.skip_element!(ch)
    end
    return result
end

# The names in a table:named-expressions element.
function _read_names(node::XML.LazyNode{String}, scope::Union{Nothing,String})
    names = DefinedName[]
    c = XML.Cursor(node)
    XML.next!(c)
    XML.for_each_child!(c) do ch
        XML.nodetype(ch) === XML.Element || return
        t = XML.tag(ch)
        if t == "table:named-range" || t == "table:named-expression"
            name = ""; rng = nothing; expr = nothing; base = nothing
            for (k, v) in XML.eachattribute!(ch)
                k == "table:name" && (name = String(v))
                k == "table:cell-range-address" && (rng = String(v))
                k == "table:expression" && (expr = String(v))
                k == "table:base-cell-address" && (base = String(v))
            end
            isempty(name) || push!(names, DefinedName(name, scope, rng, expr, base))
        end
        XML.skip_element!(ch)
    end
    return names
end

# The sheet's own names (inside its table:table), read on first use.
function _local_names(ws::Worksheet)
    lock(ws.lock) do
        ws.localnames === nothing || return ws.localnames
        found = DefinedName[]
        ws.entry === nothing && (ws.localnames = found; return found)
        c = XML.Cursor(ws.entry.node)
        XML.next!(c)
        XML.for_each_child!(c) do ch
            XML.nodetype(ch) === XML.Element || return
            if XML.tag(ch) == "table:named-expressions"
                append!(found, _read_names(XML.LazyNode(ch), ws.name))
            end
            XML.skip_element!(ch)
        end
        ws.localnames = found
        return found
    end
end

#
# The cell store
#

# The full store of a cached sheet, read on first use.
function _cached_store(ws::Worksheet)::SheetStore
    s = ws.store
    s === nothing || return s
    lock(ws.lock) do
        if ws.store === nothing
            ws.store = ws.entry === nothing ? SheetStore() : read_store(ws.entry.node, get_odsfile(ws).styles)
        end
        return ws.store
    end
end

# The rows `rows` of a sheet: the cache, or with the cache off, a store read for them alone.
function _store_for(ws::Worksheet, rows::AbstractUnitRange{<:Integer})::SheetStore
    (is_cache_enabled(ws) || ws.entry === nothing) && return _cached_store(ws)
    isempty(rows) && return SheetStore(RowData[], ColRun[], CellRange[], nothing)
    return read_store(ws.entry.node, get_odsfile(ws).styles; skip_before = first(rows), stop_after = last(rows))
end
_store_for(ws::Worksheet) = _store_for(ws, 1:SheetCore.MAX_ROWS)

#
# Sheets
#

"""
    sheetnames(xf::ODSFile) -> Vector{String}

The names of the sheets, in order.
"""
sheetnames(xf::ODSFile) = [s.name for s in _sheets(xf)]

"""
    sheetcount(xf::ODSFile) -> Int

The number of sheets.
"""
sheetcount(xf::ODSFile) = length(_sheets(xf))

# Sheet names match without regard to case, as in LibreOffice (and Excel). A quoted name
# (`'My sheet'`) is unquoted first. The index is extended only until an exact match is
# found; a match without regard to case needs all the names.
function _sheet_index(xf::ODSFile, sheetname::AbstractString)
    name = SheetCore.unquoteit(String(sheetname))
    i = findfirst(s -> s.name == name, xf.sheets)
    i === nothing || return i
    while _index_next!(xf)
        xf.sheets[end].name == name && return length(xf.sheets)
    end
    return findfirst(s -> _same_sheetname(s.name, name), xf.sheets)
end
_same_sheetname(a::AbstractString, b::AbstractString) =
    Unicode.normalize(a; casefold = true) == Unicode.normalize(b; casefold = true)

"""
    hassheet(xf::ODSFile, sheetname) -> Bool

Whether the file has a sheet named `sheetname`. Names match without regard to case, as in
LibreOffice, which does not allow two sheets whose names differ only in case.
"""
hassheet(xf::ODSFile, sheetname::AbstractString)::Bool = _sheet_index(xf, sheetname) !== nothing

function getsheet(xf::ODSFile, sheetname::AbstractString)::Worksheet
    i = _sheet_index(xf, sheetname)
    i === nothing && throw(ODSError("$(xf.source) does not have a sheet named `$sheetname`."))
    return xf.sheets[i]
end

function getsheet(xf::ODSFile, i::Integer)::Worksheet
    while length(xf.sheets) < i && _index_next!(xf) end
    1 <= i <= length(xf.sheets) ||
        throw(ODSError("$(xf.source) has no sheet $i: it has $(length(xf.sheets)) sheet(s)."))
    return xf.sheets[i]
end

Base.getindex(xf::ODSFile, i::Integer) = getsheet(xf, i)
function Base.getindex(xf::ODSFile, s::AbstractString)
    # a sheet-qualified reference to a sheet that exists (found without indexing the rest)
    if occursin('.', s) || occursin('!', s)
        ref = try parse_sheet_ref(s) catch; nothing end
        if ref !== nothing && _sheet_index(xf, ref.sheet) !== nothing
            return getdata(xf, ref)
        end
    end
    hassheet(xf, s) && return getsheet(xf, s)
    return getdata(xf, s)
end

"""
    isvisible(ws::Worksheet) -> Bool

Whether the sheet is shown, as opposed to hidden (`table:display="false"` on its table style).
"""
isvisible(ws::Worksheet) = ws.visible

#
# Defined names
#

# The name `name` in `names`, matched without regard to case (as LibreOffice does).
function _find_name(names::Vector{DefinedName}, name::AbstractString)
    for dn in names
        dn.name == name && return dn
    end
    for dn in names
        _same_sheetname(dn.name, name) && return dn
    end
    return nothing
end

is_workbook_defined_name(xf::ODSFile, name::AbstractString) = _find_name(_wb_names(xf), name) !== nothing
is_worksheet_defined_name(ws::Worksheet, name::AbstractString) = _find_name(_local_names(ws), name) !== nothing

# A space-separated table:cell-range-address list as a reference string: `~` between areas.
_address_list(s::AbstractString) = join(SheetCore._split_unquoted(strip(s), (' ',)) |> v -> filter(!isempty, v), "~")

"""
    get_defined_name_value(dn::DefinedName)

The value of a defined name: a sheet-qualified reference (`SheetCellRef`, `SheetCellRange`,
...) for a named range or a named expression that is a single reference, or the constant of
a named expression that is a number, string or logical value. Other expressions throw: they
would need a formula evaluator.
"""
function get_defined_name_value(dn::DefinedName)
    if dn.range !== nothing
        return parse_sheet_ref(_address_list(dn.range))
    end
    expr = something(dn.expression, "")
    body = _strip_formula_prefix(expr)
    startswith(body, '=') && (body = body[2:end])
    body = strip(body)
    # One or more bracketed references, separated by spaces or `~`: LibreOffice saves a
    # named range of several areas so (F-026).
    toks = tokenize_formula(body)
    if !isempty(toks) && all(t -> t.kind in (FT_REF, FT_SPACE) || (t.kind === FT_OP && t.text == "~"), toks) &&
       any(t -> t.kind === FT_REF, toks)
        areas = [String(t.text[2:end-1]) for t in toks if t.kind === FT_REF]
        return parse_sheet_ref(join(areas, "~"))
    end
    _is_intlike(body) && return parse(Int64, body)
    x = tryparse(Float64, body)
    x === nothing || return x
    if length(body) >= 2 && startswith(body, '"') && endswith(body, '"')
        return replace(body[2:end-1], "\"\"" => "\"")
    end
    uppercase(body) in ("TRUE()", "TRUE") && return true
    uppercase(body) in ("FALSE()", "FALSE") && return false
    throw(ODSError("The defined name `$(dn.name)` is the expression `$expr`, which ODSFiles cannot evaluate."))
end
get_defined_name_value(xf::ODSFile, name::AbstractString) = get_defined_name_value(_find_name(_wb_names(xf), name))
get_defined_name_value(ws::Worksheet, name::AbstractString) = get_defined_name_value(_find_name(_local_names(ws), name))

is_defined_name_value_a_reference(v) = v isa Union{SheetCellRef,SheetCellRange,SheetColumnRange,SheetRowRange,NonContiguousRange}

"""
    defined_names(xf::ODSFile) -> Vector{DefinedName}
    defined_names(ws::Worksheet) -> Vector{DefinedName}

The workbook's named ranges and expressions, or those local to a sheet.
"""
defined_names(xf::ODSFile) = copy(_wb_names(xf))
defined_names(ws::Worksheet) = copy(_local_names(ws))

#
# Dimension and display
#

"""
    get_dimension(ws::Worksheet; allow_load=true) -> CellRange

The smallest range holding every cell with a value or formula. ODS files do not record it,
so it is computed from the sheet (the cache, or a scan without the cache). An empty sheet
gives `A1:A1`, as in XLSX.jl. With `allow_load=false`, an unread sheet gives `A1:A1`
without being read.
"""
function get_dimension(ws::Worksheet; allow_load::Bool = true)::CellRange
    fallback = CellRange(CellRef(1, 1), CellRef(1, 1))
    if !allow_load && ws.store === nothing
        return fallback
    end
    dim = store_dimension(is_cache_enabled(ws) ? _cached_store(ws) : _store_for(ws))
    return something(dim, fallback)
end

# The dimension if it is known without reading the sheet.
_known_dimension(ws::Worksheet) = ws.store === nothing ? nothing : store_dimension(ws.store)

Base.size(ws::Worksheet) = size(get_dimension(ws))

function Base.show(io::IO, ws::Worksheet)
    hidden = ws.visible ? "" : " (hidden)"
    rg = _known_dimension(ws)
    if rg !== nothing
        nrow, ncol = size(rg)
        print(io, nrow, "×", ncol, " ODSFiles.Worksheet: [\"", ws.name, "\"](", rg, ")", hidden)
    else
        print(io, "ODSFiles.Worksheet: [\"", ws.name, "\"]", hidden)
    end
end

function Base.show(io::IO, xf::ODSFile)
    n = sheetcount(xf)
    src = xf.source in ("IOBuffer", "IO") ? xf.source : repr(xf.source)
    print(io, "ODSFile(", src, ") containing ", n, n == 1 ? " Worksheet\n" : " Worksheets\n")
    @printf(io, "%21s %-13s %-13s\n", "sheetname", "size", "range")
    print(io, "-"^(21 + 1 + 13 + 1 + 13))
    for s in _sheets(xf)
        println(io)
        name = length(s.name) > 20 ? first(s.name, 19) * "…" : s.name
        rg = _known_dimension(s)
        if rg === nothing
            @printf(io, "%21s %s", name, s.store === nothing ? "size unknown" : "empty")
        else
            sz = size(rg)
            @printf(io, "%21s %-13s %-13s", name, string(sz[1], "x", sz[2]), string(rg))
        end
        s.visible || print(io, " (hidden)")
    end
end
