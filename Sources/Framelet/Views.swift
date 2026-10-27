import SwiftUI
import AppKit
import ScreenCaptureKit
import FrameletCore

struct HomeView: View {
    @ObservedObject var controller: AppController
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "viewfinder").font(.system(size: 29, weight: .medium)).foregroundStyle(Palette.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("拾影").font(.system(size: 23, weight: .semibold, design: .rounded))
                        Text("FRAMELET").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(Palette.muted)
                    }
                }.padding(.bottom, 42)
                Label("截图工作台", systemImage: "viewfinder").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.blue).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(Palette.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                Button(action: controller.importImage) { Label("打开图片", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                    .buttonStyle(.plain).padding(.top, 5)
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "externaldrive.badge.checkmark").font(.system(size: 20)).foregroundStyle(Palette.muted)
                    Text("你的画面，留在本机。").font(.system(size: 12, weight: .medium))
                    Text("无需账号，没有订阅。\n只有保存时才写入图片。").font(.system(size: 11)).lineSpacing(4).foregroundStyle(Palette.muted)
                }.padding(.bottom, 24)
                Button(action: controller.showSettings) { Label("设置", systemImage: "slider.horizontal.3").font(.system(size: 12)) }.buttonStyle(.plain)
                Text("0.3.0").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).padding(.top, 18)
            }.padding(24).frame(width: 210).frame(maxHeight: .infinity).background(Palette.paper)
            Rectangle().fill(Palette.ink.opacity(0.07)).frame(width: 1)
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("随手一截，留住重点。").font(.system(size: 29, weight: .semibold, design: .rounded)).tracking(-0.7)
                    Spacer()
                    Text("本地处理").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.blue).padding(.horizontal, 10).padding(.vertical, 6).background(Palette.blue.opacity(0.07), in: Capsule())
                }
                Text("截取画面，标出想法，把重点分享出去。").font(.system(size: 13)).foregroundStyle(Palette.muted).padding(.top, -12)
                preview.padding(.vertical, 2)
                HStack(spacing: 12) {
                    captureButton("区域截图", subtitle: "拖动选择范围", symbol: "viewfinder", shortcut: shortcut(.region), primary: true) { controller.capture(.region) }
                    captureButton("窗口截图", subtitle: "完整截取一个窗口", symbol: "macwindow", shortcut: shortcut(.window)) { controller.chooseWindow() }
                    captureButton("全屏截图", subtitle: "鼠标所在的屏幕", symbol: "display", shortcut: shortcut(.fullscreen)) { controller.capture(.full) }
                }.disabled(controller.busy)
                HStack(spacing: 6) {
                    if controller.busy { ProgressView().controlSize(.small); Text("正在准备截图…") }
                    else { Image(systemName: "keyboard"); Text("快捷键随时可用，关闭此窗口后仍在菜单栏运行。") }
                }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
                HStack {
                    Text("已有图片？直接打开，继续标注。").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    Spacer()
                    Button("打开图片…", action: controller.importImage).buttonStyle(.bordered)
                }.padding(.top, 12).overlay(alignment: .top) { Divider() }
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
        }.foregroundStyle(Palette.ink).preferredColorScheme(.light)
    }

    private func shortcut(_ action: CaptureAction) -> String? {
        guard let combo = controller.settings.settings.globalShortcuts[action] ?? nil else { return nil }
        return HotKeyFormat.display(combo)
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Palette.paper)
            GeometryReader { geometry in
                Path { path in
                    for x in stride(from: CGFloat(12), to: geometry.size.width, by: 20) {
                        for y in stride(from: CGFloat(12), to: geometry.size.height, by: 20) {
                            path.addEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.5))
                        }
                    }
                }.fill(Palette.ink.opacity(0.13))
            }.clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 5) { ForEach(0..<3) { _ in Circle().fill(Palette.ink.opacity(0.13)).frame(width: 6, height: 6) }; Spacer(); Text("灵感片段").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                Text("把重点，框出来。").font(.system(size: 24, weight: .semibold, design: .rounded))
                HStack(spacing: 12) {
                    Text("截图").padding(.horizontal, 12).padding(.vertical, 7).overlay(RoundedRectangle(cornerRadius: 3).stroke(Palette.blue, lineWidth: 2))
                    Image(systemName: "arrow.right").foregroundStyle(Palette.blue)
                    Text("标注").foregroundStyle(Palette.muted)
                    Image(systemName: "arrow.right").foregroundStyle(Palette.blue)
                    Text("分享").foregroundStyle(Palette.muted)
                }.font(.system(size: 12, weight: .medium))
            }.padding(20).frame(width: 320).background(.white, in: RoundedRectangle(cornerRadius: 10))
                .shadow(color: Palette.ink.opacity(0.10), radius: 15, x: 0, y: 8).rotationEffect(.degrees(-3))
            VStack { Spacer(); HStack { Spacer(); Button(action: controller.showDemo) { Label("试试标注", systemImage: "pencil.tip.crop.circle").font(.system(size: 11, weight: .medium)) }.buttonStyle(.bordered).padding(14) } }
        }.frame(height: 220)
    }

    private func captureButton(_ title: String, subtitle: String, symbol: String, shortcut: String?, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Image(systemName: symbol).font(.system(size: 24, weight: .light)); Spacer(); if let shortcut { Text(shortcut).font(.system(size: 10, design: .monospaced)).opacity(0.65) } }
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).opacity(0.7).lineLimit(1)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).frame(height: 122)
                .foregroundStyle(primary ? .white : Palette.ink)
                .background(primary ? Palette.blue : Palette.paper, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}

