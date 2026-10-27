import AppKit
import SwiftUI
import FrameletCore

enum InlineAction: Equatable { case cancel, reselect, save, pin, ocr, undo, redo, complete, scroll }

struct InlineCaptureToolbar: View {
    @ObservedObject var document: CaptureDocument
    let settings: AppSettingsStore
    let chooseTool: (MarkTool?) -> Void
    let action: (InlineAction) -> Void
    private let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemOrange, .systemYellow, .white, .black]

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                mainRow(compact: false)
                mainRow(compact: true)
                mainRow(compact: true, minimal: true)
            }
            .padding(.horizontal, 8).frame(height: 44)
            if let message = document.message, document.tool == nil {
                Text(message).font(.system(size: 11)).foregroundStyle(Palette.ink).lineLimit(2).padding(.horizontal, 10).frame(height: 32)
            }
            if document.tool != nil {
                Divider().padding(.horizontal, 10)
                ViewThatFits(in: .horizontal) {
                    properties(showDetails: true)
                    properties(showDetails: false)
                }.padding(.horizontal, 12).frame(height: 40)
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border, lineWidth: 1))
        .foregroundStyle(Palette.ink).tint(Palette.blue).help(hint)
        .onChange(of: document.showOCR) { _, show in if show { showOCRPopover = true } }
        .popover(isPresented: $showOCRPopover, arrowEdge: .top) { ocrPopover }
    }

    private func mainRow(compact: Bool, minimal: Bool = false) -> some View {
        HStack(spacing: 4) {
            if !minimal {
                toolButton("移动选区", caption: "移动", symbol: "cursorarrow", selected: document.tool == nil, key: key(for: .move)) { chooseTool(nil) }
                separator
            }
            ForEach(minimal ? [] : compact ? [.rectangle, .arrow, .text] : MarkTool.allCases) { tool in
                markButton(tool)
            }
            separator
            iconButton("撤销", symbol: "arrow.uturn.backward", key: "⌘Z") { action(.undo) }.disabled(!document.canUndo)
            Menu {
                if compact {
                    Section("更多标注工具") {
                        if minimal {
                            Button("移动选区") { chooseTool(nil) }
                        }
                        ForEach(MarkTool.allCases.filter { minimal || ![.rectangle, .arrow, .text].contains($0) }) { tool in
                            Button { chooseTool(document.tool == tool ? nil : tool) } label: {
                                Label { Text(tool.title) } icon: { MarkToolIcon(tool: tool) }
                            }
                        }
                    }
                }
                Button { action(.redo) } label: { Label("重做", systemImage: "arrow.uturn.forward") }.disabled(!document.canRedo)
                Button { action(.reselect) } label: { Label("重新选择", systemImage: "viewfinder") }
                Divider()
                Button { action(.ocr) } label: { Label(document.recognizing ? "识别中…" : "提取文字", systemImage: "text.viewfinder") }.disabled(document.recognizing)
                Button { action(.scroll) } label: { Label("长截图 · 向下滚动拼接", systemImage: "arrow.down.to.line") }.disabled(!document.marks.isEmpty)
                Button { action(.pin) } label: { Label("贴图", systemImage: "pin") }
                if compact { Button { action(.save) } label: { Label("保存…", systemImage: "square.and.arrow.down") } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .medium)).frame(width: 30, height: 32)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("更多操作").accessibilityLabel("更多操作")
            if !compact {
                iconButton("保存", symbol: "square.and.arrow.down", key: "⌘S") { action(.save) }
            }
            Spacer(minLength: 4)
            separator
            iconButton("取消", symbol: "xmark", key: "Esc") { action(.cancel) }
            Button { action(.complete) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                    Text(settings.settings.completionAction.title).font(.system(size: 12, weight: .semibold)).fixedSize()
                }.padding(.horizontal, 10).frame(height: 30)
            }.buttonStyle(.borderedProminent).controlSize(.small)
                .help("\(settings.settings.completionAction.title)并退出 · Enter")
                .accessibilityLabel("\(settings.settings.completionAction.title)并退出")
        }.fixedSize(horizontal: true, vertical: false)
    }

    private var separator: some View { Divider().frame(height: 18).padding(.horizontal, 3) }

    private func properties(showDetails: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Button { setColor(color) } label: {
                    Circle().fill(Color(nsColor: color)).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Palette.ink.opacity(0.2), lineWidth: 1)).padding(4)
                        .overlay(Circle().stroke(document.color == color ? Palette.blue : .clear, lineWidth: 1.5))
                }.buttonStyle(QuietButtonStyle()).accessibilityLabel(color.accessibilityName)
            }
            separator
            if showDetails {
                Text(document.tool == .text ? "字号" : "粗细").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Slider(value: document.tool == .text ? fontSizeBinding : strokeBinding,
                   in: document.tool == .text ? 10...48 : 2...12, step: 1)
                .frame(width: showDetails ? 72 : 48).accessibilityLabel(document.tool == .text ? "文字字号" : "标注粗细")
            Text("\(Int(document.tool == .text ? document.fontSize : document.strokeWidth))")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).frame(width: 18)
            if showDetails {
                Spacer(minLength: 12)
                Text(document.message ?? document.tool?.toolbarHint ?? "\(document.pixelWidth) × \(document.pixelHeight) px")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1)
            }
        }
    }

    @State private var showOCRPopover = false

    private var hint: String {
        if document.tool == .text { return "点击选区输入文字 · 回车确认文字" }
        if document.tool == .redact { return "拖动覆盖敏感内容" }
        if document.tool == .pixelate { return "敏感文字建议使用遮挡" }
        if let tool = document.tool { return "在选区内拖动绘制\(tool.title) · Esc 取消笔画" }
        return "方向键移动 1px · Shift 10px · Option 调整大小 · Cmd+C 复制"
    }

    private func key(for action: ToolKeyAction) -> String? {
        guard let combo = settings.settings.toolShortcuts[action] ?? nil else { return nil }
        return HotKeyFormat.keyName(combo.keyCode)
    }

    private func setColor(_ color: NSColor) {
        document.color = color
        settings.settings.annotationColor = RGBValue(nsColor: color)
    }

    private var strokeBinding: Binding<CGFloat> {
        Binding(get: { document.strokeWidth },
                set: { document.strokeWidth = $0; settings.settings.strokeWidth = Double($0) })
    }

    private var fontSizeBinding: Binding<CGFloat> {
        Binding(get: { document.fontSize },
                set: { document.fontSize = $0; settings.settings.fontSize = Double($0) })
    }

    private func markButton(_ tool: MarkTool) -> some View {
        let selected = document.tool == tool
        let shortcut = key(for: ToolKeyAction(markTool: tool))
        return Button { chooseTool(selected ? nil : tool) } label: {
            VStack(spacing: 2) {
                MarkToolIcon(tool: tool, color: selected ? Palette.blue : Palette.ink)
                Text(tool.title).font(.system(size: 10, weight: selected ? .medium : .regular))
            }
            .frame(width: tool == .pixelate ? 44 : 36, height: 36)
            .foregroundStyle(selected ? Palette.blue : Palette.ink)
            .background(selected ? Palette.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietButtonStyle())
        .help("\(tool.title)\(shortcut.map { " · " + $0 } ?? "")\n\(tool.toolbarHint)")
        .accessibilityLabel(tool.title)
        .accessibilityHint(tool.toolbarHint)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func toolButton(_ title: String, caption: String, symbol: String, selected: Bool = false, key: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 15, weight: .regular)).frame(height: 16)
                Text(caption).font(.system(size: 10, weight: selected ? .medium : .regular))
            }
            .frame(width: 36, height: 36)
            .foregroundStyle(selected ? Palette.blue : Palette.ink)
            .background(selected ? Palette.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }.buttonStyle(QuietButtonStyle()).help(key.map { "\(title) · \($0)" } ?? title).accessibilityLabel(title)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func iconButton(_ title: String, symbol: String, key: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).frame(width: 30, height: 32)
                .foregroundStyle(Palette.ink).contentShape(Rectangle())
        }.buttonStyle(QuietButtonStyle()).help(key.map { "\(title) · \($0)" } ?? title).accessibilityLabel(title)
    }

    private var ocrPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("提取文字").font(.headline); Spacer(); Text("本机识别").font(.caption).foregroundStyle(.secondary) }
            TextEditor(text: Binding(get: { document.ocrText ?? "" }, set: { document.ocrText = $0 })).font(.system(size: 13)).border(.gray.opacity(0.2))
            HStack {
                Button("收起") { document.showOCR = false; showOCRPopover = false }
                Spacer()
                Button("复制文字") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(document.ocrText ?? "", forType: .string)
                }.buttonStyle(.borderedProminent).tint(Palette.blue)
            }
        }.padding(18).frame(width: 400, height: 300)
    }
}

private extension ToolKeyAction {
    init(markTool: MarkTool) {
        switch markTool {
        case .rectangle: self = .rectangle
        case .ellipse: self = .ellipse
        case .arrow: self = .arrow
        case .pen: self = .pen
        case .pixelate: self = .mosaic
        case .text: self = .text
        case .redact: self = .redact
        }
    }
}
