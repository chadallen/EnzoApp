#!/usr/bin/env bash
# launch.sh — build, install, and launch EnzoApp on the booted simulator.
#
# Usage:
#   bash scripts/launch.sh          # build then launch
#   bash scripts/launch.sh --no-build  # install+launch from last build only
#
# Requires a booted simulator. Boot one first if needed:
#   xcrun simctl boot "iPhone 17"

set -euo pipefail

BUNDLE_ID="chadallen.EnzoApp"
SCHEME="EnzoApp"
DERIVED_DATA=~/Library/Developer/Xcode/DerivedData

NO_BUILD=false
for arg in "$@"; do
  [[ "$arg" == "--no-build" ]] && NO_BUILD=true
done

# Ensure a simulator is booted
UDID=$(xcrun simctl list devices booted --json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
devs = [v for vs in d['devices'].values() for v in vs if v['state'] == 'Booted']
print(devs[0]['udid'] if devs else '')
" 2>/dev/null)

if [[ -z "$UDID" ]]; then
  echo "No booted simulator. Booting iPhone 17..."
  xcrun simctl boot "iPhone 17"
  sleep 5
  UDID=$(xcrun simctl list devices booted --json 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
devs = [v for vs in d['devices'].values() for v in vs if v['state'] == 'Booted']
print(devs[0]['udid'] if devs else '')
" 2>/dev/null)
fi

echo "Simulator: $UDID"

# Build
if [[ "$NO_BUILD" == false ]]; then
  echo "Building $SCHEME..."
  xcodebuild build \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$UDID" \
    -quiet
  echo "Build succeeded."
fi

# Find .app
APP=$(find "$DERIVED_DATA" -name "EnzoApp.app" -path "*/Debug-iphonesimulator/*" 2>/dev/null | head -1)
if [[ -z "$APP" ]]; then
  echo "Error: EnzoApp.app not found in DerivedData. Run without --no-build first." >&2
  exit 1
fi
echo "App: $APP"

# Install and launch
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE_ID"
echo "Launched $BUNDLE_ID"
