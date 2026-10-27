#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${NOTARY_PROFILE:?请设置已保存在钥匙串中的 notarytool profile 名称，不要在脚本中写入密码。}"
DMG="${1:?用法：NOTARY_PROFILE=配置名 bash scripts/notarize.sh dist/Framelet-0.2.0.dmg}"
[[ -f "$DMG" ]] || { echo "安装包不存在" >&2; exit 1; }
codesign --verify --verbose=2 "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > dist/notarization-result.json
python3 -c 'import json; d=json.load(open("dist/notarization-result.json")); print(d["status"]); assert d["status"] == "Accepted", "公证未通过，请查看 Apple 公证日志"'
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
shasum -a 256 "$DMG" > "$DMG.sha256"
echo "公证通过并已附加票据；尚未公开发布。"
