#!/bin/zsh
#
# capture-app-store-screens.sh — App Store screenshots from the real app, at the display's own size.
#
# Same demo-mode screens as capture-site-screens.sh (Twofold/Twofold/App/DemoMode.swift: the sample
# couple, Sam in Melbourne and Alex in Rome, no backend, no real account), saved as PNG at the
# simulator's native resolution — which is the size App Store Connect asks for — rather than
# converted for the website.
#
#   scripts/capture-app-store-screens.sh <path/to/Twofold.app> [simulator-udid] [out-dir]
#
# The .app is a Debug build for the simulator (demo mode does not exist in Release); see the header
# of capture-site-screens.sh for the build command.
#
# iPhone Duo has two displays, so simctl needs to be told which one to capture. SCREEN picks it, by
# the screen ID `xcrun simctl io <udid> enumerate` reports:
#
#   SCREEN=1  the outer display, 1398 x 2034 px — the size App Store Connect lists for it
#   SCREEN=3  the inner display, 2007 x 2853 px upright (2853 x 2007 opened like a book)
#
# Only the display the device is using draws anything. A Duo simulator boots closed, on the outer
# display, and simctl has no way to unfold it: unfold it from the simulator's own window first, then
# capture SCREEN=3. Leave SCREEN unset on a single-display iPhone.
#
# Light and dark, like the site set. Writes <out-dir>/<screen>-<light|dark>.png; out-dir defaults to
# ./app-store-screens.

set -euo pipefail

APP=${1:?usage: capture-app-store-screens.sh <Twofold.app> [simulator-udid] [out-dir]}
SIM=${2:-$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)}
[[ -n "$SIM" ]] || { echo "No booted simulator; boot one or pass its UDID." >&2; exit 1; }
OUT=${3:-app-store-screens}
BID=com.orangefinch.Twofold
WAIT=${WAIT:-10}
DISPLAY_ARGS=()
[[ -n "${SCREEN:-}" ]] && DISPLAY_ARGS=(--display="$SCREEN")

# name : launch arguments after -demoMode
SCREENS=(
  "home:-demoTab home"
  "travel-trips:-demoTab travel"
  "travel-flights:-demoTab travel -demoTravelSegment flights"
  "memories-map:-demoTab memories"
  "memory-detail:-demoScreen memory"
  "games:-demoTab games"
  "our-story:-demoScreen ourStory"
)

ORIGINAL_APPEARANCE=$(xcrun simctl ui "$SIM" appearance)
cleanup() {
  xcrun simctl ui "$SIM" appearance "$ORIGINAL_APPEARANCE" >/dev/null 2>&1 || true
  xcrun simctl status_bar "$SIM" clear >/dev/null 2>&1 || true
  xcrun simctl terminate "$SIM" "$BID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$OUT"
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
    xcrun simctl io "$SIM" screenshot $DISPLAY_ARGS "$OUT/$name-$mode.png" >/dev/null 2>&1
    echo "  $OUT/$name-$mode.png $(sips -g pixelWidth -g pixelHeight "$OUT/$name-$mode.png" | awk '/pixel/ {printf "%s ", $2}')"
  done
done
