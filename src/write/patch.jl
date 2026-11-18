# Saving a file that was read: patch its content.xml (D-023).
#
# Everything is copied from the original text, verbatim, except:
#   - a sheet with edits: its table:table is rebuilt from the original, child by child. Rows
#     without edits, and every element that is not a row, are copied as they are. A row
#     element that covers edited rows is split around them (number-rows-repeated), and an
#     edited row is rewritten cell by cell: untouched cells are copied (with their
#     number-columns-repeated split where needed), edited cells are written from the store.
#     Rows and columns beyond the original ones are added after the last row / column.
#   - new sheets, added after the last sheet
#   - ODSFiles's typed styles, added to office:automatic-styles
#   - namespace declarations the new XML needs, added to the root element
# Original text is reached through XML.jl's `sourcespan` (zero-copy, D-009).

# The index of the `>` that ends the start tag at the beginning of `text`.
function _start_tag_end(text::AbstractString)
    q = '\0'
    for i in eachindex(text)
        c = text[i]
        if q != '\0'
            c == q && (q = '\0')
        elseif c == '"' || c == '\''
            q = c
        elseif c == '>'
            return i
        end
    end
    throw(ODSError("Malformed XML: a start tag is not closed."))
end

const _ATTR_RX = r"([^\s=/<>]+)\s*=\s*(\"[^\"]*\"|'[^']*')"

# The raw attributes of the start tag of `text`: (name, quoted value as written).
_raw_attrs(text::AbstractString) =
    [(String(m.captures[1]), String(m.captures[2])) for m in eachmatch(_ATTR_RX, SubString(text, 1, _start_tag_end(text)))]

function _attr_int(text::AbstractString, name::AbstractString, default::Int)
    for (k, v) in _raw_attrs(text)
        k == name && return something(tryparse(Int, strip(v[2:end-1])), default)
    end
    return default
end

_tag_name(text::AbstractString) = match(r"^<([^\s/>]+)", text).captures[1]

"""
    _retag(text, name, value; open=false) -> String

`text`, an element's source, with attribute `name` of its start tag set to `value`
(removed when `value` is `nothing` or 1, its default). The other attributes keep their
original text. With `open=true`, only the start tag is returned, as an opening tag even if
the element was self-closing.
"""
function _retag(text::AbstractString, name::AbstractString, value::Union{Nothing,Integer}; open::Bool = false)
    e = _start_tag_end(text)
    selfclosing = text[prevind(text, e)] == '/'
    io = IOBuffer()
    print(io, '<', _tag_name(text))
    for (k, v) in _raw_attrs(text)
        k == name || print(io, ' ', k, '=', v)
    end
    (value === nothing || value == 1) || print(io, ' ', name, "=\"", value, '"')
    if open
        print(io, '>')
    else
        print(io, selfclosing ? "/>" : ">")
        print(io, SubString(text, nextind(text, e)))
    end
    return String(take!(io))
end

mutable struct _PatchState
    ws::Worksheet
    store::SheetStore
    styles::StyleIndex
    src::String
    out::IOBuffer
    pos::Int                       # the next index of src to copy
    nextrow::Int                   # the row number of the next table:table-row
    ncols::Int                     # columns defined so far
    need_cols::Int                 # columns the edits reach
    rows_started::Bool
    new_rows_written::Bool
    drows::Vector{Int}             # edited rows, sorted
    dcols::Dict{Int,Vector{Int}}   # edited columns of each edited row, sorted
    display::Bool                  # write display text in typed cells (D-029)
end

function _copy_to!(st::_PatchState, idx::Int)
    if idx > st.pos
        print(st.out, SubString(st.src, st.pos, prevind(st.src, idx)))
    end
    st.pos = max(st.pos, idx)
    return
end

_col_default(st::_PatchState, col::Int) =
    any(cr -> cr.default_style >= 0 && cr.col <= col <= cr.col + cr.count - 1, st.store.cols)

# Untouched text is not copied element by element: `st.pos` stays behind it, and it is
# copied in one piece when something must be written after it (`_copy_to!`). Only the
# elements that change, and the places where something is inserted, need their position.

# Before the first row (at src index `at`): add the columns the edits need beyond the
# defined ones.
function _before_rows!(st::_PatchState, at::Function)
    st.rows_started && return
    st.rows_started = true
    k = st.need_cols - st.ncols
    if k > 0
        _copy_to!(st, at())
        print(st.out, "<table:table-column")
        k > 1 && print(st.out, " table:number-columns-repeated=\"", k, "\"")
        print(st.out, "/>")
        st.ncols += k
    end
