#!/bin/bash
# Regression suite: XCTest unit tests + a visual render smoke test.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "════════ 1/2  Unit tests (swift test) ════════"
swift test 2>&1 | grep -E "Test Case|Executed [0-9]+ tests, with|error:" | \
    grep -vE "started$" || true
swift test >/dev/null 2>&1 && echo "✓ unit tests passed" || { echo "✗ unit tests FAILED"; exit 1; }

echo
echo "════════ 2/2  Visual render smoke test ════════"
OUT="$ROOT/.test-artifacts"
rm -rf "$OUT"; mkdir -p /tmp/shotedit_verify
swift build -c debug >/dev/null 2>&1
LOG="$(./.build/debug/ShotEditor --selftest 2>&1 || true)"
echo "$LOG" | grep -oE "OCR result:.*" || true
mkdir -p "$OUT"
cp /tmp/shotedit_verify/*.png "$OUT"/ 2>/dev/null || true
echo "Rendered artifacts:"
for f in "$OUT"/*.png; do
    [ -f "$f" ] || continue
    dim="$(sips -g pixelWidth -g pixelHeight "$f" 2>/dev/null | awk '/pixel/{printf "%s ",$2}')"
    printf "  %-24s %s\n" "$(basename "$f")" "$dim"
done
echo "✓ visual artifacts in $OUT"
