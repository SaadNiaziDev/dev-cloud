#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT_DIR/target/icon-test"
mkdir -p "$OUT"
python3 "$ROOT_DIR/tests/validate-icons.py" "$ROOT_DIR/resources/tool-icons"
xcrun clang -fobjc-arc -fblocks -mmacosx-version-min=14.0 -DCONTINUITY_TESTING \
    -Wall -Wextra -Wno-unused-parameter -Werror -framework AppKit \
    -I"$ROOT_DIR/macos-appkit" "$ROOT_DIR/tests/tool-icons.m" "$ROOT_DIR/macos-appkit/ToolIcons.m" -o "$OUT/test"
"$OUT/test" "$ROOT_DIR/resources/tool-icons"
