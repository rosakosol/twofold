#!/bin/zsh
#
# capture-site-screens.sh — the website's phone screenshots, taken from the real app.
#
# Launches a Debug build on a simulator in -demoMode (Twofold/Twofold/App/DemoMode.swift): the sample
# couple, Sam in Melbourne and Alex in Rome, with no backend and no real account. Captures each screen
# the site shows, in light and dark, and writes them to site/public/assets/phone-screen/ as
# <screen>-<light|dark>.webp. Re-run it whenever the app's look changes.
#
#   scripts/capture-site-screens.sh <path/to/Twofold.app> [simulator-udid]
#
# The .app is a Debug build for the simulator (demo mode does not exist in Release), e.g.
#   xcodebuild -project Twofold/Twofold.xcodeproj -scheme Twofold \
#     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/twofold-dd build
#   scripts/capture-site-screens.sh /tmp/twofold-dd/Build/Products/Debug-iphonesimulator/Twofold.app
#
# Use a simulator you don't mind changing: this installs the build on it, switches its appearance and
# pins its status bar to 9:41 while it runs, then puts the appearance back and clears the status bar.
# Needs python3 with Pillow for the WebP conversion.

set -euo pipefail

APP=${1:?usage: capture-site-screens.sh <Twofold.app> [simulator-udid]}
SIM=${2:-$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)}
[[ -n "$SIM" ]] || { echo "No booted simulator; boot one or pass its UDID." >&2; exit 1; }
BID=com.orangefinch.Twofold
ROOT=${0:A:h:h}
OUT="$ROOT/site/public/assets/phone-screen"
TMP=$(mktemp -d)
WAIT=${WAIT:-10}

# name : launch arguments after -demoMode
SCREENS=(
  "home:-demoTab home"
  "travel-trips:-demoTab travel"
  "travel-flights:-demoTab travel -demoTravelSegment flights"
  "flight-tracking:-demoScreen flight"
  "trip-details:-demoScreen trip"
  "memories-map:-demoTab memories"
  "memory-detail:-demoScreen memory"
  "games:-demoTab games"
  "stats:-demoTab stats"
  "connected:-demoScreen connected"
  "our-story:-demoScreen ourStory"
)

ORIGINAL_APPEARANCE=$(xcrun simctl ui "$SIM" appearance)
cleanup() {
  xcrun simctl ui "$SIM" appearance "$ORIGINAL_APPEARANCE" >/dev/null 2>&1 || true
  xcrun simctl status_bar "$SIM" clear >/dev/null 2>&1 || true
  xcrun simctl terminate "$SIM" "$BID" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

xcrun simctl install "$SIM" "$APP"
xcrun simctl status_bar "$SIM" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi

for mode in light dark; do
  xcrun simctl ui "$SIM" appearance $mode
  for spec in $SCREENS; do
    name=${spec%%:*}
    args=(${=spec#*:})
    xcrun simctl launch --terminate-running-process "$SIM" "$BID" -demoMode $args >/dev/null
    end=$((SECONDS + WAIT)); until (( SECONDS >= end )); do sleep 1; done
    xcrun simctl io "$SIM" screenshot "$TMP/$name-$mode.png" >/dev/null 2>&1
    echo "  $name-$mode"
  done
done

mkdir -p "$OUT"
python3 - "$TMP" "$OUT" <<'PY'
import os, sys
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
for f in sorted(os.listdir(src)):
    im = Image.open(os.path.join(src, f)).convert("RGB")
    im.save(os.path.join(out, f.replace(".png", ".webp")), "WEBP", quality=88, method=6)
    print(f"{f[:-4]}.webp {im.width}x{im.height}")
PY
