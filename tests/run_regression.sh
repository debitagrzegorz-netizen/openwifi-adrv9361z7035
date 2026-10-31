#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Entry point for on-board tests. --matrix runs the P22 feature matrix.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [ "${1:-}" = "--matrix" ]; then
  shift
  exec "$ROOT/tests/feature_matrix.sh" "$@"
fi
echo "usage: $0 --matrix [--image NAME]" >&2
exit 2
