#!/usr/bin/env bash
# screenshot.sh — capture a simulator screenshot with a timestamped filename
# Usage: scripts/screenshot.sh
# Output: scripts/screenshots/enzo-YYYY-MM-DD-HHMMSS.png
#         scripts/screenshots/latest.png  (symlink → timestamped file)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCREENSHOTS_DIR="$SCRIPT_DIR/screenshots"

mkdir -p "$SCREENSHOTS_DIR"

TIMESTAMP="$(date +%Y-%m-%d-%H%M%S)"
FILENAME="enzo-${TIMESTAMP}.png"
FILEPATH="$SCREENSHOTS_DIR/$FILENAME"

xcrun simctl io booted screenshot "$FILEPATH"

# Update the latest.png symlink (relative target so it works portably)
ln -sf "$FILENAME" "$SCREENSHOTS_DIR/latest.png"

echo "$FILEPATH"
