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
xcrun clang -fobjc-arc -fblocks -arch "$(uname -m)" -mmacosx-version-min=14.0 -DDEVCLOUD_TESTING \
    -Wall -Wextra -Wno-unused-parameter -Werror -Wno-error=deprecated-declarations \
    -framework AppKit -framework CoreServices -framework QuartzCore -framework Security -framework ServiceManagement -framework UserNotifications \
    "$ROOT_DIR"/macos-appkit/*.m -o "$OUT/DevCloud-UI"

status=0
for fixture in demo empty; do
    mkdir -p "$OUT/$fixture" "$OUT/home-$fixture"
    roots=""
    if [ "$fixture" = demo ]; then
        for name in api-server web-app design-system notes; do
            mkdir -p "$OUT/home-$fixture/Developer/$name"
            roots="$roots${roots:+:}$OUT/home-$fixture/Developer/$name"
        done
        # Earlier change points, so Activity shows a timeline.
        python3 - "$ROOT_DIR/tests/ui/demo-scan.json" "$OUT/home-$fixture/Library/Application Support/DevCloud/History" <<'PY'
import copy, json, os, sys, time
report = json.load(open(sys.argv[1]))["report"]
history = sys.argv[2]
os.makedirs(history, mode=0o700, exist_ok=True)
now = int(time.time())
first = copy.deepcopy(report)
first["observed_at_unix_seconds"] = now - 3 * 86400
first["resources"] = [r for r in first["resources"] if r["canonical_tool_id"] != "uv"]
for r in first["resources"]:
    if r["canonical_tool_id"] == "nodejs" and r.get("path_status") == "first_on_path": r["version"] = "22.9.0"
    if r["canonical_tool_id"] == "gh": r["version"] = "2.59.0"
first["resources"].append({"canonical_tool_id": "yarn", "display_name": "Yarn", "kind": "package_manager", "version": "1.22.22",
    "installation_provider": "homebrew_formula", "provider_package_id": "yarn", "installation_instance_id": "local-yarn",
    "discovery_adapter": "homebrew_formula", "evidence": ["installed package directory"]})
second = copy.deepcopy(first)
second["observed_at_unix_seconds"] = now - 86400
second["resources"] = [r for r in second["resources"] if r["canonical_tool_id"] != "yarn"]
for r in second["resources"]:
    if r["canonical_tool_id"] == "gh": r["version"] = "2.60.1"
third = copy.deepcopy(report)
third["observed_at_unix_seconds"] = now - 600
for snapshot in (first, second, third):
    with open(os.path.join(history, "scan-%d-1-0.json" % snapshot["observed_at_unix_seconds"]), "w") as f:
        json.dump(snapshot, f)
with open(os.path.join(history, "latest.json"), "w") as f:
    json.dump(third, f)
PY
    fi
    set +e
    CFFIXED_USER_HOME="$OUT/home-$fixture" \
    DEVCLOUD_AGENT_PATH="$ROOT_DIR/tests/ui/fake-agent.sh" \
    DEVCLOUD_UI_FIXTURE="$fixture" \
    DEVCLOUD_UI_ROOTS="$roots" \
    DEVCLOUD_TOOL_ICONS_DIR="$ROOT_DIR/resources/tool-icons" \
    DEVCLOUD_UI_MODE="$fixture" \
    DEVCLOUD_UI_OUT="$OUT/$fixture" \
        perl -e 'alarm shift; exec @ARGV' 300 "$OUT/DevCloud-UI" > "$OUT/$fixture.log" 2>&1
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
        for page in overview workspaces configurations activity settings; do
            cp "$OUT/demo/demo-$appearance-1180-$page.png" "$SCREENSHOTS/$page-$appearance.png"
        done
        cp "$OUT/demo/demo-$appearance-tool-selected.png" "$SCREENSHOTS/tools-$appearance.png"
        cp "$OUT/demo/demo-$appearance-menu-bar.png" "$SCREENSHOTS/menu-bar-$appearance.png"
        cp "$OUT/demo/demo-$appearance-sheet-exportReport.png" "$SCREENSHOTS/export-$appearance.png"
        cp "$OUT/demo/demo-$appearance-sheet-approveWorkspace.png" "$SCREENSHOTS/add-workspace-$appearance.png"
    done
fi
exit "$status"
