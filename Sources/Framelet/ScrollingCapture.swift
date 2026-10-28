import AppKit
import SwiftUI
import FrameletCore

private actor ScrollAssembly {
    private let stitcher: ScrollStitcher
    private var lastPreview = Date.distantPast
    private let previewWidth: Int
    init(_ first: CGImage, previewWidth: Int) throws { stitcher = try ScrollStitcher(first: first); self.previewWidth = previewWidth }
    func append(_ image: CGImage) throws -> (ScrollAppendResult, CGImage?, Int, Int) {
        let result = try stitcher.append(image)
        let preview: CGImage?
        if case .appended = result, Date().timeIntervalSince(lastPreview) >= 0.25 {
            preview = try stitcher.image(previewWidth: previewWidth); lastPreview = Date()
        } else { preview = nil }
        return (result, preview, stitcher.height, stitcher.addedFrames)
    }
    func image() throws -> CGImage { try stitcher.image() }
}

@MainActor final class ScrollingCapture: ObservableObject {
    @Published var message = "准备长截图，请先保持页面静止…"
    @Published var dimensions = ""
    @Published var preview: NSImage?
    @Published var ready = false
    @Published var paused = false
    @Published var finishing = false
    private var panel: NSPanel?
    private var border: NSPanel?
    private var task: Task<Void, Never>?
    private var warningTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<CaptureOutcome, Never>?
    private var assembly: ScrollAssembly?
    private let settings: AppSettingsStore
    private let region: LastRegion
    private var source: ScrollFrameStream?
    init(settings: AppSettingsStore, region: LastRegion) {
        self.settings = settings; self.region = region
    }
    var completionTitle: String { settings.settings.completionAction.title + "并结束" }

