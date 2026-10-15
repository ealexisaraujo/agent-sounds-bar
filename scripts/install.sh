#!/bin/bash
# Developer wrapper around the app's own command line (the app does the real work).
#
#   install.sh                      install play-sound and the default settings
#   install.sh --rewire claude      also connect Claude Code's hooks (claude | codex | all)
#   add --dry-run to print what would change and write nothing
#
# Codex pins a trusted_hash per hook in ~/.codex/config.toml, so connecting it may make
# Codex ask you to re-approve the changed hooks.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/AgentSoundsBar.app/Contents/MacOS/AgentSoundsBar"
[ -x "$BIN" ] || "$ROOT/build.sh"

DRY=(); REWIRE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=(--dry-run) ;;
    --rewire)  REWIRE="${2:-}"; shift ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
case "$REWIRE" in ""|claude|codex|all) ;; *) echo "--rewire takes claude, codex or all" >&2; exit 2 ;; esac

"$BIN" setup ${DRY[@]+"${DRY[@]}"}
[ -n "$REWIRE" ] && "$BIN" connect "$REWIRE" ${DRY[@]+"${DRY[@]}"}
exit 0
