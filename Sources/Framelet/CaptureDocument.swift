import AppKit
import Combine
import Vision
import FrameletCore

/// The in-place capture document. Unlike `ImageDocument` (which edits an
/// imported, cropped image), this one keeps the full screenshot and stores
/// marks in full-image pixel coordinates. The selection is a window; moving or
/// resizing it never stretches existing marks, and marks outside the selection
/// are cropped on export.
@MainActor final class CaptureDocument: ObservableObject {
    let fullImage: CGImage
    let name: String
    /// Pixels per view point for the display this selection lives on.
    var scale: CGFloat = 1
    /// Selection in full-image pixel coordinates (bottom-left origin), updated
    /// by the overlay as the selection moves/resizes.
    var selectionPixelRect: CGRect = .zero
    @Published private(set) var marks: [Mark] = []
    @Published var tool: MarkTool? = nil
    @Published var color: NSColor
    @Published var strokeWidth: CGFloat
    @Published var fontSize: CGFloat
    @Published var message: String?
    @Published var recognizing = false
    @Published var ocrText: String?
    @Published var showOCR = false
    private var redoMarks: [Mark] = []
    private(set) var sessionID = UUID()

    init(fullImage: CGImage, name: String, color: NSColor, strokeWidth: CGFloat, fontSize: CGFloat) {
        self.fullImage = fullImage
        self.name = name
        self.color = color
        self.strokeWidth = strokeWidth
        self.fontSize = fontSize
    }

    var pixelWidth: Int { max(1, Int(selectionPixelRect.width.rounded())) }
    var pixelHeight: Int { max(1, Int(selectionPixelRect.height.rounded())) }

    func append(_ mark: Mark) { marks.append(mark); redoMarks.removeAll() }
    func undo() { if let last = marks.popLast() { redoMarks.append(last) } }
    func redo() { if let last = redoMarks.popLast() { marks.append(last) } }
    var canRedo: Bool { !redoMarks.isEmpty }
    var canUndo: Bool { !marks.isEmpty }

    func flattened() throws -> CGImage {
        try Imaging.renderCropped(fullImage, marks: marks, selectionPixelRect: selectionPixelRect)
    }

    @discardableResult
    func copy() -> Bool {
        do {
            try CaptureExporter.writePasteboard(flattened())
            message = "已复制图片"
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func recognize() {
        guard !recognizing else { return }
        guard let image = try? flattened() else { return }
        recognizing = true
        let id = sessionID
        Task { [weak self] in
            let result = try? await OCR.recognize(image)
            await MainActor.run {
                guard let self, self.sessionID == id else { return } // stale session
                self.recognizing = false
                guard let result else {
                    self.message = "文字识别失败，请重试。"
                    return
                }
                self.ocrText = result.isEmpty ? "未识别到文字。" : result
                self.showOCR = true
            }
        }
    }
}

/// Shared, session-safe OCR helper. Runs Vision off the main actor.
enum OCR {
    static func recognize(_ image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            try VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}

extension RGBValue {
    init(nsColor: NSColor) {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.init(red: Double(converted.redComponent), green: Double(converted.greenComponent), blue: Double(converted.blueComponent))
    }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}

/// Unified export semantics: always encode the final image successfully before
/// touching the pasteboard, and write both PNG and TIFF so native targets can
/// paste reliably.
enum CaptureExporter {
    static func writePasteboard(_ image: CGImage) throws {
        let png = try Imaging.data(image, type: .png)
        let nsImage = NSImage(cgImage: image, size: .zero)
        guard let tiff = nsImage.tiffRepresentation else { throw ImagingError.export }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(png, forType: .png) else { throw ImagingError.export }
        pasteboard.setData(tiff, forType: .tiff)
    }

    static func writeFile(_ image: CGImage, to url: URL, format: SaveFormat, quality: Double) throws {
        let data: Data
        if format == .jpeg {
            data = try Imaging.data(image, type: .jpeg, quality: quality)
        } else {
            data = try Imaging.data(image, type: .png)
        }
        try data.write(to: url, options: .atomic)
    }

    static func timestamp() -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    /// Ensures the configured directory exists and is writable.
    static func ensureDirectory(_ url: URL) throws {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        if manager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw ExportError.notWritable(url) }
        } else {
            try manager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        guard manager.isWritableFile(atPath: url.path) else { throw ExportError.notWritable(url) }
    }

    static func defaultFileURL(directory: URL, format: SaveFormat) -> URL {
        directory.appendingPathComponent("拾影-\(timestamp()).\(format.fileExtension)")
    }

    enum ExportError: LocalizedError {
        case notWritable(URL)
        var errorDescription: String? {
            switch self {
            case .notWritable(let url): return "目录不可写：\(url.path)。请在设置中选择其他保存位置。"
            }
        }
    }
}
