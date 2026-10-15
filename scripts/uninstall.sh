#!/bin/bash
# Removes this app's sound hooks from Claude Code and Codex (restoring any commands it replaced).
# Leaves ~/.config/agent-sounds in place; delete it by hand if you want it gone.
#   uninstall.sh [--dry-run]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/AgentSoundsBar.app/Contents/MacOS/AgentSoundsBar"
[ -x "$BIN" ] || "$ROOT/build.sh"

"$BIN" disconnect all ${1:+"$1"}
