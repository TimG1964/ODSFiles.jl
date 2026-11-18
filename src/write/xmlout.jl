# Writing cells, rows and tables as ODF XML, from the store.
#
# A cell is written as LibreOffice writes one (F-005, F-010, F-021): its style, repeat and
# spans, its formula, its value attributes by type, and its text as `text:p` paragraphs
# (runs of spaces as `text:s`, tabs as `text:tab`, one paragraph per line). Numbers are
# written in their shortest exact form (D-026); a formula is written without a result,
# which LibreOffice computes on load (F-028).

# Whether `s` holds none of the given ASCII bytes (most texts and names need no escaping:
# they are then written at once, phase 3).
@inline function _none_of(s::AbstractString, bytes)
    for b in codeunits(s)
        b in bytes && return false
    end
    return true
end
const _TEXT_SPECIAL = (UInt8('&'), UInt8('<'), UInt8('>'))
const _ATTR_SPECIAL = (UInt8('&'), UInt8('<'), UInt8('>'), UInt8('"'), UInt8('\n'), UInt8('\r'), UInt8('\t'))

function _escape_text(io::IO, s::AbstractString)
    _none_of(s, _TEXT_SPECIAL) && (write(io, s); return)
    for c in s
        if c == '&'
            print(io, "&amp;")
        elseif c == '<'
            print(io, "&lt;")
        elseif c == '>'
            print(io, "&gt;")
        else
            print(io, c)
        end
    end
end

function _escape_attr(io::IO, s::AbstractString)
    _none_of(s, _ATTR_SPECIAL) && (write(io, s); return)
    for c in s
        if c == '&'
            print(io, "&amp;")
        elseif c == '<'
            print(io, "&lt;")
        elseif c == '>'
            print(io, "&gt;")
        elseif c == '"'
            print(io, "&quot;")
        elseif c == '\n'
            print(io, "&#10;")
        elseif c == '\r'
            print(io, "&#13;")
        elseif c == '\t'
            print(io, "&#9;")
        else
            print(io, c)
        end
    end
end
_escape_attr(s::AbstractString) = sprint(_escape_attr, s)

# A text as paragraphs (F-021): lines become text:p; a run of n > 1 spaces, or a space at
# the start or end of a paragraph, becomes text:s; tabs become text:tab.
function _write_paragraphs(io::IO, s::AbstractString)
    # most texts need no text:s, text:tab or second paragraph: write them at once
    if _plain_text(s)
        print(io, "<text:p>"); _escape_text(io, s); print(io, "</text:p>")
        return
    end
    for line in eachsplit(replace(s, "\r\n" => "\n", '\r' => '\n'), '\n')
        if isempty(line)
            print(io, "<text:p/>")
            continue
        end
        print(io, "<text:p>")
        chars = collect(line)
        i = 1
        n = length(chars)
        while i <= n
            c = chars[i]
            if c == ' '
                j = i
                while j < n && chars[j + 1] == ' '
                    j += 1
                end
                run = j - i + 1
                if run == 1 && i != 1 && j != n
                    print(io, ' ')
                else
                    run == 1 ? print(io, "<text:s/>") : print(io, "<text:s text:c=\"", run, "\"/>")
                end
                i = j + 1
            elseif c == '\t'
                print(io, "<text:tab/>")
                i += 1
            else
                c == '&' ? print(io, "&amp;") : c == '<' ? print(io, "&lt;") : c == '>' ? print(io, "&gt;") : print(io, c)
                i += 1
            end
        end
        print(io, "</text:p>")
    end
end

# A text that is one paragraph with no tab, no run of spaces and no space at either end.
function _plain_text(s::AbstractString)
    isempty(s) && return false
    prev = ' '                                   # a space at the start is not plain
    for c in s
        (c == '\n' || c == '\r' || c == '\t') && return false
        c == ' ' && prev == ' ' && return false
        prev = c
    end
    return prev != ' '
end

