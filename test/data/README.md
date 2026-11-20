# Test fixtures

Regenerate them all with `fixtures/make_fixtures.sh` in the workspace root (D-011). The LibreOffice version is in `lo-version.txt`.

| File | Written by | How it was made |
|---|---|---|
| `lo-scenarios.ods`, `.fods`, `.ots` | LibreOffice | experiment 004's 15 hand-written scenario sheets (`fixtures/make_scenarios_fods.jl`), re-saved by LibreOffice headless |
| `lo-values.ods`, `.fods` | LibreOffice | experiment 007's 78 value and text cases (`experiments/007-lo-cell-values/build.jl`), re-saved |
| `lo-tables.ods`, `.fods` | LibreOffice | `fixtures/make_tables_fods.jl`: a table with gaps, named ranges and expressions (workbook and sheet-local), a merge, a hidden sheet, a quoted sheet name, formulas, re-saved |
| `lo-named-styles.ods`, `.fods` | LibreOffice (macro) | experiment 018: built-in styles applied over direct formatting, and user-defined styles ("My Style", "a&b", …), saved by its `Module1.bas` (`experiments/018-lo-named-styles/run.sh`) |
| `shift/lo-shift-before.fods`, `lo-shift-refs.tsv`, `lo-shift-ops.tsv` | LibreOffice (macro) | experiment 021: a document holding every kind of reference, and the reference values LibreOffice stored after each of 28 row/column inserts and deletes (`experiments/021-lo-shift-refs/run.sh`, then `fixtures.jl`; the TSV is `out/refs.tsv` without cell values and the limit files). The oracle of reference shifting |
| `shift/lo-shift-quirks-before.fods`, `lo-shift-quirks.tsv`, `lo-shift-quirks-ops.tsv` | LibreOffice (macro) | experiment 021 part B: ranges ending at the sheet's last row or column, relative and absolute, above and below 13 edits; the formulas LibreOffice stored after each (`run_quirks.sh`, then `fixtures.jl`) |
| `shift/lo-sheetops-refs.tsv`, `lo-sheetops-ops.tsv`, `lo-sheetops-quirks-before.fods` | LibreOffice (macro) | experiment 022 and its part B: every reference value after 19 rename, delete, copy, move and insert operations on `lo-shift-before.fods`, and 6 more on a copy with extra charts and names (`lo-sheetops-quirks-before.fods`); formulas keyed by sheet (`experiments/021-lo-shift-refs/fixtures.jl`) |
| `formula/lo-syntax.tsv`, `lo-names.tsv`, `lo-names2.tsv` | LibreOffice (`=FORMULA()`) | experiment 008: stored OpenFormula next to LibreOffice's UI notation; the oracle of `getFormula` |
| `core/*.tsv` | Excel 365 | copied from XLSX.jl (see `records/provenance.md`) |

The scenario sheets are S01-gaps, S02-identical, S03-col-style, S03b-col-style-cells, S03c-col-style-allrows, S03d-cell-style, S04-row-style, S05-styled-empty, S06-col-widths, S07-row-heights, S08-empty, S09-merge, S10-formula, S11-far and S12-types. What each one covers is described in `experiments/004-lo-repeats/README.md`.
