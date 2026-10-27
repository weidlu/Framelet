# 拾影 · Framelet

拾影是一款 macOS 截图与标注工具，平时在菜单栏运行。截图、标注、长图拼接和文字识别都在本机处理。

[官网与下载](https://framelet.slnt.dev) · [使用说明](docs/使用说明.txt) · [隐私说明](https://framelet.slnt.dev/privacy.html)

当前版本为 **0.3.1 预览版**，支持 macOS 14 及以上的 Apple Silicon 和 Intel Mac。

## 功能

- 区域、窗口、全屏和上次区域截图；长十字准星、像素放大镜和逐像素键盘微调。
- 选区左上角滑块调整截图圆角，最左为直角；PNG 和剪贴板图像支持透明角。
- 截图后原地标注箭头、矩形、圆圈、画笔、文字、马赛克与不透明遮挡。
- 手动连续滚动拼接长截图并查看实时预览；3、5、10 秒延时截图与 HEX/RGB 取色。
- 本机中英文 OCR、截图贴图、可自定义全局快捷键与登录启动。
- 导出 PNG 或 JPEG；JPEG 不支持透明，圆角外部以白色填充。

长截图适用于纵向滚动的相对静止内容。大面积空白、重复纹理、视频或过快滚动可能无法匹配；当前不包含录屏、翻译和自动更新。

## 使用

从[官网](https://framelet.slnt.dev)下载安装，将拾影拖进“应用程序”。首次截图需要按 macOS 提示授予屏幕录制权限。默认快捷键为 `Control+Option+4`（区域）和 `Control+Option+3`（全屏），可在设置中更改。

选区确定后，在左上角尺寸旁调整圆角；在下方工具栏标注，点击完成或按 Enter 执行设置的完成动作。Esc 取消，`Command+C` 复制但保留选区。

## 构建与验证

需要 macOS、Apple Swift 工具链和 macOS SDK：

```sh
bash scripts/swift.sh run FrameletChecks
bash scripts/build.sh
open dist/Framelet.app
```

构建 Apple Silicon 和 Intel 通用版本：

```sh
UNIVERSAL=1 bash scripts/build.sh
```

本地默认使用临时签名。对外分发需要自己的 Developer ID 签名及 Apple 公证；有关环境变量见 [使用说明](docs/使用说明.txt)和 `scripts/`。不要把证书私钥、密码或公证凭据放入仓库。

## 隐私与支持

拾影不要求账号，不自动上传截图。保存、复制和贴图按所选操作执行；使用系统剪贴板后，其他应用及通用剪贴板可能读取或同步内容。敏感内容建议使用不透明遮挡，马赛克不能保证安全脱敏。

问题和建议可提交 GitHub Issue，或联系 [contact@yinbingshi.com](mailto:contact@yinbingshi.com)。

## 许可证

源代码采用 [MIT License](LICENSE)。