struct EditorView: View {
    @ObservedObject var document: ImageDocument
    let controller: AppController
    @State private var showOCR = false
    private let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemOrange, .black, .white]
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                ForEach(MarkTool.allCases) { tool in
                    Button { document.tool = tool } label: {
                        VStack(spacing: 5) { Image(systemName: tool.symbol).font(.system(size: 17)); Text(tool.title).font(.system(size: 10)) }
                            .frame(width: 48, height: 49).background(document.tool == tool ? Palette.blue.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .foregroundStyle(document.tool == tool ? Palette.blue : Palette.ink)
                    }.buttonStyle(.plain).help(tool.title).accessibilityLabel(tool.title)
                }
                Divider().frame(height: 28).padding(.horizontal, 10)
                Button(action: document.undo) { Image(systemName: "arrow.uturn.backward") }.disabled(document.marks.isEmpty).help("撤销 ⌘Z")
                Button(action: document.redo) { Image(systemName: "arrow.uturn.forward") }.disabled(!document.canRedo).help("重做 ⇧⌘Z")
                Spacer(minLength: 8)
                Button { document.recognize() } label: { Label(document.recognizing ? "识别中" : "提取文字", systemImage: "text.viewfinder") }.disabled(document.recognizing)
                Button { controller.pin(document) } label: { Label("贴图", systemImage: "pin") }
                Button { document.copy() } label: { Label("复制", systemImage: "doc.on.doc") }.help("复制图片 ⌘C")
                Button { document.save() } label: { Label("保存", systemImage: "square.and.arrow.down") }.buttonStyle(.borderedProminent).tint(Palette.blue).help("保存图片 ⌘S")
            }.buttonStyle(.bordered).controlSize(.small).padding(12).background(.white)
            HStack(spacing: 10) {
                Text("颜色").font(.system(size: 11)).foregroundStyle(Palette.muted)
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Button { document.color = color } label: {
                        Circle().fill(Color(nsColor: color)).frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Palette.ink.opacity(0.2), lineWidth: 1))
                            .padding(3).overlay(Circle().stroke(document.color == color ? Palette.blue : .clear, lineWidth: 1.5))
                    }.buttonStyle(.plain).accessibilityLabel(color.accessibilityName)
                }
                Divider().frame(height: 14).padding(.horizontal, 6)
                Text("粗细").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Slider(value: $document.strokeWidth, in: 2...12, step: 1).frame(width: 85).accessibilityLabel("标注粗细")
                Spacer()
                Text(document.tool == .redact ? "遮挡区域会以不透明黑色覆盖" : document.tool == .pixelate ? "敏感文字建议使用「遮挡」彻底覆盖" : document.tool == .text ? "点击图片添加文字" : "在图片上拖动绘制 · Esc 取消当前笔画")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 18).padding(.vertical, 9).background(Palette.paper)
            Divider()
            ImageCanvas(document: document).frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text("\(document.original.width) × \(document.original.height) px").font(.system(size: 10, design: .monospaced))
                Text("·"); Text("\(document.marks.count) 个标注")
                Spacer()
                Text(document.message ?? "图片在本机处理，导出时合并全部标注。")
            }.font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.horizontal, 16).padding(.vertical, 10).background(.white)
        }.foregroundStyle(Palette.ink).preferredColorScheme(.light)
            .onChange(of: document.ocrText) { _, value in if value != nil { showOCR = true } }
            .sheet(isPresented: $showOCR) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Label("提取文字", systemImage: "text.viewfinder").font(.title3.bold()); Spacer(); Text("本机识别").font(.caption).foregroundStyle(.secondary) }
                    TextEditor(text: Binding(get: { document.ocrText ?? "" }, set: { document.ocrText = $0 })).font(.system(size: 14)).border(Color.gray.opacity(0.2))
                    HStack { Button("关闭") { showOCR = false }.keyboardShortcut(.cancelAction); Spacer(); Button("复制文字") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(document.ocrText ?? "", forType: .string)
                    }.buttonStyle(.borderedProminent).tint(Palette.blue) }
                }.padding(24).frame(width: 540, height: 420)
            }
    }
}

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settings: AppSettingsStore
    let keys: HotKeyRegistry
    @State private var tab = 0
    @State private var toolError: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("截图").tag(0); Text("快捷键").tag(1); Text("保存").tag(2); Text("权限与关于").tag(3)
            }.pickerStyle(.segmented).labelsHidden().padding(16)
            Divider()
            ScrollView {
                Group {
                    switch tab {
                    case 0: captureTab
                    case 1: shortcutTab
                    case 2: saveTab
                    default: permissionTab
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }.background(.white).preferredColorScheme(.light).frame(minWidth: 700, minHeight: 500)
    }

    private var captureTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("完成动作").font(.headline)
            Text("点击「完成」、按 Enter 或在移动状态下双击选区时执行。Cmd+C 始终只复制、不退出截图。").font(.system(size: 11)).foregroundStyle(.secondary)
            Picker("完成动作", selection: Binding(get: { settings.settings.completionAction }, set: { settings.settings.completionAction = $0 })) {
                ForEach(CompletionAction.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.radioGroup)
            Divider()
            Text("双击动作").font(.headline)
            Text("仅在移动/选区状态生效；绘制工具、文字输入和工具栏上的双击不会触发。").font(.system(size: 11)).foregroundStyle(.secondary)
            Picker("双击动作", selection: Binding(get: { settings.settings.doubleClickAction }, set: { settings.settings.doubleClickAction = $0 })) {
                ForEach(DoubleClickAction.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.radioGroup)
        }
    }

    private var shortcutTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("全局快捷键").font(.headline); Spacer(); Button("全部恢复默认") { controller.restoreDefaultGlobalShortcuts() }.controlSize(.small) }
            if !controller.hotKeyFailures.isEmpty {
                Text("以下快捷键未注册成功：\(controller.hotKeyFailures.map { "\($0.key.title)（\($0.value)）" }.joined(separator: "、"))")
                    .font(.caption).foregroundStyle(.orange)
            }
            ForEach(CaptureAction.allCases) { action in
                HStack {
                    Text(action.title).frame(width: 120, alignment: .leading)
                    ShortcutRecorder(combo: settings.settings.globalShortcuts[action] ?? nil,
                                     placeholder: "未设置",
                                     onCommit: { controller.rebindHotKey(action, to: $0) },
                                     onRecordingChanged: { controller.setRecording($0) })
                        .frame(width: 220, height: 28)
                    Button("恢复默认") {
                        controller.rebindHotKey(action, to: AppSettings.defaultGlobalShortcuts[action] ?? nil)
                    }.controlSize(.small).disabled(AppSettings.defaultGlobalShortcuts[action] ?? nil == settings.settings.globalShortcuts[action] ?? nil)
                }
            }
            Divider()
            HStack { Text("截图会话工具键").font(.headline); Spacer(); Button("全部恢复默认") { controller.restoreDefaultToolShortcuts() }.controlSize(.small) }
            Text("截图时直接按这些键切换工具；文字输入期间不会劫持字符键。").font(.system(size: 11)).foregroundStyle(.secondary)
            if let toolError { Text(toolError).font(.caption).foregroundStyle(.orange) }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                ForEach(ToolKeyAction.allCases) { action in
                    HStack {
                        Text(action.title).frame(width: 70, alignment: .leading)
                        ShortcutRecorder(combo: settings.settings.toolShortcuts[action] ?? nil,
                                         placeholder: "未设置",
                                         onCommit: { setToolKey(action, $0) },
                                         onRecordingChanged: { controller.setRecording($0) })
                            .frame(width: 120, height: 26)
                    }
                }
            }
        }
    }

    private var saveTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("保存格式").font(.headline)
            Picker("格式", selection: Binding(get: { settings.settings.saveFormat }, set: { settings.settings.saveFormat = $0 })) {
                ForEach(SaveFormat.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).frame(width: 220)
            if settings.settings.saveFormat == .jpeg {
                HStack {
                    Text("质量").font(.system(size: 12))
                    Slider(value: Binding(get: { settings.settings.jpegQuality }, set: { settings.settings.jpegQuality = $0 }), in: 0.5...1.0)
                    Text("\(Int(settings.settings.jpegQuality * 100))%").font(.system(size: 11, design: .monospaced)).frame(width: 40, alignment: .trailing)
                }.frame(width: 300)
            }
            Divider()
            Toggle("保存时同时复制", isOn: Binding(get: { settings.settings.copyOnSave }, set: { settings.settings.copyOnSave = $0 }))
            Toggle("贴图时同时复制", isOn: Binding(get: { settings.settings.copyOnPin }, set: { settings.settings.copyOnPin = $0 }))
            Divider()
            Text("保存位置").font(.headline)
            HStack {
                Text(settings.saveDirectoryURL.path).font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("选择…") { chooseDirectory() }.controlSize(.small)
            }
        }
    }

    private var permissionTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(controller.permission ? "屏幕录制权限已开启" : "需要屏幕录制权限", systemImage: controller.permission ? "checkmark.circle.fill" : "display.trianglebadge.exclamationmark")
                .foregroundStyle(controller.permission ? Color.green : Palette.blue)
            Text("只有截图时读取屏幕。OCR 在本机处理；截图不会自动上传，也不会自动保存。").font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4)
            HStack { Button("打开系统权限设置", action: controller.openPermissionSettings); Button("刷新状态") { controller.permission = CGPreflightScreenCaptureAccess() } }
            Divider()
            if let notice = settings.repairNotice {
                Text(notice).font(.caption).foregroundStyle(.orange)
            }
            Text("拾影 · Framelet 0.3.0").font(.system(size: 13, weight: .semibold))
            Text("macOS 14 或更高版本。截图流程借鉴 iShot 的交互思路，代码与素材均为本产品独立实现。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
        }
    }

    private func setToolKey(_ action: ToolKeyAction, _ combo: HotKeyCombo?) {
        toolError = nil
        guard let combo else {
            settings.settings.toolShortcuts[action] = nil
            return
        }
        let bare = HotKeyCombo(keyCode: combo.keyCode)
        if let conflict = settings.settings.toolShortcuts.first(where: { $0.key != action && $0.value == bare })?.key {
            toolError = "该键已被「\(conflict.title)」使用。"
            return
        }
        settings.settings.toolShortcuts[action] = bare
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveDirectoryURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.settings.saveDirectoryPath = url.path
    }
}

