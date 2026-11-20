```@meta
CurrentModule = ODSFiles
```

# API reference

```@docs
ODSFiles
```

## Files and sheets

```@docs
readods
openods
newods
writeods
saveods
ODSFile
Worksheet
sheetnames
sheetcount
hassheet
addsheet!
ODSError
```

## Reading cells

```@docs
getdata
readdata
getcell
getcellrange
get_dimension
Cell
EmptyCell
iserror
geterror
getFormula
SheetRow
Base.eachrow(::Worksheet)
row_number
column_number
CellRef
SheetCellRef
```

## Tables

```@docs
readtable
gettable
eachtablerow
readto
DataTable
TableRow
TableRowIterator
```

## Writing

```@docs
setdata!
setFormula
writetable
writetable!
streamods
StreamWriter
StreamSheet
writerow!
writerows!
```

## Rows and columns

Inserting and deleting rows and columns moves every reference to them as LibreOffice moves it:
formulas on every sheet, defined names, merges, conditional formats, validations, database
ranges, print ranges, charts and anchored shapes.

```@docs
insertRows
insertColumns
deleteRows
deleteColumns
```

## Sheet operations

Renaming, deleting, copying and moving sheets, with references following as they follow in
LibreOffice.

```@docs
renamesheet!
deletesheet!
copysheet!
movesheet!
```

## Formatting

Fonts, fills, borders and alignment:

```@docs
setFont
setFill
setBorder
setOutsideBorder
setAlignment
getFont
getFill
getBorder
getAlignment
getDefaultFont
CellFont
CellFill
CellBorder
CellAlignment
```

Number formats and the text a cell shows:

```@docs
setFormat
getFormat
CellFormat
getText
```

Uniform formatting:

```@docs
setUniformFont
setUniformFill
setUniformBorder
setUniformAlignment
setUniformFormat
setUniformStyle
```

Column widths and row heights:

```@docs
setColumnWidth
getColumnWidth
setRowHeight
getRowHeight
autofitColumns
```

Named cell styles:

```@docs
setCellStyle
getCellStyle
addCellStyle!
```

Merged cells:

```@docs
mergeCells
removeMergedCells
getMergedCells
isMergedCell
getMergedBaseCell
```

## The shared core

The format-independent parts of ODSFiles (references, tables, number formats, dates) live in
a submodule meant to be shared with XLSX.jl in future. It is not part of the public API.

```@docs
ODSFiles.SheetCore
```
