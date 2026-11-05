#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT_DIR/target/tests"
xcrun clang -fobjc-arc -fblocks -mmacosx-version-min=14.0 -Wall -Wextra -Werror \
    -Wno-error=deprecated-declarations -framework Foundation -I"$ROOT_DIR/macos-appkit" \
    "$ROOT_DIR/tests/ui/RecoveryPlanTest.m" "$ROOT_DIR/macos-appkit/RecoveryPlan.m" \
    "$ROOT_DIR/macos-appkit/CloudInventory.m" -o "$ROOT_DIR/target/tests/recovery-plan"
"$ROOT_DIR/target/tests/recovery-plan"
xcrun clang -fobjc-arc -fblocks -mmacosx-version-min=14.0 -Wall -Wextra -Werror \
    -framework Foundation -I"$ROOT_DIR/macos-appkit" \
    "$ROOT_DIR/tests/ui/SetupFileTest.m" "$ROOT_DIR/macos-appkit/SetupFile.m" \
    "$ROOT_DIR/macos-appkit/CloudInventory.m" -o "$ROOT_DIR/target/tests/setup-file"
"$ROOT_DIR/target/tests/setup-file"
