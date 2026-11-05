#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# A separate bundle ID and name keep this test app away from the installed
# version's settings and screen-recording authorization. It is not a store build.
DESTINATION="$PWD/dist/Framelet-Sandbox-Check.app"
if pgrep -f "^$DESTINATION/Contents/MacOS/Framelet([[:space:]]|$)" >/dev/null; then
    echo '请先退出正在运行的拾影沙盒验收版。' >&2
    exit 1
fi
bash scripts/swift.sh build -c debug --product Framelet
BIN_DIR="$(bash scripts/swift.sh build -c debug --show-bin-path)"
mkdir -p dist
STAGE="$(mktemp -d "$PWD/dist/sandbox-check.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Framelet-Sandbox-Check.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Framelet" "$APP/Contents/MacOS/Framelet"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.framelet.capture.sandboxcheck' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Framelet Sandbox Check' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName 拾影沙盒验收' "$APP/Contents/Info.plist"

IDENTITY="${SIGNING_IDENTITY:--}"
codesign --force --options runtime --entitlements Resources/FrameletAppStore.entitlements --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
if [[ -e "$DESTINATION" ]]; then mv "$DESTINATION" "$STAGE/Previous.app"; fi
if ! mv "$APP" "$DESTINATION"; then
    if [[ -e "$STAGE/Previous.app" ]]; then mv "$STAGE/Previous.app" "$DESTINATION"; fi
    exit 1
fi
echo "沙盒验收版：${DESTINATION}（不用于 App Store 上传）"
