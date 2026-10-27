> 以下保留 AGY 的原始交付记录，包含当时的待办。当前发布状态与命令请以 README.md、release.json 和 ../docs/发布检查.md 为准。

# 拾影 · Framelet 官网交付与协同交接说明 (HANDOFF)

本文档面向父代理及后续协作者，记录拾影（Framelet）官方网站（`https://framelet.slnt.dev`）及隐冰室门户作品草稿的交付成果、本地验证方式、发布流程与当前已知缺口。

---

## 一、交付摘要

根据用户要求与《frontend-design》专业规范，本轮工作完成了纯静态、精致克制的中文 macOS 工具官网建设，并编写了适配 `yinbingshi.com` 门户的作品条目草稿。

- **目标域名**：`https://framelet.slnt.dev`
- **产品版本**：`v0.3.0 预览版` (Preview)
- **技术栈**：原生 HTML5 / CSS3 / 原生轻量 JavaScript，零运行时后端，部署目标为 Cloudflare Workers Static Assets。
- **设计风格**：深色专业 macOS 工具质感（Obsidian Slate 炭黑底色 + 细腻微边框），保留品牌标线紫（Precision Violet: `#6366F1`）作为准星、微调与取色点睛色，彻底摒弃通用的紫色渐变大卡片模板；
- **特色签名组件**：在首屏提供高保真交互模拟视窗（标注「交互示意」），支持长十字准星追踪、像素放大镜、sRGB HEX/RGB 即时取色、1px / 10px 键盘方向键微调，以及连续长截图高帧率拼接与固定页头保护演示；
- **严格遵循事实边界**：功能如实反映 0.3.0 现有特性，明确声明暂无录屏、暂无翻译、暂无数字序号、暂无自动机械滚动、暂无二次矢量编辑；无任何商业第三方（如 iShot）代码/素材引用；无虚构用户数或终身免费承诺；如实声明屏幕录制权限、离线 Vision OCR 及托管平台基础访问日志；
- **双态下载机制**：元数据集中在 `release.json`。默认 `available: false` 时按钮优雅显示为“下载即将开放 (预览版准备中)”，直达公证状态说明，杜绝假按钮与 404 坏链；待父代理完成公证后设为 `true` 即可自动点亮直链下载。

---

## 二、交付文件清单

所有修改均严格限制在当前 worktree 的 `website/` 目录，未改动 `Sources/`、`Resources/`、`scripts/` 或主目录任何文件。

| 文件路径 | 职责与内容说明 |
| :--- | :--- |
| `website/index.html` | 官网首页：Hero、取景器微交互视窗、六大核心特性矩阵、产品边界透明声明、行动区与页脚 |
| `website/privacy.html` | 隐私政策：说明屏幕录制权限用途、单层位图导出与遮挡安全、离线 Vision OCR、以及 Cloudflare 静态托管基础访问日志说明 |
| `website/releases.html` | 版本发布记录：0.3.0 预览版更新日志、局限与边界、系统要求 (macOS 14+)、签名公证进度与 SHA-256 校验指引 |
| `website/release.json` | 集中下载元数据接口 (`version`, `url`, `sha256`, `size`, `architecture`, `notarized`, `available`)，当前默认为待公证状态 |
| `website/yinbingshi-framelet.mdx` | 供父代理复制进 `yinbingshi_portal/content/work/framelet.mdx` 的作品展示草稿，链接为 `https://framelet.slnt.dev` 并标明预览版 |
| `website/wrangler.jsonc` | Cloudflare Workers Static Assets 配置文件（绑定 assets 目录与路由） |
| `website/wrangler.toml` | 兼容版 Cloudflare Wrangler 配置文件 |
| `website/assets/css/main.css` | 纯原生样式表：配色系统、响应式断点、macOS 原生字体栈、无障碍聚焦高亮与 `prefers-reduced-motion` |
| `website/assets/js/app.js` | 纯原生交互脚本：加载 `release.json` 动态切换下载态、驱动十字线/放大镜/原位工具栏/长图拼接模拟 |
| `website/assets/img/` | 由本仓库 `Resources/AppIcon.png` 无损生成的 Web 图标组 (1024/512/128/32px) |
| `website/README.md` | 官网技术说明与本地开发指南 |
| `website/HANDOFF.md` | 本交接文档 |

---

## 三、本地检查与验证命令

本交付已通过多项自动化与浏览器渲染测试，父代理可在本地重新执行以下命令验收：