# `<table:table-cell [table:style-name="…"] office:value-type="…" office:(date-)value="`,
# by style, value type and whether a Default style is written, built once per style index
# (a document is written by one task at a time).
function _cell_prefix(styles::StyleIndex, style::Int32, kind::CellKind, style_default::Bool)
    key = (style, UInt8(kind), style_default)
    p = get(styles.prefixes, key, nothing)
    p === nothing || return p
    io = IOBuffer()
    print(io, "<table:table-cell")
    if style != 0
        print(io, " table:style-name=\""); _escape_attr(io, style_name(styles, style)); print(io, '"')
    elseif style_default
        print(io, " table:style-name=\"Default\"")
    end
    print(io, " office:value-type=\"", _value_type(kind), "\" ", kind === CK_DATE ? "office:date-value" : "office:value", "=\"")
    p = String(take!(io))
    styles.prefixes[key] = p
    return p
end

# Numbers, dates, times and durations as text, through the document's digit buffer
# (`StyleIndex.numbuf`; a document is written by one task at a time) and SheetCore's
# `write_integer` / `write_float` (adapted from XLSX.jl), so that no string is made for
# each value (phase 3).

_two(io, buf, x) = SheetCore.write_integer(io, buf, x; mindigits = 2)

function _write_date(io::IO, buf::Vector{UInt8}, d::Dates.Date)
    y, m, dd = Dates.yearmonthday(d)
    y < 0 && write(io, UInt8('-'))
    SheetCore.write_integer(io, buf, abs(y); mindigits = 4)
    write(io, UInt8('-')); _two(io, buf, m); write(io, UInt8('-')); _two(io, buf, dd)
end

function _write_datetime(io::IO, buf::Vector{UInt8}, t::Dates.DateTime)
    _write_date(io, buf, Dates.Date(t))
    write(io, UInt8('T')); _two(io, buf, Dates.hour(t)); write(io, UInt8(':')); _two(io, buf, Dates.minute(t))
    write(io, UInt8(':')); _two(io, buf, Dates.second(t))
    ms = Dates.millisecond(t)
    ms == 0 || (write(io, UInt8('.')); SheetCore.write_integer(io, buf, ms; mindigits = 3))
end

# An ISO 8601 duration in LibreOffice's form (F-020): [-]PT{h}H{mm}M{ss[.fffffffff]}S.
function _write_duration(io::IO, buf::Vector{UInt8}, ns::Int64)
    ns < 0 && write(io, UInt8('-'))
    a = unsigned(abs(Int128(ns)))
    secs, frac = divrem(a, UInt128(1_000_000_000))
    h, rest = divrem(secs, UInt128(3600))
    m, s = divrem(rest, UInt128(60))
    write(io, "PT"); _two(io, buf, h); write(io, UInt8('H')); _two(io, buf, m); write(io, UInt8('M')); _two(io, buf, s)
    if frac != 0
        f = rstrip(lpad(string(frac), 9, '0'), '0')
        print(io, '.', f)
    end
    write(io, UInt8('S'))
end

# The text of a number as written (D-026).
function _write_number(io::IO, buf::Vector{UInt8}, d::CellData)
    if (d.flags & F_INTLIKE) != 0
        d.text !== nothing && d.kind === CK_FLOAT ? write(io, d.text) :
            SheetCore.write_integer(io, buf, Int64(reinterpret(Float64, d.bits)))
    else
        SheetCore.write_float(io, buf, reinterpret(Float64, d.bits))
    end
    return nothing
end

_value_type(k::CellKind) =
    k === CK_FLOAT ? "float" : k === CK_PERCENT ? "percentage" : k === CK_CURRENCY ? "currency" :
    (k === CK_DATE || k === CK_DATETIME) ? "date" : k === CK_TIME ? "time" : k === CK_BOOL ? "boolean" : "string"

