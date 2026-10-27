# 拾影 · Framelet

独立开发的 macOS 截图与标注工具，官网分发方向。当前版本 **0.2.0 预览版**，要求 macOS 14 或更高版本。

所有产品代码由本项目独立实现；没有包含 iShot 的代码、图片、资源、二进制或授权逻辑。工作名尚未进行商标和域名核验。

## 已实现

- 区域截图：拖出选区后原地显示悬浮工具栏；不再自动打开独立编辑窗口。支持多显示器选区、Retina 像素坐标转换、Esc 取消。
- 全屏截图：鼠标所在显示器全选，使用同一套原地工具栏，排除拾影自己的窗口。
- 窗口截图：列出可见应用窗口，截取后在窗口对应位置显示工具栏。
- 箭头、方框、圆圈、自由画笔、文字、马赛克、不透明遮挡；撤销与重做。
- PNG/JPEG 保存、复制合并后的 PNG、浮动贴图。
- Apple Vision 中文/英文 OCR，支持编辑和复制识别结果。
- 菜单栏常驻，全局快捷键 `Control+Option+4` / `Control+Option+3`。
- 权限引导、未保存标注关闭提示、图片导入与文档打开。

截图不自动存盘，不自动上传；OCR 在设备上运行。导出图像是重新编码的单层图像，不带可撤销的标注层或原始图像附件。敏感内容使用「遮挡」，马赛克不作为安全脱敏承诺。

## 构建和验证

```sh
bash scripts/swift.sh run FrameletChecks
bash scripts/build.sh
open dist/Framelet.app
```

需要 Apple Swift 工具链和 macOS SDK。`scripts/swift.sh` 对部分升级的 CLT 中旧版 private swiftinterface 提供工作区内兼容处理，不修改系统工具链。完整 Xcode 可用于 IDE 调试，但当前构建不依赖 xcodebuild。

同时构建 Intel 与 Apple Silicon：

```sh
UNIVERSAL=1 bash scripts/build.sh
```

有 Developer ID Application 证书时：

```sh
SIGNING_IDENTITY='Developer ID Application: 你的证书名称 (TEAMID)' UNIVERSAL=1 bash scripts/build.sh
SIGNING_IDENTITY='Developer ID Application: 你的证书名称 (TEAMID)' bash scripts/package.sh
NOTARY_PROFILE='钥匙串配置名' bash scripts/notarize.sh dist/Framelet-0.2.0.dmg
```

正式 bundle ID 可通过 `BUNDLE_ID` 指定。公证凭据只保存在钥匙串中，不进入代码或配置。`notarize.sh` 会向 Apple 上传指定安装包，需要账号所有者授权；不会上传截图或用户数据，不会公开发布安装包。

## 首次运行

1. 将 `.app` 拖入 Applications，打开。
2. 点击「区域截图」，按系统提示允许屏幕录制。若系统要求，退出后重开。
3. 拖出选区后，用下方悬浮工具栏直接标注、贴图、保存；Enter 或「完成」复制图片并退出，Esc 取消。「重新选择」可重画选区。文字在选区内点击输入，Enter 确认。未标注时可拖动选区四角调整范围。
4. 导入已有图片和「试试标注」不需要屏幕录制权限。
5. 关闭主窗口后仍通过菜单栏运行；`Command+Q` 完全退出。

## 发布范围

本版不含长截图、录屏、声音内录、翻译、自动更新、登录启动、自定义快捷键、裁剪或可编辑工程文件。没有为这些功能放置付费入口或占位按钮。

官网公开分发前，需完成真实截图权限流程、真实多显示器和 Intel 机器验收、Apple 公证、名称及域名确认，并替换支持联系方式。见 [发布检查](docs/发布检查.md)。没有配置托管和下载域名，尚未上线官网。

自动化测试覆盖坐标与裁剪、导出格式、遮挡像素和马赛克叠加遮挡。构建通过不代表所有设备上的截图权限与显示行为已通过验收。
