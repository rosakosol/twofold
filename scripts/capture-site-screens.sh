#!/bin/zsh
#
# capture-site-screens.sh — the website's phone screenshots, taken from the real app.
#
# Launches a Debug build on a simulator in -demoMode (Twofold/Twofold/App/DemoMode.swift): the sample
# couple, Sam in Melbourne and Alex in Rome, with no backend and no real account. Captures each screen
# the site shows, in light and dark, and writes them to site/public/assets/phone-screen/ as
# <screen>-<light|dark>-<set>.webp. Re-run it whenever the app's look changes, with SET one higher than
# CAPTURE_SET in site/src/lib/marketing/phoneScreens.ts, then bump CAPTURE_SET to match: the image
# optimiser caches by URL, so new captures need new file names.
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
SET=${SET:?set SET to the new capture set number, see the header}

# name : launch arguments after -demoMode
SCREENS=(
  "home:-demoTab home"
  "travel-trips:-demoTab travel"
  "travel-flights:-demoTab travel -demoTravelSegment flights"
  "memories-map:-demoTab memories"
  "memory-detail:-demoScreen memory"
  "games:-demoTab games"
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
python3 - "$TMP" "$OUT" "$SET" <<'PY'
import os, sys
from PIL import Image
src, out, cset = sys.argv[1], sys.argv[2], sys.argv[3]
for f in sorted(os.listdir(src)):
    im = Image.open(os.path.join(src, f)).convert("RGB")
    im.save(os.path.join(out, f.replace(".png", f"-{cset}.webp")), "WEBP", quality=88, method=6)
    print(f"{f[:-4]}-{cset}.webp {im.width}x{im.height}")
PY