    func run() async -> CaptureOutcome {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            showPanels()
            task = Task { [weak self] in await self?.poll() }
        }
    }
    private func showPanels() {
        let border = NSPanel(contentRect: region.selection.insetBy(dx: -8, dy: -8), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        border.isOpaque = false; border.backgroundColor = .clear; border.hasShadow = false
        border.ignoresMouseEvents = true; border.level = .floating; border.hidesOnDeactivate = false
        border.contentView = NSHostingView(rootView: Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
        border.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        border.orderFrontRegardless(); self.border = border
        let panel = ScrollControlPanel(contentRect: NSRect(x: 0, y: 0, width: 310, height: 350), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "长截图 · 拾影"; panel.isReleasedWhenClosed = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ScrollCaptureView(model: self))
        let screen = NSScreen.screens.first { $0.frame == region.screenFrame }?.visibleFrame ?? region.screenFrame
        let right = region.selection.maxX + 16
        let x = right + 310 < screen.maxX ? right : max(screen.minX + 8, region.selection.minX - 326)
        let y = min(max(screen.minY + 8, region.selection.maxY - 374), screen.maxY - 374)
        panel.onCancel = { [weak self] in self?.cancel() }
        panel.setFrameOrigin(CGPoint(x: x, y: y)); panel.orderFrontRegardless(); panel.makeKey(); self.panel = panel
    }

    private func poll() async {
        defer { task = nil }
        var rejectedSince: Date?
        do {
            let excluded = [panel, border].compactMap { $0.map { CGWindowID($0.windowNumber) } }
            let source = try await ScrollFrameStream.start(region: region, excluding: excluded)
            self.source = source
            guard continuation != nil, !Task.isCancelled else { await source.stop(); return }
            for try await image in source.frames {
                guard continuation != nil, !Task.isCancelled else { break }
                guard !paused && !finishing else { continue }
                guard NSScreen.screens.contains(where: {
                    ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == region.displayID && $0.frame == region.screenFrame
                }) else { throw CaptureError.noDisplay }
                if assembly == nil {
                    assembly = try ScrollAssembly(image, previewWidth: Int(272 * (panel?.backingScaleFactor ?? 2)))
                    preview = NSImage(cgImage: image, size: .zero)
                    dimensions = "\(image.width) × \(image.height) px"
                    ready = true; message = "向下滚动，预览会自动变长；满意后点击完成。"
                } else if let assembly {
                    let (result, thumbnail, height, _) = try await assembly.append(image)
                    guard continuation != nil, !finishing else { break }
                    if let thumbnail { preview = NSImage(cgImage: thumbnail, size: .zero) }
                    dimensions = "\(image.width) × \(height) px"
                    switch result {
                    case .appended:
                        rejectedSince = nil
                        warningTask?.cancel(); warningTask = nil
                        message = "正在拼接 · 继续向下滚动，预览自动更新。"
                    case .unchanged: break
                    case .rejected(let reason):
                        if rejectedSince == nil {
                            rejectedSince = Date()
                            warningTask = Task { [weak self] in
                                do { try await Task.sleep(nanoseconds: 600_000_000) } catch { return }
                                guard let self, self.continuation != nil, !self.paused, !self.finishing else { return }
                                self.message = reason
                            }
                        }
                        // Transient frames during scrolling should not flash an
                        // alarm. Persisting mismatch needs actionable feedback.
                        if Date().timeIntervalSince(rejectedSince!) > 0.6 { message = reason }
                    }
                }
            }
            await source.stop()
        } catch is CancellationError { }
        catch {
            await source?.stop(); source = nil
            guard continuation != nil else { return }
            paused = true; message = "截取失败：\(error.localizedDescription) 请结束当前截图或重试。"
        }
    }
    func togglePause() {
        paused.toggle()
        warningTask?.cancel(); warningTask = nil
        message = paused ? "已暂停；可以查看预览，或完成当前长截图。" : "已继续，向下滚动会自动拼接。"
        if !paused && task?.isCancelled != false { task = Task { [weak self] in await self?.poll() } }
    }
    func cancel() { finish(.cancelled) }
    func complete() {
        guard ready, !finishing, let assembly else { return }
        finishing = true; paused = true
        Task {
            do {
                let stitched = try await assembly.image()
                let scale = region.selection.width > 0 ? CGFloat(stitched.width) / region.selection.width : 1
                let image = try Imaging.roundedCorners(stitched, radius: CGFloat(settings.settings.effectiveSelectionCornerRadius) * scale)
                guard continuation != nil else { return }
                let action = settings.settings.completionAction
                switch action {
                case .copy: try CaptureExporter.writePasteboard(image)
                case .save, .saveAndCopy:
                    try settings.withSaveDirectory { directory in
                        try CaptureExporter.ensureDirectory(directory)
                        let url = CaptureExporter.defaultFileURL(directory: directory, format: settings.settings.saveFormat)
                        try CaptureExporter.writeFile(image, to: url, format: settings.settings.saveFormat, quality: settings.settings.jpegQuality)
                    }
                    if action == .saveAndCopy || settings.settings.copyOnSave { try CaptureExporter.writePasteboard(image) }
                case .pin:
                    if settings.settings.copyOnPin { try CaptureExporter.writePasteboard(image) }
                    finish(.pinned(image, name: "长截图", lastRegion: region)); return
                }
                finish(.finished(lastRegion: region))
            } catch { finishing = false; message = "未能完成：\(error.localizedDescription)；结果仍保留，可重试。" }
        }
    }
    private func finish(_ outcome: CaptureOutcome) {
        guard let continuation else { return }
        self.continuation = nil; task?.cancel(); task = nil
        warningTask?.cancel(); warningTask = nil
        panel?.orderOut(nil); panel?.contentView = nil; panel = nil
        border?.orderOut(nil); border?.contentView = nil; border = nil
        self.assembly = nil
        let source = self.source; self.source = nil
        Task { await source?.stop(); continuation.resume(returning: outcome) }
    }
}

private final class ScrollControlPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

private struct ScrollCaptureView: View {
    @ObservedObject var model: ScrollingCapture
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.dimensions.isEmpty ? "准备长截图" : model.dimensions).font(.system(.headline, design: .monospaced))
            ScrollViewReader { proxy in
                ScrollView {
                    if let image = model.preview {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit().frame(maxWidth: 272)
                    }
                    Color.clear.frame(height: 1).id("tail")
                }.onChange(of: model.dimensions) { _, _ in proxy.scrollTo("tail", anchor: .bottom) }
            }.frame(height: 170).background(Color.black.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 6))
            Text(model.message).font(.system(size: 12)).frame(height: 48, alignment: .topLeading)
            HStack {
                Button("取消") { model.cancel() }
                Button(model.paused ? "继续" : "暂停") { model.togglePause() }.disabled(model.finishing)
                Spacer()
                Button(model.completionTitle) { model.complete() }.buttonStyle(.borderedProminent).disabled(!model.ready || model.finishing)
            }
        }.padding(14).frame(width: 310, height: 350).background(Palette.surface)
    }
}
