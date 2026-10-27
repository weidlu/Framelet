#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/Framelet.app"
[[ -d "$APP" ]] || { echo "请先运行 scripts/build.sh" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$PWD/dist/Framelet-$VERSION.dmg"
[[ ! -e "$DMG" ]] || { echo "安装包已存在，请先重命名旧版本：$DMG" >&2; exit 1; }
STAGE="$(mktemp -d "$PWD/dist/dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Framelet.app"
ln -s /Applications "$STAGE/Applications"
cp docs/使用说明.txt "$STAGE/使用说明.txt"
hdiutil create -volname '拾影 Framelet' -srcfolder "$STAGE" -ov -format UDZO "$DMG"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"; fi
shasum -a 256 "$DMG" > "$DMG.sha256"
echo "已生成：$DMG"
echo "此命令不会公证或发布。公证后请重新生成 SHA-256。"
