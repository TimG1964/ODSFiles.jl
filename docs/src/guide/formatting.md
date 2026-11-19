# Formatting

ODSFiles formats cells with XLSX.jl's functions: [`setFont`](@ref), [`setFill`](@ref),
[`setBorder`](@ref), [`setAlignment`](@ref) and [`setFormat`](@ref), with their getters and
uniform variants. They take XLSX.jl's address forms: a cell (`"B2"`), a range (`"B2:D4"`),
whole columns (`"A:C"`) or rows (`"3:5"`), a list of ranges (`"A1:B2,D4"`), a defined name,
a sheet-qualified reference on the file (`xf["Sheet1.A1"]` style: `setFont(xf, "Sheet1.A1"; …)`),
or rows and columns as integers, ranges, vectors or `:`.

```julia
using ODSFiles

xf = newods()
s = xf[1]
s["A1"] = "Total"
s["B1"] = 1234.5

setFont(s, "A1"; bold = true, size = 12, color = "darkblue")
setFill(s, "A1:B1"; pattern = "solid", fgColor = "FFF2CC")
setBorder(s, "A1:B1"; outside = ["style" => "medium"])
setAlignment(s, "B1"; horizontal = "right")
setFormat(s, "B1"; format = "#,##0.00")

ODSFiles.getText(s, "B1")      # "1,234.50"
writeods("report.ods", xf)
```

## How it differs from XLSX.jl

- **Empty cells are formatted**, as in LibreOffice. Whole columns and rows are formatted to
  the end of the sheet, not only up to the used area.
- **Styles, not tables.** ODF has no font, fill or border tables: a cell has a style, which
  ODSFiles derives from the cell's current one (named styles stay its parent). Setters return
  the new style's name for a single cell, and getters report the properties the cell's style
  resolves to, also on files opened read-only.
- **What ODF can't hold:** superscript and subscript (`vertAlign`) are refused; pattern fills
  are blended into one colour, as LibreOffice does when it opens an xlsx file.
- **Number formats** are stored as ODF data styles, in the form LibreOffice writes for the
  same code. [`getText`](@ref ODSFiles.getText) shows a value as LibreOffice shows it, which differs from Excel
  in places (General shows up to 15 significant digits, for example).
- **Merged cells** are an anchor cell and covered cells, as LibreOffice writes them.

The full list is in the workspace's `records/api-divergence.md`.
