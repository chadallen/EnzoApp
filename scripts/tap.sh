#!/usr/bin/env bash
# tap.sh — thin idb wrapper for simulator UI interactions
#
# Usage:
#   scripts/tap.sh tap <x> <y>
#   scripts/tap.sh swipe <x_start> <y_start> <x_end> <y_end> [duration_secs]
#   scripts/tap.sh type <text>
#
# Resolves the booted simulator UDID automatically via xcrun simctl.
# Exits with an error if no simulator is booted.
#
# idb binary: ~/.venv/idb312/bin/idb (Python 3.12 venv — 3.14 is incompatible)

set -euo pipefail

IDB="$HOME/.venv/idb312/bin/idb"

# Resolve booted simulator UDID
UDID=$(xcrun simctl list devices booted --json 2>/dev/null \
  | python3 -c "
import json, sys
d = json.load(sys.stdin)
devs = [v for vs in d['devices'].values() for v in vs if v['state'] == 'Booted']
print(devs[0]['udid'] if devs else '')
" 2>/dev/null)

if [[ -z "$UDID" ]]; then
  echo "Error: no booted simulator found. Boot one first:" >&2
  echo "  xcrun simctl boot 'iPhone 17'" >&2
  exit 1
fi

SUBCOMMAND="${1:-}"
if [[ -z "$SUBCOMMAND" ]]; then
  echo "Usage:" >&2
  echo "  scripts/tap.sh tap <x> <y>" >&2
  echo "  scripts/tap.sh swipe <x_start> <y_start> <x_end> <y_end> [duration]" >&2
  echo "  scripts/tap.sh type <text>" >&2
  exit 1
fi
shift

case "$SUBCOMMAND" in
  tap)
    "$IDB" ui tap "$1" "$2" --udid "$UDID"
    ;;
  swipe)
    X_START="$1"; Y_START="$2"; X_END="$3"; Y_END="$4"
    DURATION="${5:-}"
    if [[ -n "$DURATION" ]]; then
      "$IDB" ui swipe "$X_START" "$Y_START" "$X_END" "$Y_END" --duration "$DURATION" --udid "$UDID"
    else
      "$IDB" ui swipe "$X_START" "$Y_START" "$X_END" "$Y_END" --udid "$UDID"
    fi
    ;;
  type|text)
    "$IDB" ui text "$1" --udid "$UDID"
    ;;
  *)
    echo "Error: unknown subcommand '$SUBCOMMAND'" >&2
    echo "Usage:" >&2
    echo "  scripts/tap.sh tap <x> <y>" >&2
    echo "  scripts/tap.sh swipe <x_start> <y_start> <x_end> <y_end> [duration]" >&2
    echo "  scripts/tap.sh type <text>" >&2
    exit 1
    ;;
esac
