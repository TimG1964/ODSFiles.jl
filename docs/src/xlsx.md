```@meta
CurrentModule = ODSFiles
```

# Coming from XLSX.jl

ODSFiles follows XLSX.jl's interface, so most code needs only its file names changed:

| XLSX.jl | ODSFiles |
|---|---|
| `XLSX.readxlsx`, `XLSX.openxlsx` | [`readods`](@ref), [`openods`](@ref) |
| `XLSX.newxlsx`, `XLSX.writexlsx`, `XLSX.savexlsx` | [`newods`](@ref), [`writeods`](@ref), [`saveods`](@ref) |
| `XLSX.streamxlsx` | [`streamods`](@ref) |
| `XLSXFile`, `XLSXError` | [`ODSFile`](@ref), [`ODSError`](@ref) |

These work as in XLSX.jl: `readtable`, `gettable`, `eachtablerow`, `readdata`, `getdata`,
indexing, `getcell`, `getcellrange`, `eachrow`, `iserror`, `geterror`, `setdata!`,
`writetable`, `writetable!`, `addsheet!`, `writerow!`, `writerows!` and the Tables.jl
interface.

The formatting functions work as in XLSX.jl too, with the differences listed in
[Formatting](guide/formatting.md):
- `setFont`, `setFill`, `setBorder`, `setAlignment`, `setFormat` and their getters
- the `setUniform*` variants and `setOutsideBorder`
- `getText`
- `mergeCells` and the other merge functions
- `setColumnWidth`, `setRowHeight`, their getters and `autofitColumns`
- `writetable`'s `column_widths` and `column_formats`

## Differences

- **References** print in LibreOffice's notation (`Sheet1.A1`); Excel's (`Sheet1!A1`) is
  still accepted. Lists of areas can also use `~`.
- **Formulas** read and write in LibreOffice's notation (`=SUM(Sheet2.A1:B2,1)`), not
  Excel's.
- **Durations:** a time cell of 24 hours or more, or a negative one, reads as a
  `Dates.CompoundPeriod`, not a `Time`.
- **Cells:** a [`Cell`](@ref) holds its decoded value, its value type as a symbol, its
  style's name and its formula text, rather than XLSX.jl's internal indices.
- **Error codes** are the text LibreOffice shows, including its own `Err:NNN`.
- **Saving an edited file** keeps everything not edited, rather than rewriting the file.
- **`display_text=false`** (no XLSX.jl counterpart) writes smaller files; see
  [Saving and writing](@ref).
- **Formatting** works on ODF's styles: setters return a style name, getters work on
  read-only files, and empty cells and whole columns are formatted as LibreOffice formats
  them. ODSFiles also has named cell styles ([`setCellStyle`](@ref), [`addCellStyle!`](@ref)),
  which XLSX.jl lacks. See [Formatting](guide/formatting.md).
- **Inserting and deleting rows and columns** ([`insertRows`](@ref), [`insertColumns`](@ref),
  [`deleteRows`](@ref), [`deleteColumns`](@ref)) take XLSX.jl's arguments and behave as
  LibreOffice does: a deleted reference is stored as `#REF!` without its sheet, 3-D references
  follow, new rows copy the formatting of the row above (borders included), and new columns
  that of the column to their left, with the width of the column they push right.
- **Sheet operations** ([`renamesheet!`](@ref), [`deletesheet!`](@ref), [`copysheet!`](@ref),
  [`movesheet!`](@ref)) take XLSX.jl's arguments and behave as LibreOffice does; a copy repoints only
  references whose sheet name is relative, and a name already in use is an error.
- **Defined names** ([`addDefinedName`](@ref), [`deleteDefinedName`](@ref),
  [`deleteAllDefinedNames`](@ref), [`getDefinedNames`](@ref), [`getAllDefinedNames`](@ref)) take
  XLSX.jl's arguments, with LibreOffice's rules: a name may hold `?` but not `\`, and names such
  as `C1x` that LibreOffice reads as references are refused. A sheet's name may refer to another
  sheet, whole columns and rows can be named, and `Bool` constants stay `Bool`. A formula's
  sheet names without `$` are relative, as in LibreOffice. ODF has no system names, so `force` and
  `include_system` change nothing.
- **Hiding** ([`setRowHidden`](@ref), [`setColumnHidden`](@ref), [`setSheetVisibility`](@ref)) and
  **tab colours** ([`setTabColor`](@ref)) take XLSX.jl's arguments. ODF has no very hidden sheets:
  `:veryHidden` hides a sheet as `:hidden` does, as LibreOffice imports Excel's. Theme colours are
  not accepted, as elsewhere in ODSFiles.
- **Grouping** ([`groupRows`](@ref), [`groupColumns`](@ref), [`ungroupRows`](@ref),
  [`ungroupColumns`](@ref)) takes XLSX.jl's arguments, but follows LibreOffice, whose groups are
  nested containers rather than Excel's levels per line: groups next to each other stay separate,
  ungrouping removes a whole group (and lifts the groups inside it), and a range that crosses a
  group, or an eighth level, is an error.
- **Panes and the sheet view** ([`freezePanes`](@ref), [`splitPanes`](@ref), [`setSheetView`](@ref),
  [`getSheetView`](@ref)) take XLSX.jl's arguments and are kept as LibreOffice keeps them, in its view
  settings: the page-break view, row and column headers and zeros are the whole file's; a selection
  is kept as its cursor only; zoom runs from 20 to 600; LibreOffice has no page layout view and no
  "frozen split" (`splitFreeze` freezes). A split's position is in screen pixels, so it falls at the
  edge of the rows and columns given on a 96-dpi screen at 100% zoom.
- **Not yet available:**
  Excel-style tables, conditional formats, comments, images and charts, and `writetable`'s
  `as_table` and `freeze_header`.
