import AppKit
import SwiftUI
import FrameletCore

enum InlineAction: Equatable { case cancel, reselect, save, pin, ocr, undo, redo, complete }

struct InlineCaptureToolbar: View {
    @ObservedObject var document: CaptureDocument
    let settings: AppSettingsStore
    let chooseTool: (MarkTool?) -> Void
    let action: (InlineAction) -> Void
    private let colors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemOrange, .systemYellow, .white, .black]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        toolButton("移动选区", symbol: "cursorarrow", selected: document.tool == nil, key: key(for: .move)) {
                            chooseTool(nil)
                        }
                        Divider().frame(height: 20).padding(.horizontal, 2)
                        ForEach(MarkTool.allCases) { tool in
                            toolButton(tool.title, symbol: tool.symbol, selected: document.tool == tool, key: key(for: ToolKeyAction(markTool: tool))) {
                                chooseTool(document.tool == tool ? nil : tool)
                            }
                        }
                        Divider().frame(height: 20).padding(.horizontal, 2)
                        iconButton("撤销", symbol: "arrow.uturn.backward", key: "⌘Z") { action(.undo) }.disabled(!document.canUndo)
                        iconButton("重做", symbol: "arrow.uturn.forward", key: "⇧⌘Z") { action(.redo) }.disabled(!document.canRedo)
                        iconButton("重新选择", symbol: "viewfinder") { action(.reselect) }
                        Divider().frame(height: 20).padding(.horizontal, 2)
                        iconButton(document.recognizing ? "识别中" : "提取文字", symbol: "text.viewfinder", key: key(for: .ocr)) { action(.ocr) }.disabled(document.recognizing)
                        iconButton("贴图", symbol: "pin", key: key(for: .pin)) { action(.pin) }
                        iconButton("保存", symbol: "square.and.arrow.down", key: "⌘S") { action(.save) }
                    }.padding(.horizontal, 9).padding(.vertical, 6)
                }
                Divider().frame(height: 24)
                Button { action(.cancel) } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).frame(width: 30, height: 32)
                }.buttonStyle(.plain).help("取消 · Esc").accessibilityLabel("取消")
                Button { action(.complete) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                        Text("完成").font(.system(size: 12, weight: .semibold))
                    }.padding(.horizontal, 12).frame(height: 32)
                }.buttonStyle(.plain).foregroundStyle(.white).background(Palette.blue, in: RoundedRectangle(cornerRadius: 6))
                    .help("\(settings.settings.completionAction.title)并退出 · Enter").accessibilityLabel("完成")
            }.frame(height: 44).background(.white)

            if document.tool != nil {
                Divider().padding(.horizontal, 8)
                HStack(spacing: 8) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                        Button { setColor(color) } label: {
                            Circle().fill(Color(nsColor: color)).frame(width: 13, height: 13)
                                .overlay(Circle().stroke(.gray.opacity(0.4), lineWidth: 1)).padding(3)
                                .overlay(Circle().stroke(document.color == color ? Palette.blue : .clear, lineWidth: 1.5))
                        }.buttonStyle(.plain).accessibilityLabel(color.accessibilityName)
                    }
                    Divider().frame(height: 14).padding(.horizontal, 2)
                    if document.tool == .text {
                        Text("字号").font(.system(size: 10)).foregroundStyle(Palette.muted)
                        Slider(value: fontSizeBinding, in: 10...48, step: 1).frame(width: 80).accessibilityLabel("文字字号")
                    } else {
                        Text("粗细").font(.system(size: 10)).foregroundStyle(Palette.muted)
                        Slider(value: strokeBinding, in: 2...12, step: 1).frame(width: 80).accessibilityLabel("标注粗细")
                    }
                    Spacer(minLength: 8)
                    if document.recognizing { ProgressView().controlSize(.mini) }
                    Text(document.message ?? hint).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                    Text("\(document.pixelWidth) × \(document.pixelHeight)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                }.padding(.horizontal, 12).frame(height: 40).background(.white)
            }
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.ink.opacity(0.12), lineWidth: 1))
        .foregroundStyle(Palette.ink).preferredColorScheme(.light)
        .onChange(of: document.showOCR) { _, show in if show { showOCRPopover = true } }
        .popover(isPresented: $showOCRPopover, arrowEdge: .top) { ocrPopover }
    }

    @State private var showOCRPopover = false

    private var hint: String {
        if document.tool == .text { return "点击选区输入文字 · 回车确认文字" }
        if document.tool == .redact { return "拖动覆盖敏感内容" }
        if document.tool == .pixelate { return "敏感文字建议使用遮挡" }
        if let tool = document.tool { return "在选区内拖动绘制\(tool.title) · Esc 取消笔画" }
        return "拖动手柄调整 · 双击完成 · Cmd+C 复制"
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

    private func toolButton(_ title: String, symbol: String, selected: Bool = false, key: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                if let key { Text(key).font(.system(size: 8, weight: .semibold, design: .monospaced)).opacity(0.55) }
            }
            .frame(minWidth: 30, minHeight: 32)
            .foregroundStyle(selected ? Palette.blue : Palette.ink)
            .background(selected ? Palette.blue.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }

    private func iconButton(_ title: String, symbol: String, key: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).frame(width: 30, height: 32)
                .foregroundStyle(Palette.ink).contentShape(Rectangle())
        }.buttonStyle(.plain).help(key.map { "\(title) · \($0)" } ?? title).accessibilityLabel(title)
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
