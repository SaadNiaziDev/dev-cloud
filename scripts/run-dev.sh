#!/bin/bash
# Builds a development app for this Mac's architecture in target/dev and opens it.
# DEVCLOUD_API_URL connects cloud backup to a server; use http://127.0.0.1:<port> for a
# local one. Without it the Backup page reports that this build has no cloud.
# DEVCLOUD_AGENT_BINARY reuses an already built scanner instead of running cargo.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/target/dev/DevCloud.app"
CONTENTS_DIR="$APP_DIR/Contents"
AGENT="${DEVCLOUD_AGENT_BINARY:-$ROOT_DIR/target/release/devcloud-agent}"
API="${DEVCLOUD_API_URL:-}"

if [ ! -x "$AGENT" ]; then
    command -v cargo >/dev/null || { echo "No scanner at $AGENT and cargo is unavailable; set DEVCLOUD_AGENT_BINARY." >&2; exit 1; }
    cargo build --release --locked --bin devcloud-agent
fi
DEFINES=()
ATS=""
if [ -n "$API" ]; then
    case "$API" in
        https://*) ;;
        http://127.0.0.1:*|http://localhost:*) ATS="<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>" ;;
        *) echo "DEVCLOUD_API_URL must be https:// or http://127.0.0.1:<port>." >&2; exit 1 ;;
    esac
    DEFINES=(-DDEVCLOUD_API_URL="\"$API\"")
fi

pkill -f "$CONTENTS_DIR/MacOS/DevCloud" 2>/dev/null || true
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Helpers" "$CONTENTS_DIR/Resources"
xcrun clang -fobjc-arc -fblocks -arch "$(uname -m)" -mmacosx-version-min=14.0 ${DEFINES[@]+"${DEFINES[@]}"} \
    -Wall -Wextra -Wno-unused-parameter -Werror -Wno-error=deprecated-declarations \
    -framework AppKit -framework CoreServices -framework QuartzCore -framework Security -framework ServiceManagement -framework UserNotifications \
    "$ROOT_DIR"/macos-appkit/*.m -o "$CONTENTS_DIR/MacOS/DevCloud"
xcrun clang -fobjc-arc -mmacosx-version-min=14.0 -framework AppKit -I"$ROOT_DIR/macos-appkit" \
    "$ROOT_DIR/scripts/make-icon.m" "$ROOT_DIR/macos-appkit/BrandMark.m" -o "$ROOT_DIR/target/dev/make-icon"
rm -rf "$ROOT_DIR/target/dev/AppIcon.iconset"
"$ROOT_DIR/target/dev/make-icon" "$ROOT_DIR/target/dev/AppIcon.iconset"
iconutil -c icns "$ROOT_DIR/target/dev/AppIcon.iconset" -o "$CONTENTS_DIR/Resources/AppIcon.icns"
cp "$AGENT" "$CONTENTS_DIR/Helpers/devcloud-agent"
cp -R "$ROOT_DIR/resources/tool-icons" "$CONTENTS_DIR/Resources/ToolIcons"
cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>DevCloud</string>
    <key>CFBundleIdentifier</key><string>dev.devcloud.desktop.mac.dev</string>
    <key>CFBundleName</key><string>DevCloud</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>development build</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    $ATS
</dict>
</plist>
PLIST
# Compiler-generated local symbol hashes are not part of the shipped interface.
strip -x "$CONTENTS_DIR/MacOS/DevCloud" "$CONTENTS_DIR/Helpers/devcloud-agent"
codesign --force --sign - "$CONTENTS_DIR/Helpers/devcloud-agent"
codesign --force --sign - "$APP_DIR"
open "$APP_DIR"
echo "Opened $APP_DIR${API:+ (cloud: $API)}"
