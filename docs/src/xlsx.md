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
- **Not yet available:** formatting, sheet operations, Excel-style tables, comments,
  images and charts, and the table and layout keywords of `writetable` (`as_table`,
  `column_widths`, `freeze_header`, ...).
