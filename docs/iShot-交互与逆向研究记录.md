# iShot 交互与逆向研究记录

研究日期：2026-10-27。本机目标：/Applications/iShot.app，2.6.9，build 20260831001，bundle cn.better365.ishot。

## 结论与边界

Framelet 是独立编写的原生应用，目前没有使用 iShot 源码。此前做到的主要是元数据与交互观察，不能称为已经理解其内部完整实现。本轮补做 REA 的 Objective-C 分派元数据提取与 Ghidra 函数反编译，以下把事实、推断、产品选择分开记录。目的是借鉴可见交互并独立实现自己的软件；未修改目标程序、授权或付费逻辑，发布物不包含目标程序及其素材。

工具：[REA 官方仓库](https://github.com/morluto/rea)，rea-agents 6.8.0；[NSA Ghidra 官方发行](https://github.com/NationalSecurityAgency/ghidra/releases/tag/Ghidra_12.1.4_build)，12.1.4。Ghidra 包 SHA256 为 ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db，已与官方发行资产摘要核对。使用本地 OpenJDK24；官方包缺 mac_arm_64 反编译器，已由随包源码编译，仅安装在本任务 work/tools 内。

目标原二进制为 arm64/x86_64 universal，仅对工作目录中的 arm64 副本分析。副本 SHA256：0fd04bf6c49aa4f5e3bbc392bd88c0d319faa663fbc27edd7a2b97d51a88126b。原应用未写入。下列地址对应该 arm64 副本，不能直接当作其他版本/架构地址。

## 现场界面观察

本机 iShot 偏好设置的 Screenshot → Save & Action：

- 双击完成动作当前为 Save to clipboard；菜单可选 No action / Pin / OCR / Save to file / Save to clipboard / Save to file and clipboard。
- “Also save to paste when save to a file”当前未勾选。
- 有截图完成声音、格式 png、保存目录与画质选项。

这些是用户机器的当前配置，不是经过重置确认的出厂默认。也没有证据证明“鼠标松开选区立即自动复制”。因此 Framelet 设计以完成动作触发自动复制，保留选区后的原地标注阶段。

Screenshot → Preference 中可分别设置标准截图、性能截图、预设区域、上次区域、光标下窗口、延时全屏等快捷键。当前机器可见 Option+A / Q / G / X / Z / D 等，不应凭用户曾提到 Option+4 就写死或抢占那个键。

Annotate 设置是工具/动作与会话内快捷键对应表，包含形状、箭头、画笔、马赛克、文字、注释、高亮、贴图、OCR、滚动截图、取消、保存、剪贴板、复制、另存为及撤销/重做，部分为可选按键，另有工具栏弹出响应时间。它将全局截图快捷键与标注会话快捷键分开设计。

## Objective-C 分派元数据

REA inspect-native-dispatch-metadata 提取到 234 个 ObjC 类。选取与当前问题直接相关的入口：

| 类/方法 | arm64 地址 | 能确认的范围 |
|---|---|---|
| MXClipScreenManager startScreenShots | 0x10005f708 | 存在截图管理入口 |
| MXClipWindowController clipViewMouseDoubleClick: | 0x100018b48 | 存在双击回调；函数反编译结果为空返回，不能靠名字认定逻辑 |
| CustomScrollView saveToPaste: | 0x10004ec68 | 存在保存到剪贴板入口 |
| AnnotatedImageController copyToPasteButtonClick: | 0x100083e0c | 存在标注复制按钮入口 |
| AppDelegate registerAllHotKey | 0x1000abf98 | 存在统一快捷键注册入口 |
| AppDelegate hotKeyActionWithIdentifier: | 0x1000ac288 | 存在按标识分派的快捷键入口 |
| AppPrefsWindowController shortcutRecorderDidEndRecording: | 0x1000c187c | 存在快捷键录入完成入口 |
| AppDelegate saveImageOfNotSpecified: | 0x1000ac670 | 存在图片保存入口 |

方法名和地址是元数据事实；单凭它们不能证明函数调用关系、动作顺序、冲突处理事务或保存成功语义。Framelet 的模块边界属于设计选择，而非声称复制了目标软件内部架构。

## 原始证据位置

原始证据保留在本机 /Users/weidlu/Documents/Codex/2026-10-27/re-a/work/ishot：

- dispatch.json：ObjC 分派元数据。
- feature-methods.json：筛选后的功能入口。
- doubleclick-decompile.json：REA/Ghidra 的真实伪代码证据，空返回。
- behavior-batch.json：剪贴板、保存、快捷键入口的批量反编译结果，结论见下方。
- macho.json / plist.json / signature.json：目标结构、版本及签名元数据。

分析工具与原始伪代码不加入应用源码仓库。运行期行为仍以实际界面测试为准；编译器优化、ObjC 动态分派、外部框架调用及反编译类型恢复会限制静态解释。

## 本轮函数反编译得到的具体结论

批量调用 batch_decompile 的 6 项全部成功；Evidence ID：ev_474704d1d15ba978241e3ed38260026c17e7a302f3bd98f9ec851bdebd2a1b15。以下是伪代码的人工归纳，不是原始源码。

1. **CustomScrollView saveToPaste:** 遍历一组视图，匹配当前窗口的 contentView，取其 image，记录 screen 后调用 NSImage 的 saveImageToPaste:；再从 UserDefaults 读取完成声音选项。由此可见复制是明确的应用动作，并带有用户配置；本次没有继续展开 saveImageToPaste:，不声称已经验证其所有 pasteboard 类型或原子性。
2. **AnnotatedImageController copyToPasteButtonClick:** 对文字/注释工具先发送结束文字编辑的通知，更新一组会话标志，触发局部重绘通知，最后发送 StartScreenShots 通知。若干 ObjC stub 的目标仍未恢复，不能据该函数名认定此处直接写剪贴板；它至少表明复制流程涉及结束文本编辑和会话协调。
3. **AppDelegate registerAllHotKey:** 从 UserDefaults 的 dicOfShortCutKey 取字典，遍历动作条目，经 PTHotKeyCenter / PTHotKey 相关入口更新注册，并指定 hotKeyAction: 回调。这里看到的是存储与注册路径，不等于已经证实注册失败回滚。因此 Framelet 的换键事务是我们自己的可靠性要求。
4. **AppDelegate hotKeyActionWithIdentifier:** 按 regionalScreenshotsRecorder、quickScreenshotsRecorder、presetAreaSizeScreenshotsRecorder、screenshotPreviousAreaRecorder、OCRRecorder 等标识分派动作，部分分支设置截图模式标志。支持把动作标识作为稳定配置键，而非把按键与 UI 按钮硬耦合的设计判断。
5. **AppPrefsWindowController shortcutRecorderDidEndRecording:** 读取快捷键字典、录制器 identifier 与键值；清除时移除对应配置，否则调用热键构造/注册入口，并写回 UserDefaults。另有修饰键与辅助功能权限分支，部分条件会恢复录制器显示。未完整恢复的 stub/数值条件不强行命名成已确认的系统版本规则。
6. **AppDelegate saveImageOfNotSpecified:** 保存前记录前台应用标识，建立 NSSavePanel，读取保存格式偏好并提供格式列表；runModal 返回确认后才调用图片文件保存入口，最后请求恢复原前台应用。格式列表包含 PNG/JPG/TIFF/WebP/HEIC/PDF，但实际编码正确性不在本次验证范围。Framelet 首轮实现 PNG/JPEG，不用空选项冒充全部支持。

这些结果支撑了“持久化设置 → 动作分派 → 会话结束/文本提交 → 导出 → 恢复前台”的设计方向，但没有还原完整调用图。Ghidra 日志有分析器异常警告及外部系统库未随目标导入的提示；已成功返回的伪代码仍需结合现场行为理解。工具报告成功不等于全部类型/调用目标已正确恢复。
