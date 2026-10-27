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
    @Published var selectionPixelRect: CGRect = .zero
    @Published private(set) var marks: [Mark] = [] {
        didSet { cachedPreview = nil }
    }
    private var cachedPreview: CGImage?
    @Published var tool: MarkTool? = nil
    @Published var color: NSColor
    @Published var strokeWidth: CGFloat
    @Published var fontSize: CGFloat
    @Published var message: String?
    @Published var recognizing = false
    @Published var ocrText: String?
    @Published var showOCR = false
    private(set) var sessionID = UUID()
    private var valid = true
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    struct Snapshot {
        var marks: [Mark]
        var selection: CGRect
    }

    init(fullImage: CGImage, name: String, color: NSColor, strokeWidth: CGFloat, fontSize: CGFloat) {
        self.fullImage = fullImage
        self.name = name
        self.color = color
        self.strokeWidth = strokeWidth
        self.fontSize = fontSize
    }

    private var exportPixelRect: CGRect {
        CaptureGeometry.cropRect(selectionPixelRect, imageSize: CGSize(width: fullImage.width, height: fullImage.height))
    }
    var pixelWidth: Int { max(1, Int(exportPixelRect.width)) }
    var pixelHeight: Int { max(1, Int(exportPixelRect.height)) }

    /// Marks the document as discarded so late OCR results cannot reopen UI for
    /// a session that already ended.
    func invalidate() { valid = false }
    var isActive: Bool { valid }

    private var snapshot: Snapshot { Snapshot(marks: marks, selection: selectionPixelRect) }

    /// Records the pre-edit state so undo/redo covers both annotation and
    /// selection adjustments in one timeline.
    func beginEdit() {
        undoStack.append(snapshot)
        if undoStack.count > 200 { undoStack.removeFirst(undoStack.count - 200) }
        redoStack.removeAll()
    }

    func append(_ mark: Mark) { beginEdit(); marks.append(mark) }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        marks = previous.marks
        selectionPixelRect = previous.selection
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        marks = next.marks
        selectionPixelRect = next.selection
    }

    var canRedo: Bool { !redoStack.isEmpty }
    var canUndo: Bool { !undoStack.isEmpty }

    func flattened() throws -> CGImage {
        try Imaging.renderCropped(previewImage(), marks: [], selectionPixelRect: selectionPixelRect)
    }

    /// Full-resolution composite anchored to the display. Selection geometry
    /// changes only the clip; moving/resizing must not move or resize pixels.
    func previewImage(pending: Mark? = nil) throws -> CGImage {
        if let pending { return try Imaging.render(fullImage, marks: marks + [pending]) }
        if let cachedPreview { return cachedPreview }
        let image = marks.isEmpty ? fullImage : try Imaging.render(fullImage, marks: marks)
        cachedPreview = image
        return image
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
                guard let self, self.isActive, self.sessionID == id else { return } // stale session
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
    /// Single production write path; `Imaging.writePasteboard` is shared with the
    /// checks so tests exercise the real implementation against an isolated
    /// pasteboard instead of duplicating it.
    static func writePasteboard(_ image: CGImage) throws {
        try Imaging.writePasteboard(image, to: .general)
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
