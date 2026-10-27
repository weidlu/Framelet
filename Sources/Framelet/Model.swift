import AppKit
import SwiftUI
import Vision
import FrameletCore

@MainActor final class ImageDocument: ObservableObject {
    let original: CGImage
    let name: String
    @Published private(set) var marks: [Mark] = []
    @Published var tool: MarkTool = .arrow
    @Published var color = NSColor(red: 0.90, green: 0.24, blue: 0.25, alpha: 1)
    @Published var strokeWidth: CGFloat = 5
    @Published var message: String?
    @Published var recognizing = false
    @Published var ocrText: String?
    private var redoMarks: [Mark] = []
    private var dirty = false
    init(image: CGImage, name: String) { original = image; self.name = name }
    var hasUnsavedMarks: Bool { dirty }
    func append(_ mark: Mark) { marks.append(mark); redoMarks.removeAll(); dirty = true }
    func undo() { if let last = marks.popLast() { redoMarks.append(last); dirty = true } }
    func redo() { if let last = redoMarks.popLast() { marks.append(last); dirty = true } }
    var canRedo: Bool { !redoMarks.isEmpty }
    func flattened() throws -> CGImage { try Imaging.render(original, marks: marks) }
    @discardableResult func copy() -> Bool {
        do {
            let data = try Imaging.data(flattened())
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setData(data, forType: .png) else { throw ImagingError.export }
            message = "已复制图片"
            return true
        } catch { message = error.localizedDescription; return false }
    }
    @discardableResult func save() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "拾影-\(Self.timestamp()).png"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            let image = try flattened()
            let data = try Imaging.data(image, type: ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg : .png)
            try data.write(to: url, options: .atomic)
            dirty = false
            message = "已保存到 \(url.lastPathComponent)"
            return true
        } catch { message = error.localizedDescription; return false }
    }
    func recognize() {
        guard !recognizing else { return }
        do {
            let image = try flattened()
            recognizing = true
            Task {
                do {
                    let text = try await Task.detached(priority: .userInitiated) {
                        let request = VNRecognizeTextRequest()
                        request.recognitionLevel = .accurate
                        request.usesLanguageCorrection = true
                        request.automaticallyDetectsLanguage = true
                        request.recognitionLanguages = ["zh-Hans", "en-US"]
                        try VNImageRequestHandler(cgImage: image).perform([request])
                        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                    }.value
                    ocrText = text.isEmpty ? "未识别到文字。可以换一张更清晰的图片再试。" : text
                } catch { message = error.localizedDescription }
                recognizing = false
            }
        } catch { message = error.localizedDescription }
    }
    static func timestamp() -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"; return formatter.string(from: Date())
    }
}

/// Shared semantic colors keep every surface in sync with the macOS appearance.
enum Palette {
    static let ink = Color(nsColor: .labelColor)
    static let blue = Color.accentColor
    static let paper = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let border = Color(nsColor: .separatorColor).opacity(0.5)
    static let selection = Color.accentColor.opacity(0.12)
}

/// Hover feedback without adding permanent button chrome to compact tool surfaces.
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        QuietButtonBody(configuration: configuration, isEnabled: isEnabled)
    }

    private struct QuietButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let isEnabled: Bool
        @State private var hovering = false
        var body: some View {
            configuration.label
                .background(Palette.ink.opacity(configuration.isPressed ? 0.10 : hovering && isEnabled ? 0.05 : 0),
                            in: RoundedRectangle(cornerRadius: 6))
                .opacity(isEnabled ? 1 : 0.35)
                .onHover { hovering = $0 }
        }
    }
}
