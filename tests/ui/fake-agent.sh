#!/bin/bash
# Stands in for devcloud-agent in UI tests: replays a fixture with progress.
set -euo pipefail
fixture="$(dirname "$0")/${DEVCLOUD_UI_FIXTURE:-demo}-scan.json"
if [ -n "${DEVCLOUD_UI_SCAN_LOG:-}" ]; then printf 'scan\n' >> "$DEVCLOUD_UI_SCAN_LOG"; fi
if [ -n "${DEVCLOUD_UI_SCAN_DELAY:-}" ]; then sleep "$DEVCLOUD_UI_SCAN_DELAY"; fi
for step in "Reading package manager inventory" "Checking runtime managers and editor extensions" "Finishing inventory"; do
    echo "DEVCLOUD_PROGRESS|0|0|$step" >&2
done
python3 - "$fixture" <<'PY'
import json
import sys
import time

with open(sys.argv[1], encoding="utf-8") as source:
    envelope = json.load(source)
envelope["report"]["observed_at_unix_seconds"] = int(time.time())
json.dump(envelope, sys.stdout)
PY
