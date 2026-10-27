import SwiftUI
import AppKit
import ScreenCaptureKit
import FrameletCore

/// A small launcher; the actual workspace is the selected area on screen.
struct HomeView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 27, weight: .medium)).foregroundStyle(Palette.blue)
                    .frame(width: 48, height: 48).background(Palette.selection, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("拾影").font(.system(size: 21, weight: .semibold))
                    Text("截图，标注，随手粘贴。").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
            }
            VStack(spacing: 0) {
                captureRow("区域截图", symbol: "viewfinder", action: .region, primary: true) { controller.capture(.region) }
                Divider().padding(.leading, 48)
                captureRow("窗口截图", symbol: "macwindow", action: .window) { controller.chooseWindow() }
                Divider().padding(.leading, 48)
                captureRow("全屏截图", symbol: "display", action: .fullscreen) { controller.capture(.full) }
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1))
            .disabled(controller.busy)

            if !controller.permission {
                Button(action: controller.openPermissionSettings) {
                    HStack(spacing: 8) {
                        Image(systemName: "display.trianglebadge.exclamationmark")
                        Text("截图需要屏幕录制权限").font(.system(size: 11))
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 10))
                    }.foregroundStyle(Palette.blue)
                }.buttonStyle(.plain)
            }
            if !controller.shortcutsAvailable {
                Button("部分快捷键不可用，前往设置查看") { controller.showSettings(tab: 1) }
                    .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                if controller.busy { ProgressView().controlSize(.mini) }
                Text(controller.busy ? "正在准备截图…" : "关闭窗口后，仍可通过快捷键截图。")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
                Button(action: controller.showSettings) {
                    Image(systemName: "gearshape").font(.system(size: 15)).frame(width: 28, height: 28)
                }.buttonStyle(QuietButtonStyle()).help("设置 · ⌘,").accessibilityLabel("设置")
            }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Palette.ink).background(Palette.paper).tint(Palette.blue)
    }

    private func captureRow(_ title: String, symbol: String, action: CaptureAction, primary: Bool = false,
                            perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 18, weight: .regular))
                    .foregroundStyle(primary ? Palette.blue : Palette.ink).frame(width: 24)
                Text(title).font(.system(size: 13, weight: primary ? .semibold : .medium))
                Spacer()
                if let combo = settings.settings.globalShortcuts[action] ?? nil {
                    Text(HotKeyFormat.display(combo)).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.muted).padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 5))
                }
            }.padding(.horizontal, 14).frame(height: 58).contentShape(Rectangle())
        }.buttonStyle(QuietButtonStyle()).accessibilityLabel(title)
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
            }.buttonStyle(.bordered).controlSize(.small).padding(12).background(Palette.surface)
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
            }.font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.horizontal, 16).padding(.vertical, 10).background(Palette.surface)
        }.foregroundStyle(Palette.ink)
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
    let initialTab: Int
    @State private var tab: Int
    @State private var toolError: String?

    init(controller: AppController, settings: AppSettingsStore, keys: HotKeyRegistry, initialTab: Int = 0) {
        self.controller = controller
        self.settings = settings
        self.keys = keys
        self.initialTab = initialTab
        _tab = State(initialValue: min(3, max(0, initialTab)))
    }

    private let sections: [(title: String, symbol: String, detail: String)] = [
        ("截图", "viewfinder", "选择截图后的完成方式。"),
        ("快捷键", "keyboard", "随时截图，快速切换标注工具。"),
        ("保存", "square.and.arrow.down", "设置图片格式、位置与复制方式。"),
        ("权限与关于", "info.circle", "屏幕访问权限与应用信息。")
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("拾影").font(.system(size: 17, weight: .semibold)).padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 20)
                ForEach(sections.indices, id: \.self) { index in
                    Button { tab = index } label: {
                        Label(sections[index].title, systemImage: sections[index].symbol)
                            .font(.system(size: 12, weight: tab == index ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(height: 36)
                            .foregroundStyle(tab == index ? Palette.blue : Palette.ink)
                            .background(tab == index ? Palette.selection : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(QuietButtonStyle()).accessibilityAddTraits(tab == index ? [.isSelected] : [])
                }
                Spacer()
                Text("Framelet 0.3.0").font(.system(size: 10)).foregroundStyle(Palette.muted).padding(12)
            }.padding(12).frame(width: 162).background(Palette.paper)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(sections[tab].title).font(.system(size: 22, weight: .semibold))
                        Text(sections[tab].detail).font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    Group {
                        switch tab {
                        case 0: captureTab
                        case 1: shortcutTab
                        case 2: saveTab
                        default: permissionTab
                        }
                    }
                    .font(.system(size: 12)).padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border, lineWidth: 1))
                }.padding(28).frame(maxWidth: .infinity, alignment: .topLeading)
            }.background(Palette.paper)
        }.foregroundStyle(Palette.ink).tint(Palette.blue).frame(minWidth: 760, minHeight: 540)
    }

    private var captureTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            LoginItemSettings()
            Divider()
            Text("完成动作").font(.headline)
            Text("右侧的结束按钮会显示所选动作；也可按 Enter 执行。⌘C 仅复制，保留当前选区。").font(.system(size: 11)).foregroundStyle(.secondary)
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
            HStack { Text("标注工具快捷键").font(.headline); Spacer(); Button("全部恢复默认") { controller.restoreDefaultToolShortcuts() }.controlSize(.small) }
            Text("截图时直接按这些键切换工具；输入文字时不会切换工具。").font(.system(size: 11)).foregroundStyle(.secondary)
            if let toolError { Text(toolError).font(.caption).foregroundStyle(.orange) }
            LazyVGrid(columns: [GridItem(.flexible())], alignment: .leading, spacing: 8) {
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
            Text("macOS 14 或更高版本。无需账号，截图与文字识别均在本机完成。").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
        }
    }

    private func setToolKey(_ action: ToolKeyAction, _ combo: HotKeyCombo?) {
        toolError = nil
        guard let combo else {
            settings.settings.toolShortcuts[action] = nil
            return
        }
        guard !combo.hasRequiredModifier, !combo.hasShift else {
            toolError = "会话工具键请使用单个按键，不要加修饰键。"
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
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Palette.surface)
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

/// A synthetic desktop used only by the local `--capture synthetic` acceptance
/// hook. It lets the real overlay/toolbar/canvas be exercised on machines where
/// screen-recording permission has not been granted.
enum SyntheticSnapshot {
    static func make() -> CGImage? {
        let width = 1600, height = 1000
        guard let ctx = Imaging.context(width: width, height: height) else { return nil }
        ctx.setFillColor(NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.97, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 120, y: 140, width: 1360, height: 720))
        ctx.setFillColor(NSColor(calibratedRed: 0.16, green: 0.35, blue: 0.77, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 120, y: 780, width: 1360, height: 80))
        guard let base = ctx.makeImage() else { return nil }
        let lines: [(String, CGPoint, CGFloat, NSColor)] = [
            ("拾影 · 验收用合成画面", CGPoint(x: 200, y: 700), 34, NSColor(calibratedRed: 0.13, green: 0.19, blue: 0.25, alpha: 1)),
            ("这张图只用于本地交互验收，不会进入产品。", CGPoint(x: 200, y: 610), 22, .darkGray),
            ("1  2  3  4  5  6  7  8", CGPoint(x: 200, y: 500), 30, .darkGray),
            ("拖动八个手柄可调整选区；V 移动；T 贴图；O 提取文字。", CGPoint(x: 200, y: 400), 20, .gray),
            ("Enter 完成并复制；Cmd+C 只复制；Esc 取消。", CGPoint(x: 200, y: 320), 20, .gray),
        ]
        for (text, point, size, color) in lines {
            Imaging.draw(Mark(tool: .text, points: [point], color: color, width: size / 4, fontSize: size, text: text), on: ctx, base: base)
        }
        return ctx.makeImage()
    }
}
