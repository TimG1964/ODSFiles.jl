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
- **Not yet available:** sheet operations, Excel-style tables, conditional formats,
  comments, images and charts, and `writetable`'s `as_table` and `freeze_header`.
