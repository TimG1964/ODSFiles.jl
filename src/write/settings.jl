# settings.xml (or a flat document's office:settings) after sheet operations (phase 5, D-053):
# the entries keyed by sheet name follow renames, deletes and copies, as LibreOffice keeps them
# (F-047): each view's per-sheet entries (`Tables`), the sheets' code names
# (`ScriptConfiguration`), and the active sheet (`ActiveTable`). Everything else is kept as it is.

const _SHEET_MAPS = ("Tables", "ScriptConfiguration")

# Applies `f` to the content of every named map holding entries keyed by sheet name.
function _in_sheet_maps(f::Function, s::String)
    for m in _SHEET_MAPS
        open_tag = "<config:config-item-map-named config:name=\"$m\">"
        i = 1
        while (r = findnext(open_tag, s, i)) !== nothing
            a = last(r) + 1
            z = findnext("</config:config-item-map-named>", s, a)
            z === nothing && break
            inner = f(String(SubString(s, a, prevind(s, first(z)))), m)
            s = s[1:last(r)] * inner * s[first(z):end]
            i = last(r) + ncodeunits(inner) + 1
        end
    end
    return s
end

_entry_open(name) = "<config:config-item-map-entry config:name=\"" * _escape_attr(name) * "\">"

# The span of the entry for `name` in a map's content, or nothing.
function _entry_span(inner::String, name::String)
    r = findfirst(_entry_open(name), inner)
    r === nothing && return nothing
    z = findnext("</config:config-item-map-entry>", inner, last(r))
    z === nothing && return nothing
    return first(r):last(z)
end

const _ACTIVE_RX = r"(<config:config-item config:name=\"ActiveTable\" config:type=\"string\">)([^<]*)(</config:config-item>)"

function _set_active(s::String, f::Function)
    return replace(s, _ACTIVE_RX => m -> begin
        mm = match(_ACTIVE_RX, m)
        cur = XML.unescape(mm.captures[2])
        new = f(cur)
        mm.captures[1] * _escape_attr(new) * mm.captures[3]
    end)
end

function _settings_rename(s::String, old::String, new::String)
    s = _in_sheet_maps(s) do inner, _
        sp = _entry_span(inner, old)
        sp === nothing && return inner
        replace(inner, _entry_open(old) => _entry_open(new); count = 1)
    end
    return _set_active(s, cur -> _same_sheet(cur, old) ? new : cur)
end

function _settings_delete(s::String, name::String, order::Vector{String})
    s = _in_sheet_maps(s) do inner, _
        sp = _entry_span(inner, name)
        sp === nothing ? inner : inner[1:prevind(inner, first(sp))] * inner[nextind(inner, last(sp)):end]
    end
    i = _sheet_index(order, name)
    other = i === nothing || length(order) < 2 ? "" : i > 1 ? order[i - 1] : order[2]
    return _set_active(s, cur -> _same_sheet(cur, name) ? other : cur)
end

function _settings_copy(s::String, src::String, dst::String)
    return _in_sheet_maps(s) do inner, m
        if m == "ScriptConfiguration"
            inner * _entry_open(dst) * "<config:config-item config:name=\"CodeName\" config:type=\"string\">" *
                _escape_attr(dst) * "</config:config-item></config:config-item-map-entry>"
        else
            sp = _entry_span(inner, src)
            sp === nothing ? inner : inner * replace(inner[sp], _entry_open(src) => _entry_open(dst); count = 1)
        end
    end
end

# Whether settings.xml changes: after sheet operations, a change of a sheet's visibility, or view
# settings set (phase 5 step 8).
_settings_edited(xf::ODSFile) = any(op -> !(op isa LineShift), xf.ops) || xf.tstyles.shown_changed || _views_edited(xf)

"""
    patched_settings(xf, s) -> String

The settings `s` (settings.xml, or a flat document's office:settings) after the sheet operations
in `xf.ops`, in order, and with the active sheet moved off a sheet that was hidden (phase 5 step 6).
"""
function patched_settings(xf::ODSFile, s::String)
    s = _settings_ops(xf, s)
    xf.tstyles.shown_changed && (s = _settings_shown(xf, s))     # src/write/sheetprops.jl
    return _settings_views(xf, s)                               # src/write/views.jl
end

# The settings after the sheet operations alone.
function _settings_ops(xf::ODSFile, s::String)
    for op in xf.ops
        if op isa SheetRename
            s = _settings_rename(s, op.old, op.new)
        elseif op isa SheetDelete
            s = _settings_delete(s, op.name, op.order)
        elseif op isa SheetCopy
            s = _settings_copy(s, op.src, op.dst)
        end
    end
    return s
end
