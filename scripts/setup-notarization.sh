#!/bin/bash
# Run interactively in your own terminal. Do not send passwords to an agent/chat.
set -euo pipefail
PROFILE="${1:-Framelet}"
: "${TEAM_ID:?请将 TEAM_ID 设置为你的 Apple Developer Team ID}"
echo '接下来由 Apple notarytool 提示输入 Apple ID 和 App 专用密码。'
echo '密码将保存在本机钥匙串中，不会写入此项目。请勿输入 Apple ID 主密码。'
xcrun notarytool store-credentials "$PROFILE" --team-id "$TEAM_ID"
echo "已配置公证 profile：$PROFILE"