end

# After the last original row (at src index `at`): the stored rows beyond it (all of them
# edits).
function _write_new_rows!(st::_PatchState, at::Function)
    st.new_rows_written && return
    st.new_rows_written = true
    # once the walk is past the last edit it stops counting rows: then nothing is new
    _past_edits(st) && return
    i = _first_row_index(st.store, st.nextrow)
    i > length(st.store.rows) && return
    _copy_to!(st, at())
    write_rows(st.out, @view(st.store.rows[i:end]), st.styles, st.nextrow; st.display)
end

# The edited rows in a:b.
function _edited_rows(st::_PatchState, a::Int, b::Int)
    lo = searchsortedfirst(st.drows, a)
    hi = searchsortedlast(st.drows, b)
    return @view st.drows[lo:hi]
end

# Whether every edit is behind the walk: the rest of the table can be copied as it is.
_past_edits(st::_PatchState) = st.rows_started && (isempty(st.drows) || st.nextrow > st.drows[end])

function _walk!(st::_PatchState, node::XML.LazyNode, level::Symbol)
    c = XML.Cursor(node)
    XML.next!(c)
    XML.for_each_child!(c) do ch
        XML.nodetype(ch) === XML.Element || return
        if _past_edits(st)                      # copied with the rest, at the end
            XML.skip_element!(ch)
            return
        end
        t = XML.tag(ch)
        repeat = 1
        if t == "table:table-row" || t == "table:table-column"
            key = t == "table:table-row" ? "table:number-rows-repeated" : "table:number-columns-repeated"
            for (k, v) in XML.eachattribute!(ch)
                k == key && (repeat = something(tryparse(Int, v), 1))
            end
        end
        start() = first(XML.sourcespan(XML.LazyNode(ch)))
        if t == "table:table-column"
            st.ncols += repeat
        elseif t in _COL_CONTAINERS
            _walk!(st, XML.LazyNode(ch), :cols)
        elseif t == "table:table-row"
            level === :table && _before_rows!(st, start)
            r0 = st.nextrow
            cnt = max(1, min(repeat, SheetCore.MAX_ROWS - r0 + 1))
            if isempty(_edited_rows(st, r0, r0 + cnt - 1))
                st.nextrow = r0 + cnt                   # untouched: left in the gap
            else
                ln = XML.LazyNode(ch)
                sp = XML.sourcespan(ln)
                _copy_to!(st, first(sp))
                _patch_row!(st, ln, SubString(st.src, first(sp), last(sp)), cnt)
                st.pos = nextind(st.src, last(sp))
            end
        elseif t in _ROW_CONTAINERS
            level === :table && _before_rows!(st, start)
            _walk!(st, XML.LazyNode(ch), :rows)
        else
            level === :table && st.rows_started && _write_new_rows!(st, start)
        end
        XML.skip_element!(ch)
    end
    if level === :table
        sp = XML.sourcespan(node)
        endtag = findprev('<', st.src, last(sp))       # the start of </table:table>
        _before_rows!(st, () -> endtag)
        _write_new_rows!(st, () -> endtag)
    end
    return
end

# A row element covering rows nextrow…nextrow+cnt-1, some of them edited, at `st.pos`.
function _patch_row!(st::_PatchState, ln::XML.LazyNode, text::SubString{String}, cnt::Int)
    r0 = st.nextrow
    st.nextrow = r0 + cnt
    edited = _edited_rows(st, r0, r0 + cnt - 1)
    cur = r0
    for r in edited
        r > cur && print(st.out, _retag(text, "table:number-rows-repeated", r - cur))
        _write_edited_row!(st, ln, text, r)
        cur = r + 1
    end
    last_row = r0 + cnt - 1
    cur <= last_row && print(st.out, _retag(text, "table:number-rows-repeated", last_row - cur + 1))
    return
end

# An edited cell that is now empty keeps the original cell's style.
function _empty_cell_like(io::IO, celltext::AbstractString, repeat::Int)
    covered = startswith(celltext, "<table:covered-table-cell")
    print(io, covered ? "<table:covered-table-cell" : "<table:table-cell")
    for (k, v) in _raw_attrs(celltext)
        k == "table:style-name" && print(io, ' ', k, '=', v)
    end
    repeat > 1 && print(io, " table:number-columns-repeated=\"", repeat, '"')
    print(io, "/>")
