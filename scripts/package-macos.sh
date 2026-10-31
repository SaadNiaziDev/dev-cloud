#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_DIR="$ROOT_DIR/dist/DevCloud.app"
CONTENTS_DIR="$APP_DIR/Contents"
VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' "$ROOT_DIR/Cargo.toml" | head -1)"
SIGN_IDENTITY="${DEVCLOUD_SIGN_IDENTITY:--}"
NOTARY_PROFILE="${DEVCLOUD_NOTARY_PROFILE:-}"
if [ -n "$NOTARY_PROFILE" ] && [ "$SIGN_IDENTITY" = "-" ]; then
    echo "Notarization requires a Developer ID signing identity." >&2
    exit 1
fi

cargo build --release --locked --target aarch64-apple-darwin --bin devcloud-agent
cargo build --release --locked --target x86_64-apple-darwin --bin devcloud-agent
rm -rf "$APP_DIR"
mkdir -p "$ROOT_DIR/target/release" "$ROOT_DIR/dist" "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Helpers" "$CONTENTS_DIR/Resources"
xcrun clang -fobjc-arc -fblocks -arch arm64 -arch x86_64 -mmacosx-version-min=14.0 \
    -Wall -Wextra -Wno-unused-parameter -Werror -Wno-error=deprecated-declarations \
    -framework AppKit -framework CoreServices -framework QuartzCore -framework Security -framework ServiceManagement -framework UserNotifications \
    "$ROOT_DIR"/macos-appkit/*.m \
    -o "$ROOT_DIR/target/release/devcloud-desktop"
lipo -create \
    "$ROOT_DIR/target/aarch64-apple-darwin/release/devcloud-agent" \
    "$ROOT_DIR/target/x86_64-apple-darwin/release/devcloud-agent" \
    -output "$ROOT_DIR/target/release/devcloud-agent"
xcrun clang -fobjc-arc -mmacosx-version-min=14.0 -framework AppKit -I"$ROOT_DIR/macos-appkit" \
    "$ROOT_DIR/scripts/make-icon.m" "$ROOT_DIR/macos-appkit/BrandMark.m" -o "$ROOT_DIR/target/release/make-icon"
rm -rf "$ROOT_DIR/target/release/AppIcon.iconset"
"$ROOT_DIR/target/release/make-icon" "$ROOT_DIR/target/release/AppIcon.iconset"
iconutil -c icns "$ROOT_DIR/target/release/AppIcon.iconset" -o "$CONTENTS_DIR/Resources/AppIcon.icns"
cp -R "$ROOT_DIR/resources/tool-icons" "$CONTENTS_DIR/Resources/ToolIcons"
cp "$ROOT_DIR/target/release/devcloud-desktop" "$CONTENTS_DIR/MacOS/DevCloud"
cp "$ROOT_DIR/target/release/devcloud-agent" "$CONTENTS_DIR/Helpers/devcloud-agent"
cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>DevCloud</string>
    <key>CFBundleIdentifier</key><string>dev.devcloud.desktop.mac</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>DevCloud</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"
SIGN_ARGS=(--force --options runtime --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" != "-" ]; then SIGN_ARGS+=(--timestamp); fi
codesign "${SIGN_ARGS[@]}" "$CONTENTS_DIR/Helpers/devcloud-agent"
codesign "${SIGN_ARGS[@]}" "$APP_DIR"
# hdiutil occasionally fails with "Resource busy" on CI runners.
for attempt in 1 2 3; do
    hdiutil create -volname DevCloud -srcfolder "$APP_DIR" -ov -format UDZO "$ROOT_DIR/dist/DevCloud.dmg" && break
    [ "$attempt" = 3 ] && exit 1
    sleep 5
done
if [ -n "$NOTARY_PROFILE" ]; then
    xcrun notarytool submit "$ROOT_DIR/dist/DevCloud.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$ROOT_DIR/dist/DevCloud.dmg"
    xcrun stapler validate "$ROOT_DIR/dist/DevCloud.dmg"
fi
