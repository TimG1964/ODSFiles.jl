#!/usr/bin/env bash
# Benchmark fixtures: XLSX.jl 0.13.4's own (bench/fixtures in the XLSX-Cursor checkout, read
# only), copied to fixtures/xlsx/, and LibreOffice's .ods conversions of them in fixtures/.
# The *_rw copies are left out (they are the same files). Both folders are git-ignored.
set -e
cd "$(dirname "$0")"
SRC="${XLSX_BENCH_FIXTURES:-../../../XLSX-Cursor/XLSX.jl/bench/fixtures}"
S="/c/Program Files/LibreOffice/program/soffice.com"
PROF="file:///$(cygpath -m "$PWD/fixtures/lo-profile")"
mkdir -p fixtures/xlsx
for f in "$SRC"/*.xlsx "$SRC"/*.xlsm; do
  case "$f" in *_rw.xlsx) continue ;; esac
  cp -u "$f" fixtures/xlsx/
done
for f in fixtures/xlsx/*; do
  base=$(basename "${f%.*}")
  [ -f "fixtures/$base.ods" ] && continue
  echo "converting $base"
  timeout 900 "$S" -env:UserInstallation="$PROF" --headless --norestore \
    --convert-to ods --outdir "$(cygpath -w fixtures)" "$(cygpath -w "$f")" >/dev/null 2>&1
done
ls -la fixtures fixtures/xlsx
