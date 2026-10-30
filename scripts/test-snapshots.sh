#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT_DIR/target/tests"
xcrun clang -fobjc-arc -fblocks -mmacosx-version-min=14.0 \
    -Wall -Wextra -Werror -Wno-error=deprecated-declarations -framework Foundation \
    -I"$ROOT_DIR/macos-appkit" "$ROOT_DIR/tests/ui/SnapshotStoreTest.m" \
    "$ROOT_DIR/macos-appkit/SnapshotStore.m" "$ROOT_DIR/macos-appkit/SnapshotComparison.m" -o "$ROOT_DIR/target/tests/snapshots"
"$ROOT_DIR/target/tests/snapshots"
