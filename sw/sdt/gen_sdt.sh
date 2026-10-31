#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Batch sdtgen wrapper. sdtgen takes a positional Tcl file. It has no -source
# flag, and the Tcl interpreter has no version command.
set -euo pipefail

usage() {
  echo "usage: $0 --xsa FILE --out DIR" >&2
  exit 2
}

XSA=""
OUT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --xsa) XSA=${2:-}; shift 2 ;;
    --out) OUT=${2:-}; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$XSA" ] && [ -n "$OUT" ] && [ -f "$XSA" ] || usage

if [ -z "${SDTGEN:-}" ]; then
  if [ -n "${TOOLS_ROOT:-}" ] && [ -x "${TOOLS_ROOT}/Vitis/bin/sdtgen" ]; then
    SDTGEN=${TOOLS_ROOT}/Vitis/bin/sdtgen
  elif command -v sdtgen >/dev/null 2>&1; then
    SDTGEN=$(command -v sdtgen)
  else
    echo "sdtgen not found; set SDTGEN or TOOLS_ROOT" >&2
    exit 2
  fi
fi

mkdir -p "$OUT"
tcl=$(mktemp)
cleanup() { rm -f "$tcl"; }
trap cleanup EXIT
cat >"$tcl" <<EOF
set_dt_param -xsa {${XSA}} -dir {${OUT}} -debug enable
generate_sdt
puts "P22_SDT_DONE"
EOF

echo "sdtgen=$SDTGEN"
"$SDTGEN" -help >"${OUT}/sdtgen-help.txt" 2>&1 || true
"$SDTGEN" "$tcl"
test -f "${OUT}/system-top.dts"
test -f "${OUT}/pl.dtsi"
echo "P22_SDT_FILES"
find "$OUT" -type f | sort
