# Reading content.xml only as far as one sheet (phase 3). All sheets share content.xml, so a
# one-shot read of the first sheet (`readtable`, `readdata`) would otherwise inflate them
# all. The inflated bytes are searched for the sheet's start tag (by name or number) and
# then for its end tag; inflating stops there. The prefix is everything the readers need:
# the styles come before the body, and the sheet index ends cleanly at the end of the data.
# Anything unusual (a table nested in the sheet, an end tag written otherwise) makes the
# whole part be read instead.

mutable struct _SheetFinder
    want_name::Union{Nothing,String}
    want_index::Int
    scan::Int          # where to search next
    count::Int         # sheets seen
    start::Int         # the target's start tag (0: not found yet)
    giveup::Bool
end

const _TABLE_OPEN = Vector{UInt8}("<table:table")
const _TABLE_CLOSE = Vector{UInt8}("</table:table>")
const _NAME_RX = r"table:name\s*=\s*(?:\"([^\"]*)\"|'([^']*)')"

@inline _is_space_or_gt(b::UInt8) = b == UInt8(' ') || b == UInt8('\t') || b == UInt8('\n') || b == UInt8('\r') || b == UInt8('>')

# The next "<table:table" that opens a table element (not table:table-row, …) from `i`.
function _next_table_open(v, i::Int, n::Int)
    while true
        r = findnext(_TABLE_OPEN, v, i)
        r === nothing && return nothing
        k = last(r) + 1
        k > n && return 0                       # can't tell yet: wait for more data
        _is_space_or_gt(v[k]) && return first(r)
        i = first(r) + 1
    end
end

function _find_sheet_end!(f::_SheetFinder, data::Vector{UInt8}, n::Int)
    f.giveup && return nothing
    v = view(data, 1:n)
    while f.start == 0
        p = _next_table_open(v, f.scan, n)
        if p === nothing || p == 0
            f.scan = p == 0 ? f.scan : max(1, n - length(_TABLE_OPEN) + 1)
            return nothing
        end
        gt = findnext(==(UInt8('>')), v, p)
        gt === nothing && (f.scan = p; return nothing)          # the tag is cut: wait
        f.count += 1
        m = match(_NAME_RX, String(v[p:gt]))
        name = m === nothing ? "" : XML.unescape(something(m.captures[1], m.captures[2]))
        found = f.want_name === nothing ? f.count == f.want_index : name == f.want_name
        f.scan = gt + 1
        found && (f.start = p)
    end
    r = findnext(_TABLE_CLOSE, v, f.scan)
    if r === nothing
        f.scan = max(f.start + 1, n - length(_TABLE_CLOSE) + 1)
        return nothing
    end
    nested = _next_table_open(v, f.start + 1, n)
    if nested !== nothing && nested != 0 && nested < first(r)
        f.giveup = true                          # a table inside the sheet: read it all
        return nothing
    end
    return last(r)
end

"""
    content_through_sheet(c::ODFContainer, sheet) -> String

content.xml inflated only as far as the end of `sheet` (a name or a 1-based number), or the
whole document when that can't be told (a flat document, or a sheet not found by its exact
name).
"""
function content_through_sheet(c::ODFContainer, sheet::Union{AbstractString,Integer})
    c.zip === nothing && return c.flat
    f = sheet isa Integer ? _SheetFinder(nothing, Int(sheet), 1, 0, 0, false) :
                            _SheetFinder(SheetCore.unquoteit(String(sheet)), 0, 1, 0, 0, false)
    return readentry_prefix((data, n) -> _find_sheet_end!(f, data, n), c.zip, "content.xml")
end