end

function _write_edited_cell!(st::_PatchState, r::Int, col::Int, celltext::AbstractString, rowdefault::Bool)
    d = cell_data(st.store, r, col)
    if d === nothing
        _empty_cell_like(st.out, celltext, 1)
    else
        write_cell(st.out, d, st.styles; style_default = rowdefault || _col_default(st, col), st.display)
    end
end

function _write_edited_row!(st::_PatchState, ln::XML.LazyNode, text::SubString{String}, r::Int)
    src = st.src
    out = st.out
    e = _start_tag_end(text)
    selfclosing = text[prevind(text, e)] == '/'
    rowdefault = any(((k, _),) -> k == "table:default-cell-style-name", _raw_attrs(text))
    print(out, _retag(text, "table:number-rows-repeated", nothing; open = true))
    cols = st.dcols[r]
    ci = 1                                      # the next edited column to write
    col = 1
    off = first(XML.sourcespan(ln)) - 1          # src index = off + index in text
    lpos = off + nextind(text, e)                # src index after the start tag
    if !selfclosing
        c = XML.Cursor(ln)
        XML.next!(c)
        XML.for_each_child!(c) do ch
            XML.nodetype(ch) === XML.Element || return
            csp = XML.sourcespan(XML.LazyNode(ch))
            first(csp) > lpos && print(out, SubString(src, lpos, prevind(src, first(csp))))
            celltext = SubString(src, first(csp), last(csp))
            t = XML.tag(ch)
            if t == "table:table-cell" || t == "table:covered-table-cell"
                n = max(1, _attr_int(celltext, "table:number-columns-repeated", 1))
                lastc = col + n - 1
                cur = col
                while ci <= length(cols) && cols[ci] <= lastc
                    ec = cols[ci]
                    ec > cur && print(out, _retag(celltext, "table:number-columns-repeated", ec - cur))
                    _write_edited_cell!(st, r, ec, celltext, rowdefault)
                    cur = ec + 1
                    ci += 1
                end
                if cur == col
                    print(out, celltext)
                elseif cur <= lastc
                    print(out, _retag(celltext, "table:number-columns-repeated", lastc - cur + 1))
                end
                col = lastc + 1
            else
                print(out, celltext)
            end
            lpos = nextind(src, last(csp))
            XML.skip_element!(ch)
        end
    end
    # edited columns beyond the row's cells
    while ci <= length(cols)
        ec = cols[ci]
        ec > col && write_cell(out, nothing, st.styles; repeat = ec - col)
        d = cell_data(st.store, r, ec)
        d === nothing ? write_cell(out, nothing, st.styles) :
            write_cell(out, d, st.styles; style_default = rowdefault || _col_default(st, ec), st.display)
        col = ec + 1
        ci += 1
    end
    if selfclosing
        print(out, "</table:table-row>")
    else
        endidx = off + lastindex(text)
        print(out, SubString(src, lpos, endidx))   # whitespace and the end tag
    end
    return
end

"""
    patched_table(ws::Worksheet) -> String

The `table:table` of a sheet read from the file, with its edits (D-023).
"""
function patched_table(ws::Worksheet; display::Bool = true)
    node = ws.entry.node
    src = parent(XML.sourcetext(node))
    store = _cached_store(ws)
    dcols = Dict{Int,Vector{Int}}(r => sort!(unique(cs)) for (r, cs) in ws.dirty)
    need = maximum((maximum(v) for v in values(dcols)); init = 0)
    sp = XML.sourcespan(node)
    st = _PatchState(ws, store, get_odsfile(ws).styles, src, IOBuffer(sizehint = ncodeunits(src) ÷ 4 + 1024),
                     first(sp), 1, 0, need, false, false, sort!(collect(keys(dcols))), dcols, display)
    _walk!(st, node, :table)
    _copy_to!(st, nextind(src, last(sp)))      # the rest of the table, verbatim
    return String(take!(st.out))
end

