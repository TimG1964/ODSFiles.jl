```@meta
CurrentModule = ODSFiles
```

# References and names

## Cells and ranges

Within a sheet, references are the usual ones: `"B2"`, `"A1:C3"`, whole columns `"A:C"`,
whole rows `"2:4"`. `$` marks are accepted (`"$A$1"`). Several areas are joined with `,` or
LibreOffice's `~`:

```julia
sh["A1:A4,C1"]     # a vector of matrices, one per area
sh["A1:A4~C1"]     # the same
```

Rows and columns can also be given as numbers, ranges or vectors: `sh[2, 3]`,
`sh[2:5, [1, 3]]`, `sh[:, 2]`.

## Naming a sheet

ODSFiles reads and prints sheet-qualified references in LibreOffice's notation, and also
accepts Excel's:

| LibreOffice | Excel | |
|---|---|---|
| `Sheet1.A1` | `Sheet1!A1` | |
| `'My sheet'.A1:B2` | `'My sheet'!A1:B2` | quoted names |
| `$Sheet1.$A$1` | | absolute |
| `Sheet1.A1~Sheet1.C3` | `Sheet1!A1,Sheet1!C3` | lists |

```julia
xf["Sheet1.B2"]            # a value from the file
xf["'My sheet'!A1:C3"]
```

References that ODSFiles returns, such as `SheetCellRef`, print in LibreOffice's notation.

## Defined names

Named ranges and named expressions, for the whole file or for one sheet, can be used wherever
a reference can:

```julia
xf["Totals"]              # a workbook name
sh["LocalRange"]          # a name local to the sheet
```

A name whose expression is a constant gives that value. A name that is a formula can't be
read: ODSFiles does not evaluate formulas.

Sheet and defined names match without regard to case, as in LibreOffice.
