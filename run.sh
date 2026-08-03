#!/bin/bash
# Build then launch ShotEditor.app
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${1:-debug}"
"$ROOT/build.sh" "$CONFIG"
echo "▸ Launching…"
# Kill previous instance if running
pkill -x ShotEditor 2>/dev/null || true
open "$ROOT/ShotEditor.app"