### 1. 语法与链接有效性测试
```bash
# 验证 release.json 格式合法性
python3 -m json.tool website/release.json > /dev/null && echo "release.json 语法有效"

# 验证所有 HTML 内的本地相对路径、图片引用及 CSS/JS 是否全部有效
python3 -c "
import os, re
from html.parser import HTMLParser
class LinkCollector(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
    def handle_starttag(self, tag, attrs):
        for a, v in attrs:
            if a in ('href', 'src') and v and not v.startswith(('http', '#', 'mailto')):
                self.links.append(v.split('#')[0])
for root, _, files in os.walk('website'):
    for f in files:
        if f.endswith('.html'):
            p = os.path.join(root, f)
            with open(p) as fp:
                c = LinkCollector(); c.feed(fp.read())
            for l in c.links:
                if not os.path.exists(os.path.normpath(os.path.join(root, l))):
                    print(f'Broken link: {l} in {p}'); exit(1)
print('所有本地链接与资源引用均完整有效！')
"
```

### 2. 本地 HTTP 服务与响应测试
```bash
cd website
python3 -m http.server 8080
# 浏览器访问 http://localhost:8080/、privacy.html、releases.html
```

### 3. 无头浏览器渲染与截图测试 (macOS 原生 Headless Chrome)
```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
# 验证桌面端渲染 (1280x900)
"$CHROME" --headless --disable-gpu --window-size=1280,900 --screenshot=/tmp/framelet_desktop.png http://127.0.0.1:8080/
# 验证移动端视口无横向溢出 (375x812)
"$CHROME" --headless --disable-gpu --window-size=375,812 --screenshot=/tmp/framelet_mobile.png http://127.0.0.1:8080/
```

### 4. 下载未开放/开放两态切换测试
- **未开放状态**：当前 `website/release.json` 默认 `available: false`，首页主下载按钮呈现待发样式：“下载即将开放 (预览版准备中)”，无假链接。
- **开放状态模拟**：若将 `available` 改为 `true` 并赋予 `url`，主按钮自动更新为高亮可点击的“下载 Framelet 0.3.0”，展示文件大小与 SHA-256。

---

## 四、父代理后续发布接力流程

父代理负责打包、公证与正式分发，后续执行步骤建议如下：

1. **打包与公证**：
   - 使用钥匙串中的正式 Apple 开发者凭据完成 Universal 2 DMG 打包与公证：
     ```bash
     SIGNING_IDENTITY='Developer ID Application: 你的证书名称 (TEAMID)' UNIVERSAL=1 bash scripts/build.sh
     SIGNING_IDENTITY='Developer ID Application: 你的证书名称 (TEAMID)' bash scripts/package.sh
     NOTARY_PROFILE='你的钥匙串配置名' bash scripts/notarize.sh dist/Framelet-0.3.0.dmg
     ```
2. **回填下载元数据**：
   - 计算生成 DMG 的 SHA-256 与文件大小：
     ```bash
     shasum -a 256 dist/Framelet-0.3.0.dmg
     ls -lh dist/Framelet-0.3.0.dmg
     ```
   - 编辑 `website/release.json`，将 `available` 设为 `true`，`notarized` 设为 `true`，更新 `url`、`sha256` 与 `size`。
3. **部署官网至 Cloudflare**：
   - 在具备 Cloudflare 授权凭据的终端运行：
     ```bash
     cd website
     npx wrangler deploy
     ```
   - 在 Cloudflare DNS/Worker 路由中确保 `framelet.slnt.dev` 生效。
4. **集成至隐冰室门户**：
   - 将 `website/yinbingshi-framelet.mdx` 复制至门户仓库：
     `/Users/weidlu/workspace/yinbingshi_portal/content/work/framelet.mdx`
   - 在门户仓库执行构建预览并发布。

---

## 五、已知缺口与待办事项 (Gaps & Open Items)

1. **DMG 安装包未实际上线**：
   - 当前 Universal2 构建已验证 Developer ID 签名，但公证凭据尚待配置；因此 `release.json` 明确将 `available` 设为 `false`，界面显示“下载即将开放”。待父代理完成公证后更新发布。
2. **门户作品条目未写入门户 Git 仓库**：
   - 根据约束，本代理未直接修改 `/Users/weidlu/workspace/yinbingshi_portal/`；已在 `website/yinbingshi-framelet.mdx` 准备好完备的草稿，由父代理审阅后复制入库。
3. **未访问任何生产网络凭据**：
   - 本代理严格遵守指令，未执行 `git commit`、`git push` 或 `wrangler deploy`，所有修改均完整保存在当前工作区的 `website/` 目录中，等待父代理审阅并统筹集成。
