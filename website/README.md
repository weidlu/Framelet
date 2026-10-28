# 拾影官网

正式地址：https://framelet.slnt.dev

纯静态中文站点，原生 HTML / CSS / JavaScript，没有构建步骤和外部依赖。源码在这个目录，只有公开页面与安装包会被复制到 `dist/website`，部署配置不会作为网站资源上传。

## 页面

| 文件 | 内容 |
| :--- | :--- |
| `index.html` | 首页：Hero、可切换工具的截图示意、四格事实、标注、精准瞄准、更多功能 bento、三步上手、隐私、常见问题、下载 |
| `privacy.html` | 隐私与权限说明 |
| `releases.html` | 版本日志、已知边界与安装包校验方式 |
| `release.json` | 版本、下载地址、SHA-256、公证状态等元数据 |
| `style.css` / `app.js` | 样式与交互：工具切换、进场动画、版本信息对话框、按 `release.json` 切换下载态 |
| `assets/shots/` | 界面截图，见下 |

## 本地预览

```sh
python3 -m http.server 8886 --bind 127.0.0.1 --directory website
```

`release.json` 通过 fetch 读取，所以要用 HTTP 打开；直接双击 `index.html` 时下载按钮会显示「下载暂未开放」。

## 界面素材

`assets/shots/` 里的截图全部来自拾影的真实界面，不是手绘或仿制。画面中的看板、对话、表格是虚构的示例内容，页面上已注明。

素材由临时渲染器生成（不在本仓库内）：把示例桌面喂给应用真实的 `RegionView` 与各面板，再用 ScreenCaptureKit 只截取本进程自己的窗口。

| 文件 | 场景 |
| :--- | :--- |
| `hero-{all,arrow,box,text,mosaic,redact}.webp` | 完整截图界面，按工具切换 |
| `toolbar.webp` | 选区下方的工具栏 |
| `loupe.webp` | 准星与像素放大镜 |
| `ocr.webp` | 真实 Vision 识别后的提取文字面板 |
| `privacy.webp` | 马赛克与遮挡 |
| `pin.webp` | 贴图窗口 |
| `scroll.webp` | 连续长截图面板，预览由应用真实 `ScrollStitcher` 拼接 |
| `countdown.webp` | 延时截图前的倒计时浮窗 |
| `settings.webp` | 设置窗口的快捷键页（只取上半部） |

换图时保持 `index.html` 里的 `width` / `height` 与实际尺寸一致，避免布局跳动。

## 校验与部署

```sh
python3 website/prepare-deploy.py
wrangler deploy --config website/wrangler.jsonc
```

`prepare-deploy.py` 会检查三个页面的本地链接、锚点与 SVG 引用，核对 `release.json` 与 `index.html` 里静态兜底的版本号、大小、SHA-256 是否一致，再按 `release.json` 的 `notarized` 状态校验 `dist/` 里的 DMG 哈希，最后把公开资源复制到 `dist/website`。安装包不提交进 Git。

Worker `framelet-website` 绑定 `framelet.slnt.dev`，不会影响主域 `slnt.dev` 的其他 Worker。

## 发布新版本

1. 完成签名、公证与附加票据，把新的 DMG 放进 `dist/`。
2. 更新 `release.json`（`version`、`url`、`sha256`、`size`、`sizeBytes`、`releaseDate`），把上一版放进 `previousReleases` 以便旧直链继续可用。
3. 同步 `index.html` 里写死的版本号、大小与 SHA-256 兜底文案，以及 `releases.html` 的版本日志。
4. 跑 `prepare-deploy.py`，通过后再 `wrangler deploy`。
