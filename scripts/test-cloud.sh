#!/bin/bash
# Cloud upload format and client checks. With DEVCLOUD_TEST_API_URL (a local server) plus
# DEVCLOUD_TEST_TOKEN or DEVCLOUD_TEST_APPROVE, also backs up, downloads, deletes and signs out.
# The management fixture is separate and must target a disposable loopback service.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT_DIR/target/tests"
xcrun clang -fobjc-arc -fblocks -mmacosx-version-min=14.0 -DDEVCLOUD_TESTING \
    -Wall -Wextra -Werror -Wno-unused-parameter -Wno-error=deprecated-declarations -framework AppKit -framework Security \
    -I"$ROOT_DIR/macos-appkit" "$ROOT_DIR/tests/ui/CloudTest.m" \
    "$ROOT_DIR/macos-appkit/CloudAccount.m" "$ROOT_DIR/macos-appkit/CloudInventory.m" "$ROOT_DIR/macos-appkit/CloudUploadQueue.m" "$ROOT_DIR/macos-appkit/CloudUploadStore.m" -o "$ROOT_DIR/target/tests/cloud"
DEVCLOUD_NO_BROWSER=1 DEVCLOUD_TEST_REPORT="$ROOT_DIR/tests/ui/demo-scan.json" "$ROOT_DIR/target/tests/cloud"
xcrun clang -fobjc-arc -fblocks -mmacosx-version-min=14.0 \
    -Wall -Wextra -Werror -Wno-unused-parameter -Wno-error=deprecated-declarations -framework Foundation \
    -I"$ROOT_DIR/macos-appkit" "$ROOT_DIR/tests/ui/CloudQueueTest.m" \
    "$ROOT_DIR/macos-appkit/CloudUploadQueue.m" "$ROOT_DIR/macos-appkit/CloudUploadStore.m" \
    "$ROOT_DIR/macos-appkit/CloudInventory.m" -o "$ROOT_DIR/target/tests/cloud-queue"
"$ROOT_DIR/target/tests/cloud-queue"
xcrun clang -fobjc-arc -fblocks -mmacosx-version-min=14.0 -DDEVCLOUD_TESTING \
    -Wall -Wextra -Werror -Wno-unused-parameter -Wno-error=deprecated-declarations -framework AppKit -framework Security \
    -I"$ROOT_DIR/macos-appkit" "$ROOT_DIR/tests/ui/CloudManagementTest.m" \
    "$ROOT_DIR/macos-appkit/CloudAccount.m" "$ROOT_DIR/macos-appkit/CloudInventory.m" \
    "$ROOT_DIR/macos-appkit/CloudUploadQueue.m" "$ROOT_DIR/macos-appkit/CloudUploadStore.m" -o "$ROOT_DIR/target/tests/cloud-management"
"$ROOT_DIR/target/tests/cloud-management"
if [ -n "${DEVCLOUD_TEST_MANAGEMENT_API:-}" ]; then
    xcrun clang -fobjc-arc -fblocks -mmacosx-version-min=14.0 -DDEVCLOUD_TESTING \
        -Wall -Wextra -Werror -Wno-unused-parameter -Wno-error=deprecated-declarations -framework AppKit -framework Security \
        -I"$ROOT_DIR/macos-appkit" "$ROOT_DIR/tests/ui/CloudManagementLive.m" \
        "$ROOT_DIR/macos-appkit/CloudAccount.m" "$ROOT_DIR/macos-appkit/CloudInventory.m" \
        "$ROOT_DIR/macos-appkit/CloudUploadQueue.m" "$ROOT_DIR/macos-appkit/CloudUploadStore.m" -o "$ROOT_DIR/target/tests/cloud-management-live"
    "$ROOT_DIR/target/tests/cloud-management-live"
fi
