#!/bin/bash
# Renders every screen against fixture data and fails on accessibility, layout,
# or runtime problems. Usage: scripts/test-ui.sh [--screenshots DIR]
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT_DIR/target/ui"
SCREENSHOTS=""
[ "${1:-}" = "--screenshots" ] && SCREENSHOTS="$2"

rm -rf "$OUT"
mkdir -p "$OUT"
xcrun clang -fobjc-arc -fblocks -arch "$(uname -m)" -mmacosx-version-min=14.0 -DCONTINUITY_TESTING \
    -Wall -Wextra -Wno-unused-parameter -Werror -Wno-error=deprecated-declarations \
    -framework AppKit -framework CoreServices -framework QuartzCore -framework ServiceManagement -framework UserNotifications \
    "$ROOT_DIR"/macos-appkit/*.m -o "$OUT/Continuity-UI"

status=0
for fixture in demo empty; do
    mkdir -p "$OUT/$fixture" "$OUT/home-$fixture"
    set +e
    CFFIXED_USER_HOME="$OUT/home-$fixture" \
    CONTINUITY_AGENT_PATH="$ROOT_DIR/tests/ui/fake-agent.sh" \
    CONTINUITY_UI_FIXTURE="$fixture" \
    CONTINUITY_UI_MODE="$fixture" \
    CONTINUITY_UI_OUT="$OUT/$fixture" \
        perl -e 'alarm shift; exec @ARGV' 300 "$OUT/Continuity-UI" > "$OUT/$fixture.log" 2>&1
    code=$?
    set -e
    if [ "$code" -ne 0 ]; then
        echo "UI test ($fixture) failed with exit code $code"
        status=1
    fi
    if grep -E "Unable to simultaneously satisfy constraints|\*\*\* (Terminating|-\[|\+\[)" "$OUT/$fixture.log"; then
        echo "UI test ($fixture) logged runtime errors"
        status=1
    fi
    tail -n +1 "$OUT/$fixture/report.txt" 2>/dev/null || { echo "UI test ($fixture) wrote no report"; status=1; }
done

if [ -n "$SCREENSHOTS" ] && [ "$status" -eq 0 ]; then
    mkdir -p "$SCREENSHOTS"
    for appearance in light dark; do
        cp "$OUT/demo/demo-$appearance-1180-00.png" "$SCREENSHOTS/overview-$appearance.png"
        cp "$OUT/demo/demo-$appearance-tools-selected.png" "$SCREENSHOTS/developer-tools-$appearance.png"
        cp "$OUT/demo/demo-$appearance-1180-01.png" "$SCREENSHOTS/changes-$appearance.png"
        cp "$OUT/empty/empty-$appearance-1180-06.png" "$SCREENSHOTS/empty-state-$appearance.png"
    done
fi
exit "$status"
