# Saving: `writeods`, `saveods`, and the parts of a new document.
#
# Adapted from XLSX.jl 0.13.4 (src/save.jl `writexlsx`, `savexlsx`, `_reset_io_for_save!`,
# `_check_overwrite`), MIT License, Copyright (c) 2018-2026 Felipe Noronha Tavares and other
# contributors. A file that was read is saved by patching its parts (D-023); a new one is
# written whole, in ODF 1.4 by default (D-006).

const _NS_DECL = join([" xmlns:$p=\"$u\"" for (p, u) in vcat(_NAMESPACES, [
    "meta" => "urn:oasis:names:tc:opendocument:xmlns:meta:1.0",
    "dc" => "http://purl.org/dc/elements/1.1/",
    "xlink" => "http://www.w3.org/1999/xlink"])])

const _STYLES_BODY = """<office:styles><style:default-style style:family="table-cell"/><style:style style:name="Default" style:family="table-cell"/></office:styles>"""

_generator() = "ODSFiles.jl/$(pkgversion(@__MODULE__))"

function _meta_body()
    now = Dates.format(Dates.now(Dates.UTC), "yyyy-mm-ddTHH:MM:SS")
    return "<office:meta><meta:generator>$(_generator())</meta:generator><meta:creation-date>$now</meta:creation-date></office:meta>"
end

function _body(xf::ODSFile; display::Bool = true)
    io = IOBuffer()
    print(io, "<office:body><office:spreadsheet>")
    foreach(ws -> write_table(io, ws; display), xf.sheets)
    print(io, "</office:spreadsheet></office:body>")
    return String(take!(io))
end

const _XMLDECL = """<?xml version="1.0" encoding="UTF-8"?>\n"""

new_content_xml(xf::ODSFile, version; display::Bool = true) =
    string(_XMLDECL, "<office:document-content", _NS_DECL, " office:version=\"", version, "\">",
           "<office:automatic-styles>", typed_styles_xml(xf.styles), "</office:automatic-styles>",
           _body(xf; display), "</office:document-content>")

new_styles_xml(version) =
    string(_XMLDECL, "<office:document-styles", _NS_DECL, " office:version=\"", version, "\">",
           _STYLES_BODY, "<office:automatic-styles/><office:master-styles/></office:document-styles>")

new_meta_xml(version) =
    string(_XMLDECL, "<office:document-meta", _NS_DECL, " office:version=\"", version, "\">", _meta_body(), "</office:document-meta>")

new_flat_xml(xf::ODSFile, version, mediatype; display::Bool = true) =
    string(_XMLDECL, "<office:document", _NS_DECL, " office:version=\"", version, "\" office:mimetype=\"", mediatype, "\">",
           _meta_body(), _STYLES_BODY, "<office:automatic-styles>", typed_styles_xml(xf.styles), "</office:automatic-styles>",
           _body(xf; display), "</office:document>")

# :ods, :ots or :fods, for a destination.
function _output_format(dest, xf::ODSFile)
    if dest isa AbstractString
        ext = lowercase(splitext(dest)[2])
        ext == ".fods" && return :fods
        ext == ".ots" && return :ots
        ext == ".ods" && return :ods
    end
    return isnewfile(xf) ? :ods : xf.container.format
end

_mediatype(fmt::Symbol) = fmt === :ots ? MEDIATYPE_OTS : MEDIATYPE_ODS

function _check_overwrite(dest, overwrite::Bool)
    dest isa AbstractString && !overwrite && isfile(dest) &&
        throw(ODSError("$dest already exists. Use `overwrite=true` to replace it."))
end