struct WindowPicker: View {
    let windows: [SCWindow]
    let select: (SCWindow) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择一个窗口").font(.title2.bold())
            Text("点击后截取完整窗口。").foregroundStyle(.secondary)
            if windows.isEmpty { ContentUnavailableView("没有可截图的窗口", systemImage: "macwindow", description: Text("请先打开需要截图的应用窗口。")) }
            else {
                ScrollView { LazyVStack(spacing: 8) { ForEach(windows, id: \.windowID) { window in
                    Button { select(window) } label: {
                        HStack(spacing: 12) { Image(systemName: "macwindow").font(.title2).foregroundStyle(Palette.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(window.owningApplication?.applicationName ?? "应用").font(.headline)
                                Text(window.title?.isEmpty == false ? window.title! : "无标题窗口").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }.padding(12).frame(maxWidth: .infinity).background(Palette.paper, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                } } }
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(.white).preferredColorScheme(.light)
    }
}

enum DemoImage {
    static func make() -> CGImage? {
        guard let ctx = Imaging.context(width: 1440, height: 900) else { return nil }
        ctx.setFillColor(NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.99, alpha: 1).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 1440, height: 900))
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 160, y: 160, width: 1120, height: 580))
        let base = ctx.makeImage()!
        for (text, point, width) in [("拾影 Framelet", CGPoint(x: 240, y: 610), CGFloat(11)), ("截图，留住重点。", CGPoint(x: 240, y: 480), CGFloat(8)), ("LOCAL · NO ACCOUNT · NO SUBSCRIPTION", CGPoint(x: 240, y: 370), CGFloat(4)), ("这是一张示例图片。试试箭头、标注和文字识别。", CGPoint(x: 240, y: 265), CGFloat(5))] {
            Imaging.draw(Mark(tool: .text, points: [point], color: NSColor(calibratedRed: 0.15, green: 0.24, blue: 0.38, alpha: 1), width: width, text: text), on: ctx, base: base)
        }
        return ctx.makeImage()
    }
}
