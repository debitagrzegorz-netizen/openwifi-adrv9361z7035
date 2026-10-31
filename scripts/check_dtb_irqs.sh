#!/bin/bash
# Assert the P04 PL→PS interrupt map in a system DTB.
# In n → SPI 29+n (n=0..7) and SPI 44+n (n=8..15). SoftMAC index 1/3 = SPI 30/34.
# Usage: check_dtb_irqs.sh <system.dtb>
set -euo pipefail

DTB=${1:-}
if [ -z "$DTB" ] || [ ! -f "$DTB" ]; then
  echo "FAIL: usage: $0 <system.dtb>" >&2
  exit 2
fi

FDTGET=""
for c in \
  "${FDTGET:-}" \
  fdtget
do
  if [ -n "$c" ] && command -v "$c" >/dev/null 2>&1; then
    FDTGET=$c
    break
  fi
  if [ -n "$c" ] && [ -x "$c" ]; then
    FDTGET=$c
    break
  fi
done
if [ -z "$FDTGET" ]; then
  echo "FAIL: fdtget not found" >&2
  exit 2
fi

rc=0
fail() {
  echo "FAIL: $*" >&2
  rc=1
}

# Walk every node. fdtget -l prints child names, one per line.
mapfile -t ALL < <(
  walk() {
    local node="$1" child path
    while IFS= read -r child; do
      [ -z "$child" ] && continue
      if [ "$node" = "/" ]; then
        path="/$child"
      else
        path="$node/$child"
      fi
      printf '%s\n' "$path"
      walk "$path"
    done < <("$FDTGET" -l "$DTB" "$node" 2>/dev/null || true)
  }
  walk /
)

cells() {
  "$FDTGET" -t u "$DTB" "$1" interrupts 2>/dev/null || true
}

expect_node() {
  local suffix="$1" want="$2" found=0 path got
  for path in "${ALL[@]}"; do
    case "$path" in
      */"$suffix"|"$suffix")
        found=1
        got=$(cells "$path")
        if [ "$got" = "$want" ]; then
          echo "PASS: $path interrupts = $got"
        else
          fail "$path interrupts = '${got:-<missing>}' (want '$want')"
        fi
        ;;
    esac
  done
  if [ "$found" -eq 0 ]; then
    fail "node $suffix not found"
  fi
}

expect_node "sdr" "0 29 1 0 30 1 0 33 1 0 34 1"
expect_node "dma@80400000" "0 35 4 0 36 4"
expect_node "dma@80400000/dma-channel@80400000" "0 35 4"
expect_node "dma@80400000/dma-channel@80400030" "0 36 4"
expect_node "dma@80410000" "0 31 4 0 32 4"
expect_node "dma@80410000/dma-channel@80410000" "0 31 4"
expect_node "dma@80410000/dma-channel@80410030" "0 32 4"
expect_node "i2c@41600000" "0 58 4"

if [ "$rc" -eq 0 ]; then
  echo "check_dtb_irqs.sh: PASS ($DTB)"
else
  echo "check_dtb_irqs.sh: FAIL ($DTB)" >&2
fi
exit "$rc"