# The parts of a zipped file that was read, with content.xml patched (D-023).
function _patched_parts(xf::ODSFile; display::Bool = true)
    cont = xf.container
    mts = Dict(e.path => e.mediatype for e in cont.manifest)
    content = patched_content(xf; display)
    parts = PackagePart[]
    for name in partnames(cont)
        name in _RESERVED_PARTS && continue
        if endswith(name, "/")                   # a directory entry: kept, as an empty folder
            push!(parts, PackagePart(name, UInt8[]; mediatype = get(mts, name, ""), compress = false))
            continue
        end
        data = name == "content.xml" ? content : read_bytes(cont, name)
        mt = get(mts, name, guess_mediatype(name))
        push!(parts, PackagePart(name, data; mediatype = isempty(mt) ? guess_mediatype(name) : mt))
    end
    return parts
end

"""
    writeods(dest, xf::ODSFile; overwrite=false, version="1.4") -> path or nothing

Write `xf` to `dest`, a file path or an `IO`.

- The format follows the extension of a path: `.ods`, `.ots` (a template) or `.fods` (flat
  XML). Writing to an `IO` keeps the format the file was read in (`.ods` for a new one).
- A file that was read is written by patching it (D-023): what ODSFiles does not edit is
  kept exactly as it was. It can be written as a template or a document, but not converted
  between zipped and flat XML yet.
- A new file is written in ODF 1.4, or 1.3 with `version="1.3"` (D-006).
- `display_text=false` leaves out the display text (`text:p`) of the number, date, time and
  boolean cells that ODSFiles writes; readers recompute it from the value. Files are then
  smaller (about half, for numeric data) and faster to write (D-029).
- An existing file at `dest` is only replaced with `overwrite=true`.

A path becomes the file's new `source` (for [`saveods`](@ref)). Returns the absolute path,
or `nothing` for an `IO`.
"""
function writeods(dest::Union{AbstractString,IO}, xf::ODSFile; overwrite::Bool = false,
                  version::AbstractString = DEFAULT_ODF_VERSION, display_text::Bool = true)
    _check_overwrite(dest, overwrite)
    display = display_text
    fmt = _output_format(dest, xf)
    mt = _mediatype(fmt)
    if isnewfile(xf)
        _check_version(version)
        if fmt === :fods
            write_flat(dest, new_flat_xml(xf, version, mt; display))
        else
            parts = [PackagePart("content.xml", new_content_xml(xf, version; display)),
                     PackagePart("styles.xml", new_styles_xml(version)),
                     PackagePart("meta.xml", new_meta_xml(version))]
            write_package(dest, parts; mediatype = mt, version)
        end
    else
        wasflat = xf.container.format === :fods
        wasflat == (fmt === :fods) ||
            throw(ODSError("Can't write a file read as $(wasflat ? "flat XML (.fods)" : "a zipped package") as $(wasflat ? "a zipped package" : "flat XML (.fods)") yet."))
        if fmt === :fods
            write_flat(dest, patched_content(xf; display))
        else
            v = xf.version in WRITABLE_ODF_VERSIONS ? xf.version : DEFAULT_ODF_VERSION
            write_package(dest, _patched_parts(xf; display); mediatype = mt, version = v)
        end
    end
    if dest isa AbstractString
        xf.source = String(dest)
        xf.source_io = nothing
        return abspath(dest)
    end
    return nothing
end

"""
    saveods(xf::ODSFile)

Save `xf` back to where it was opened from: its file, or the `IO` it was read from (which
must be writable and seekable; its content is replaced). A file made with
[`newods`](@ref) has nowhere to go: use [`writeods`](@ref).
"""
function saveods(xf::ODSFile)
    _require_writable(xf, "save the file")
    if xf.source_io !== nothing
        io = xf.source_io
        try
            seekstart(io)
            truncate(io, 0)
        catch e
            e isa InterruptException && rethrow()
            throw(ODSError("Can't save back to the source `IO`: it must be writable and seekable. Use `writeods` to write elsewhere. ($(sprint(showerror, e)))"))
        end
        writeods(io, xf)
        xf.source_io = io
        return nothing
    end
    (xf.source == "blank.ods" || xf.source in ("IOBuffer", "IO")) &&
        throw(ODSError("This file has no file name to save to. Use `writeods(path, xf)`."))
    return writeods(xf.source, xf; overwrite = true)
end