const _NAMESPACES = [
    "office" => "urn:oasis:names:tc:opendocument:xmlns:office:1.0",
    "style" => "urn:oasis:names:tc:opendocument:xmlns:style:1.0",
    "text" => "urn:oasis:names:tc:opendocument:xmlns:text:1.0",
    "table" => "urn:oasis:names:tc:opendocument:xmlns:table:1.0",
    "number" => "urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0",
    "fo" => "urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0",
    "of" => "urn:oasis:names:tc:opendocument:xmlns:of:1.2",
]

"""
    patched_content(xf::ODSFile) -> String

The content.xml (or flat document) of a file that was read, with its edits, new sheets
and new styles (D-023).
"""
function patched_content(xf::ODSFile; display::Bool = true)
    c = XML.Cursor(xf.content)
    while XML.next!(c) !== nothing
        XML.nodetype(c) === XML.Element && break
    end
    root = XML.LazyNode(c)
    src = parent(XML.sourcetext(root))
    rootspan = XML.sourcespan(root)
    autostyles = nothing; body = nothing
    XML.for_each_child!(c) do ch
        XML.nodetype(ch) === XML.Element || return
        t = XML.tag(ch)
        t == "office:automatic-styles" && (autostyles = XML.LazyNode(ch))
        t == "office:body" && (body = XML.LazyNode(ch))
        XML.skip_element!(ch)
    end
    splices = Tuple{Int,Int,String}[]      # (first, last, replacement); last = first - 1 inserts
    # namespaces the written XML needs
    roottext = SubString(src, first(rootspan), last(rootspan))
    tagend = first(rootspan) - 1 + _start_tag_end(roottext)
    tagend_at = src[prevind(src, tagend)] == '/' ? prevind(src, tagend) : tagend
    starttag = SubString(src, first(rootspan), tagend)
    ns = join(" xmlns:$p=\"$u\"" for (p, u) in _NAMESPACES if !occursin("xmlns:$p=", starttag))
    isempty(ns) || push!(splices, (tagend_at, tagend_at - 1, ns))
    # edited sheets
    last_table_end = 0
    for ws in _sheets(xf)
        ws.entry === nothing && continue
        sp = XML.sourcespan(ws.entry.node)
        last_table_end = max(last_table_end, last(sp))
        isempty(ws.dirty) || push!(splices, (first(sp), last(sp), patched_table(ws; display)))
    end
    # new sheets, after the last one
    newsheets = [ws for ws in _sheets(xf) if ws.entry === nothing]
    if !isempty(newsheets)
        io = IOBuffer()
        foreach(ws -> write_table(io, ws; display), newsheets)
        at = last_table_end > 0 ? nextind(src, last_table_end) : _spreadsheet_end(body, src)
        push!(splices, (at, at - 1, String(take!(io))))
    end
    # typed styles
    sx = typed_styles_xml(xf.styles)
    if !isempty(sx)
        if autostyles === nothing
            body === nothing && throw(ODSError("The document has no office:body."))
            at = first(XML.sourcespan(body))
            push!(splices, (at, at - 1, "<office:automatic-styles>$sx</office:automatic-styles>"))
        else
            asp = XML.sourcespan(autostyles)
            atext = SubString(src, first(asp), last(asp))
            if endswith(atext, "/>")
                push!(splices, (first(asp), last(asp), _retag(atext, "", nothing; open = true) * sx * "</office:automatic-styles>"))
            else
                at = first(asp) - 1 + findlast("</", atext)[1]
                push!(splices, (at, at - 1, sx))
            end
        end
    end
    sort!(splices; by = x -> (x[1], x[2]))
    out = IOBuffer(sizehint = ncodeunits(src) + sum(s -> ncodeunits(s[3]), splices; init = 0))
    pos = firstindex(src)
    for (a, b, rep) in splices
        a > pos && print(out, SubString(src, pos, prevind(src, a)))
        print(out, rep)
        pos = b >= a ? nextind(src, b) : max(pos, a)
    end
    pos <= lastindex(src) && print(out, SubString(src, pos))
    return String(take!(out))
end

# The index of `</office:spreadsheet>` in the body, where sheets are added to a document
# that has none.
function _spreadsheet_end(body, src::String)
    body === nothing && throw(ODSError("The document has no office:body."))
    sp = XML.sourcespan(body)
    text = SubString(src, first(sp), last(sp))
    r = findlast("</office:spreadsheet>", text)
    r === nothing && throw(ODSError("The document's body has no office:spreadsheet to add sheets to."))
    return first(sp) - 1 + r[1]
end
