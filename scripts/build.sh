#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGURATION="${CONFIGURATION:-release}"
DESTINATION="$PWD/dist/Framelet.app"
if pgrep -f "^$DESTINATION/Contents/MacOS/Framelet([[:space:]]|$)" >/dev/null; then
    echo '请先退出正在运行的 dist/Framelet.app，再更新应用。' >&2
    exit 1
fi
mkdir -p dist
STAGE="$(mktemp -d "$PWD/dist/build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Framelet.app"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    bash scripts/swift.sh build -c "$CONFIGURATION" --arch arm64 --product Framelet
    ARM_DIR="$(bash scripts/swift.sh build -c "$CONFIGURATION" --arch arm64 --show-bin-path)"
    bash scripts/swift.sh build -c "$CONFIGURATION" --arch x86_64 --product Framelet
    INTEL_DIR="$(bash scripts/swift.sh build -c "$CONFIGURATION" --arch x86_64 --show-bin-path)"
    BIN_DIR="$PWD/.build/universal/$CONFIGURATION"
    mkdir -p "$BIN_DIR"
    lipo -create "$ARM_DIR/Framelet" "$INTEL_DIR/Framelet" -output "$BIN_DIR/Framelet"
else
    bash scripts/swift.sh build -c "$CONFIGURATION" --product Framelet
    BIN_DIR="$(bash scripts/swift.sh build -c "$CONFIGURATION" --show-bin-path)"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Framelet" "$APP/Contents/MacOS/Framelet"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi
if [[ -n "${BUNDLE_ID:-}" ]]; then /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"; fi
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
    echo "本地临时签名。正式发行请设置 SIGNING_IDENTITY 后重新构建。"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
if [[ -e "$DESTINATION" ]]; then mv "$DESTINATION" "$STAGE/Previous.app"; fi
if ! mv "$APP" "$DESTINATION"; then
    if [[ -e "$STAGE/Previous.app" ]]; then mv "$STAGE/Previous.app" "$DESTINATION"; fi
    exit 1
fi
echo "已构建：$DESTINATION"