# The value attribute of a typed (non-text) cell, for a cell written without display text.
function _write_value_attr(io::IO, buf::Vector{UInt8}, d::CellData)
    k = d.kind
    if k === CK_FLOAT || k === CK_PERCENT || k === CK_CURRENCY
        k === CK_CURRENCY && d.text !== nothing && (print(io, " office:currency=\""); _escape_attr(io, d.text); print(io, '"'))
        print(io, " office:value=\""); _write_number(io, buf, d); print(io, '"')
    elseif k === CK_DATE
        print(io, " office:date-value=\""); _write_date(io, buf, _date_from_days(reinterpret(Int64, d.bits))); print(io, '"')
    elseif k === CK_DATETIME
        print(io, " office:date-value=\""); _write_datetime(io, buf, _datetime_from_ms(reinterpret(Int64, d.bits))); print(io, '"')
    elseif k === CK_TIME
        print(io, " office:time-value=\""); _write_duration(io, buf, reinterpret(Int64, d.bits)); print(io, '"')
    elseif k === CK_BOOL
        print(io, " office:boolean-value=\"", d.bits != 0 ? "true" : "false", '"')
    end
end

"""
    write_cell(io, d::Union{CellData,Nothing}, styles; repeat=1, style_default=false, display=true)

Write one `table:table-cell` (or `table:covered-table-cell`). `nothing` is an empty cell.
With `style_default`, a cell in the `Default` style says so (`table:style-name="Default"`),
because its row or column has a default style it must not take. With `display=false`, a
number, date, time or boolean cell is written without its display text (`text:p`), which
readers recompute from the value (D-029).
"""
function write_cell(io::IO, d::Union{Nothing,CellData}, styles::StyleIndex; repeat::Integer = 1, style_default::Bool = false,
                    display::Bool = true)
    if d === nothing
        print(io, "<table:table-cell")
        style_default && print(io, " table:style-name=\"Default\"")
        repeat > 1 && print(io, " table:number-columns-repeated=\"", repeat, "\"")
        print(io, "/>")
        return
    end
    buf = styles.numbuf
    covered = (d.flags & F_COVERED) != 0
    # the common cell: a plain number or date, written from a cached prefix (phase 3)
    if repeat == 1 && !covered && d.colspan == 1 && d.rowspan == 1 && d.formula === nothing &&
       (d.kind === CK_FLOAT || d.kind === CK_DATE) && display
        write(io, _cell_prefix(styles, d.style, d.kind, style_default))
        if d.kind === CK_FLOAT
            _write_number(io, buf, d); write(io, "\"><text:p>"); _write_number(io, buf, d)
        else
            x = _date_from_days(reinterpret(Int64, d.bits))
            _write_date(io, buf, x); write(io, "\"><text:p>"); _write_date(io, buf, x)
        end
        write(io, "</text:p></table:table-cell>")
        return
    end
    print(io, covered ? "<table:covered-table-cell" : "<table:table-cell")
    if d.style != 0
        print(io, " table:style-name=\""); _escape_attr(io, style_name(styles, d.style)); print(io, '"')
    elseif style_default
        print(io, " table:style-name=\"Default\"")
    end
    repeat > 1 && print(io, " table:number-columns-repeated=\"", repeat, "\"")
    d.colspan > 1 && print(io, " table:number-columns-spanned=\"", d.colspan, "\"")
    d.rowspan > 1 && print(io, " table:number-rows-spanned=\"", d.rowspan, "\"")
    if d.formula !== nothing
        print(io, " table:formula=\""); _escape_attr(io, d.formula); print(io, '"')
    end
    k = d.kind
    if k === CK_EMPTY || k === CK_ERROR
        print(io, "/>")
        return
    end
    print(io, " office:value-type=\"", _value_type(k), '"')
    if !display && k !== CK_STRING
        _write_value_attr(io, buf, d)
        print(io, "/>")
        return
    end
    if k === CK_FLOAT || k === CK_PERCENT || k === CK_CURRENCY
        k === CK_CURRENCY && d.text !== nothing && (print(io, " office:currency=\""); _escape_attr(io, d.text); print(io, '"'))
        print(io, " office:value=\""); _write_number(io, buf, d); print(io, "\"><text:p>"); _write_number(io, buf, d)
        print(io, "</text:p>")
    elseif k === CK_DATE
        x = _date_from_days(reinterpret(Int64, d.bits))
        print(io, " office:date-value=\""); _write_date(io, buf, x); print(io, "\"><text:p>"); _write_date(io, buf, x)
        print(io, "</text:p>")
    elseif k === CK_DATETIME
        x = _datetime_from_ms(reinterpret(Int64, d.bits))
        print(io, " office:date-value=\""); _write_datetime(io, buf, x); print(io, "\"><text:p>")
        _write_date(io, buf, Dates.Date(x)); print(io, ' '); _two(io, buf, Dates.hour(x)); print(io, ':')
        _two(io, buf, Dates.minute(x)); print(io, ':'); _two(io, buf, Dates.second(x)); print(io, "</text:p>")
    elseif k === CK_TIME
        ns = reinterpret(Int64, d.bits)
        print(io, " office:time-value=\""); _write_duration(io, buf, ns); print(io, "\"><text:p>")
        ns < 0 && print(io, '-')
        secs = div(abs(Int128(ns)), 1_000_000_000)
        _two(io, buf, div(secs, 3600)); print(io, ':'); _two(io, buf, div(rem(secs, 3600), 60)); print(io, ':')
        _two(io, buf, rem(secs, 60)); print(io, "</text:p>")
    elseif k === CK_BOOL
        b = d.bits != 0
        print(io, " office:boolean-value=\"", b ? "true" : "false", "\"><text:p>", b ? "TRUE" : "FALSE", "</text:p>")
    else # CK_STRING
        print(io, '>')
        _write_paragraphs(io, something(d.text, ""))
    end
    print(io, covered ? "</table:covered-table-cell>" : "</table:table-cell>")
    return
