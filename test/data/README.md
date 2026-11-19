# Test fixtures

Regenerate them all with `fixtures/make_fixtures.sh` in the workspace root (D-011). The LibreOffice version is in `lo-version.txt`.

| File | Written by | How it was made |
|---|---|---|
| `lo-scenarios.ods`, `.fods`, `.ots` | LibreOffice | experiment 004's 15 hand-written scenario sheets (`fixtures/make_scenarios_fods.jl`), re-saved by LibreOffice headless |
| `lo-values.ods`, `.fods` | LibreOffice | experiment 007's 78 value and text cases (`experiments/007-lo-cell-values/build.jl`), re-saved |
| `lo-tables.ods`, `.fods` | LibreOffice | `fixtures/make_tables_fods.jl`: a table with gaps, named ranges and expressions (workbook and sheet-local), a merge, a hidden sheet, a quoted sheet name, formulas, re-saved |
| `lo-named-styles.ods`, `.fods` | LibreOffice (macro) | experiment 018: built-in styles applied over direct formatting, and user-defined styles ("My Style", "a&b", …), saved by its `Module1.bas` (`experiments/018-lo-named-styles/run.sh`) |
| `formula/lo-syntax.tsv`, `lo-names.tsv`, `lo-names2.tsv` | LibreOffice (`=FORMULA()`) | experiment 008: stored OpenFormula next to LibreOffice's UI notation; the oracle of `getFormula` |
| `core/*.tsv` | Excel 365 | copied from XLSX.jl (see `records/provenance.md`) |

The scenario sheets are S01-gaps, S02-identical, S03-col-style, S03b-col-style-cells, S03c-col-style-allrows, S03d-cell-style, S04-row-style, S05-styled-empty, S06-col-widths, S07-row-heights, S08-empty, S09-merge, S10-formula, S11-far and S12-types. What each one covers is described in `experiments/004-lo-repeats/README.md`.
