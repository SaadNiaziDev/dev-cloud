#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT_DIR/target/monitoring-test"
mkdir -p "$OUT/home"
rm -f "$OUT/scans.log"
xcrun clang -fobjc-arc -fblocks -arch "$(uname -m)" -mmacosx-version-min=14.0 -DDEVCLOUD_TESTING \
    -Wall -Wextra -Wno-unused-parameter -Werror -Wno-error=deprecated-declarations \
    -framework AppKit -framework CoreServices -framework ServiceManagement -framework UserNotifications \
    -I"$ROOT_DIR/macos-appkit" "$ROOT_DIR/tests/ui/ScanModelTest.m" "$ROOT_DIR/macos-appkit/ScanModel.m" -o "$OUT/test"
CFFIXED_USER_HOME="$OUT/home" \
DEVCLOUD_AGENT_PATH="$ROOT_DIR/tests/ui/fake-agent.sh" \
DEVCLOUD_UI_FIXTURE=demo \
DEVCLOUD_UI_SCAN_LOG="$OUT/scans.log" \
DEVCLOUD_UI_SCAN_DELAY=4 \
    "$OUT/test"