end

# The cells of a stored row, with empty cells between runs.
function write_row_cells(io::IO, runs::Vector{CellRun}, styles::StyleIndex; from::Int = 1, style_default = (c -> false),
                         display::Bool = true)
    col = from
    for run in runs
        run.col < col && continue
        run.col > col && write_cell(io, nothing, styles; repeat = Int(run.col) - col)
        write_cell(io, run.data, styles; repeat = Int(run.count), style_default = style_default(Int(run.col)), display)
        col = _lastcol(run) + 1
    end
    return col
end

const _EMPTY_ROW = "<table:table-row><table:table-cell/></table:table-row>"

function _write_empty_rows(io::IO, n::Integer)
    n <= 0 && return
    if n == 1
        print(io, _EMPTY_ROW)
    else
        print(io, "<table:table-row table:number-rows-repeated=\"", n, "\"><table:table-cell/></table:table-row>")
    end
end

"""
    write_rows(io, rows, styles, from)

Write stored rows (with empty rows before and between them) from row `from`; returns the
row after the last one written.
"""
function write_rows(io::IO, rows, styles::StyleIndex, from::Int; display::Bool = true)
    next = from
    for rd in rows
        rd.row < next && continue
        _write_empty_rows(io, Int(rd.row) - next)
        print(io, "<table:table-row")
        rd.count > 1 && print(io, " table:number-rows-repeated=\"", rd.count, "\"")
        print(io, '>')
        write_row_cells(io, rd.runs, styles; display)
        print(io, "</table:table-row>")
        next = _lastrow(rd) + 1
    end
    return next
end

"""
    write_table(io, ws)

A sheet made by ODSFiles, written whole: its columns, its rows from the store, and one
empty cell for an empty sheet (as LibreOffice writes one, F-015).
"""
function write_table(io::IO, ws::Worksheet; display::Bool = true)
    s = _cached_store(ws)
    styles = get_odsfile(ws).styles
    print(io, "<table:table table:name=\""); _escape_attr(io, ws.name); print(io, "\">")
    dim = store_dimension(s)
    ncols = dim === nothing ? 1 : column_number(dim.stop)
    print(io, "<table:table-column")
    ncols > 1 && print(io, " table:number-columns-repeated=\"", ncols, "\"")
    print(io, "/>")
    if isempty(s.rows)
        print(io, _EMPTY_ROW)
    else
        write_rows(io, s.rows, styles, 1; display)
    end
    print(io, "</table:table>")
end
