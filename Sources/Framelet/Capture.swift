import AppKit
import ScreenCaptureKit
import FrameletCore
import SwiftUI
import Combine

enum CaptureOutcome {
    case cancelled
    case finished(lastRegion: LastRegion?)
    case pinned(CGImage, name: String, lastRegion: LastRegion?)
}

enum SessionPhase { case selecting, editing, committing }

enum CaptureError: LocalizedError {
    case permission, noDisplay, emptyRegion
    var errorDescription: String? {
        switch self {
        case .permission: return "请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许拾影。授权后若仍无法截图，请退出并重新打开拾影。"
        case .noDisplay: return "未找到可截图的显示器，请检查显示器连接后重试。"
        case .emptyRegion: return "选区太小，请重新拖动选择截图范围。"
        }
    }
}

extension NSColor {
    convenience init(rgb: RGBValue) { self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1) }
}

@MainActor final class CaptureService {
    private var overlays: [NSWindow] = []
    private var selectionContinuation: CheckedContinuation<CaptureOutcome, Error>?
    private var clickMonitor: Any?
    private var capturing = false
    private let settings: AppSettingsStore
    var onPhase: ((SessionPhase) -> Void)?

    init(settings: AppSettingsStore) { self.settings = settings }

    func requirePermission() throws {
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            throw CaptureError.permission
        }
    }

    private func screenshot(_ display: SCDisplay, excluding app: SCRunningApplication?) async throws -> CGImage {
        let filter = SCContentFilter(display: display, excludingApplications: app.map { [$0] } ?? [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = max(1, Int(filter.contentRect.width * scale))
        config.height = max(1, Int(filter.contentRect.height * scale))
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    func fullScreen() async throws -> CGImage {
        try requirePermission()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let id = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == id }) ?? content.displays.first else { throw CaptureError.noDisplay }
        let app = content.applications.first { $0.processID == ProcessInfo.processInfo.processIdentifier }
        return try await screenshot(display, excluding: app)
    }

    func region(selectFullScreen: Bool = false, window targetWindow: SCWindow? = nil) async throws -> CaptureOutcome {
        let windowImage = try await targetWindow.mapAsync { try await self.window($0) }
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        let targetRect = targetWindow.map { CGRect(x: $0.frame.minX, y: desktopTop - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
        return try await runRegion(selectFullScreen: selectFullScreen, targetRect: targetRect, windowImage: windowImage, windowName: targetWindow?.title, preset: nil)
    }

    func lastRegionCapture(_ last: LastRegion) async throws -> CaptureOutcome {
        guard NSScreen.screens.contains(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == last.displayID
                && $0.frame.equalTo(last.screenFrame)
        }) else { throw CaptureError.emptyRegion }
        return try await runRegion(selectFullScreen: false, targetRect: nil, windowImage: nil, windowName: nil, preset: last)
    }

    private func runRegion(selectFullScreen: Bool, targetRect: CGRect?, windowImage: CGImage?, windowName: String?, preset: LastRegion?) async throws -> CaptureOutcome {
        guard !capturing else { return .cancelled }
        capturing = true; defer { capturing = false }
        try requirePermission()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let app = content.applications.first { $0.processID == ProcessInfo.processInfo.processIdentifier }
        var snapshots: [(NSScreen, UInt32, CGImage)] = []
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            snapshots.append((screen, id, try await screenshot(display, excluding: app)))
        }
        guard !snapshots.isEmpty else { throw CaptureError.noDisplay }
        return try await withCheckedThrowingContinuation { continuation in
            selectionContinuation = continuation
            for (screen, displayID, image) in snapshots {
                let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.title = "截图 · Framelet"
                window.level = .screenSaver; window.isOpaque = true; window.hasShadow = false
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                let view = RegionView(image: image, screenFrame: screen.frame, displayID: displayID, settings: settings) { [weak self] outcome in
                    self?.finish(.success(outcome))
                } presentPanel: { [weak self] panel in
                    guard let self else { return .cancel }
                    let levels = self.overlays.map { ($0, $0.level) }
                    levels.forEach { $0.0.level = .normal }
                    let response = panel.runModal()
                    levels.forEach { $0.0.level = $0.1 }
                    return response
                } onPhase: { [weak self] phase in
                    self?.onPhase?(phase)
                }
                window.contentView = view; overlays.append(window)
                window.orderFrontRegardless()
                if NSMouseInRect(NSEvent.mouseLocation, screen.frame, false) { window.makeKeyAndOrderFront(nil) }
                if let targetRect, windowImage != nil, screen.frame.contains(CGPoint(x: targetRect.midX, y: targetRect.midY)) {
                    let local = targetRect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY).intersection(view.bounds)
                    view.select(local, name: windowName ?? "窗口截图")
                    window.makeKeyAndOrderFront(nil)
                } else if let preset, screen.frame.equalTo(preset.screenFrame) {
                    let local = preset.selection.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY).intersection(view.bounds)
                    view.select(local, name: "上次区域截图")
                    window.makeKeyAndOrderFront(nil)
                } else if selectFullScreen && NSMouseInRect(NSEvent.mouseLocation, screen.frame, false) {
                    view.select(view.bounds, name: "全屏截图")
                }
            }
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = event.window, self.overlays.contains(window), !(window.firstResponder is NSTextView) else { return event }
                if let view = window.contentView as? RegionView, view.handleKey(event) { return nil }
                return event
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func finish(_ result: Result<CaptureOutcome, Error>) {
        guard let continuation = selectionContinuation else { return }
        selectionContinuation = nil
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor) }; clickMonitor = nil
        for window in overlays { window.orderOut(nil); window.contentView = nil }
        overlays.removeAll()
        continuation.resume(with: result)
    }

    func windows() async throws -> [SCWindow] {
        try requirePermission()
        return try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true).windows
            .filter { $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && $0.windowLayer == 0 && $0.frame.width > 60 && $0.frame.height > 40 }
            .sorted { ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "") }
    }

    func window(_ window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = max(1, Int(filter.contentRect.width * scale))
        config.height = max(1, Int(filter.contentRect.height * scale))
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

private final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class RegionView: NSView {
    private let image: CGImage
    private let imageSize: CGSize
    private let screenFrame: CGRect
    private let displayID: UInt32
    private let settings: AppSettingsStore
    private let onFinish: (CaptureOutcome) -> Void
    private let presentPanel: (NSSavePanel) -> NSApplication.ModalResponse
    private let onPhase: ((SessionPhase) -> Void)?

    private var document: CaptureDocument?
    private var canvas: CaptureCanvasView?
    private var toolbar: NSHostingView<InlineCaptureToolbar>?
    private var moving: (rect: CGRect, point: CGPoint)?
    private var resizing: (kind: CaptureGeometry.HandleKind, original: CGRect)?
    private var documentObservation: AnyCancellable?
    private var start: CGPoint?
    private var current: CGPoint?
    private var committing = false

    private var selection: CGRect? {
        guard let a = start, let b = current else { return nil }
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    init(image: CGImage, screenFrame: CGRect, displayID: UInt32, settings: AppSettingsStore,
         onFinish: @escaping (CaptureOutcome) -> Void, presentPanel: @escaping (NSSavePanel) -> NSApplication.ModalResponse,
         onPhase: ((SessionPhase) -> Void)? = nil) {
        self.image = image
        self.imageSize = CGSize(width: image.width, height: image.height)
        self.screenFrame = screenFrame
        self.displayID = displayID
        self.settings = settings
        self.onFinish = onFinish
        self.presentPanel = presentPanel
        self.onPhase = onPhase
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override var acceptsFirstResponder: Bool { true }

    // MARK: Drawing
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.draw(image, in: bounds)
        NSColor.black.withAlphaComponent(0.36).setFill(); bounds.fill()
        if let selection {
            ctx.saveGState(); ctx.clip(to: selection); ctx.draw(image, in: bounds); ctx.restoreGState()
            drawSelectionBorder(selection)
            drawSizeLabel(selection)
        } else {
            drawLabel("拖动选择区域 · Esc 取消", at: CGPoint(x: max(20, bounds.midX - 130), y: bounds.midY + 40))
        }
    }

    private func drawSelectionBorder(_ selection: CGRect) {
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection); border.lineWidth = 1.5; border.stroke()
        if document?.tool == nil {
            NSColor.white.setFill()
            for handle in CaptureGeometry.resizeHandles(for: selection) {
                CGRect(x: handle.x - 4, y: handle.y - 4, width: 8, height: 8).fill()
            }
        }
    }

    private func drawSizeLabel(_ selection: CGRect) {
        let scale = CGFloat(image.width) / max(1, bounds.width)
        let label = "\(Int(selection.width * scale)) × \(Int(selection.height * scale))"
        drawLabel(label, at: CGPoint(x: min(max(12, selection.minX), max(12, bounds.width - 160)),
                                     y: min(bounds.height - 40, max(12, selection.maxY + 10))))
    }

    private func drawLabel(_ string: String, at point: CGPoint) {
        let value = NSAttributedString(string: string, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white])
        let size = value.size()
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: CGRect(x: point.x - 10, y: point.y - 7, width: size.width + 20, height: size.height + 14), xRadius: 7, yRadius: 7).fill()
        value.draw(at: point)
    }

    // MARK: Mouse
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let selection, let document, document.tool == nil {
            if let kind = CaptureGeometry.handleKind(at: point, selection: selection) {
                resizing = (kind, selection)
                canvas?.isHidden = true; toolbar?.isHidden = true
                needsDisplay = true
                return
            }
            if selection.contains(point) {
                if event.clickCount == 2 { performDoubleClick(); return }
                moving = (selection, point)
                toolbar?.isHidden = true
                needsDisplay = true
                return
            }
            resetSelection()
            start = point; current = point
            needsDisplay = true
            return
        }
        if document == nil {
            start = point; current = point
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let resizing {
            guard let newSelection = CaptureGeometry.resized(selection: resizing.original, kind: resizing.kind, to: point, bounds: bounds) else { return }
            applySelection(newSelection)
            return
        }
        if let moving {
            let origin = CGPoint(x: moving.rect.minX + point.x - moving.point.x, y: moving.rect.minY + point.y - moving.point.y)
            applySelection(CaptureGeometry.moved(selection: moving.rect, to: origin, bounds: bounds))
            return
        }
        if document == nil {
            current = CGPoint(x: max(0, min(bounds.width, point.x)), y: max(0, min(bounds.height, point.y)))
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        if document == nil, let selection {
            moving = nil; resizing = nil
            select(selection, name: "区域截图")
            return
        }
        moving = nil; resizing = nil
        canvas?.isHidden = false; toolbar?.isHidden = false
        repositionToolbar()
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) { cancelCapture() }

    private func applySelection(_ rect: CGRect) {
        start = rect.origin
        current = CGPoint(x: rect.maxX, y: rect.maxY)
        canvas?.frame = rect
        document?.selectionPixelRect = CaptureGeometry.pixelRect(rect, viewBounds: bounds, imageSize: imageSize)
        needsDisplay = true
    }

    // MARK: Selection lifecycle
    func select(_ rect: CGRect, name: String) {
        let rect = rect.standardized.intersection(bounds)
        guard !rect.isNull, rect.width >= 4, rect.height >= 4 else { resetSelection(); return }
        onPhase?(.editing)
        start = rect.origin; current = CGPoint(x: rect.maxX, y: rect.maxY)
        canvas?.removeFromSuperview(); toolbar?.removeFromSuperview()
        let scale = CaptureGeometry.scale(viewBounds: bounds, imageSize: imageSize)
        let doc = CaptureDocument(fullImage: image, name: name,
                                  color: NSColor(rgb: settings.settings.annotationColor),
                                  strokeWidth: CGFloat(settings.settings.strokeWidth),
                                  fontSize: CGFloat(settings.settings.fontSize))
        doc.scale = scale
        doc.selectionPixelRect = CaptureGeometry.pixelRect(rect, viewBounds: bounds, imageSize: imageSize)
        document = doc
        documentObservation = doc.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.needsDisplay = true
                self?.repositionToolbar()
            }
        }
        let canvas = CaptureCanvasView(document: doc)
        canvas.drawingEnabled = false
        canvas.frame = rect
        self.canvas = canvas
        addSubview(canvas)
        let toolbarView = InlineCaptureToolbar(document: doc, settings: settings, chooseTool: { [weak self] tool in
            self?.setTool(tool)
        }, action: { [weak self] action in
            self?.perform(action)
        })
        let host = NSHostingView(rootView: toolbarView)
        host.wantsLayer = true; host.layer?.cornerRadius = 11; host.layer?.masksToBounds = false
        host.layer?.shadowColor = NSColor.black.cgColor; host.layer?.shadowOpacity = 0.22
        host.layer?.shadowRadius = 16; host.layer?.shadowOffset = CGSize(width: 0, height: -4)
        toolbar = host
        addSubview(host)
        repositionToolbar()
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    private func resetSelection() {
        canvas?.removeFromSuperview(); toolbar?.removeFromSuperview()
        canvas = nil; toolbar = nil; document = nil; documentObservation = nil
        start = nil; current = nil; moving = nil; resizing = nil
        needsDisplay = true
    }

    private func setTool(_ tool: MarkTool?) {
        canvas?.commitText()
        document?.tool = tool
        canvas?.drawingEnabled = tool != nil
        if let canvas { window?.invalidateCursorRects(for: canvas) }
        repositionToolbar()
        needsDisplay = true
    }

    private func repositionToolbar() {
        guard let toolbar, let selection else { return }
        let showProps = document?.tool != nil
        let preferred = CGSize(width: 900, height: showProps ? 84 : 44)
        toolbar.frame = CaptureLayout.toolbarFrame(selection: selection, screen: bounds, preferredSize: preferred)
    }

    private func makeLastRegion() -> LastRegion? {
        guard let selection else { return nil }
        let global = selection.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
        return LastRegion(displayID: displayID, screenFrame: screenFrame, selection: global)
    }

    // MARK: Actions
    private func perform(_ action: InlineAction) {
        canvas?.commitText()
        guard let document else {
            if action == .cancel { cancelCapture() }
            return
        }
        switch action {
        case .cancel: cancelCapture()
        case .reselect: resetSelection()
        case .save: performSave()
        case .pin: performPin()
        case .ocr: document.recognize()
        case .undo: document.undo()
        case .redo: document.redo()
        case .complete: performComplete()
        }
    }

    private func performDoubleClick() {
        guard let document, document.tool == nil else { return }
        switch settings.settings.doubleClickAction {
        case .followCompletion: performComplete()
        case .none: break
        }
    }

    private func performComplete() {
        canvas?.commitText()
        guard let document, !committing else { return }
        committing = true
        onPhase?(.committing)
        let action = settings.settings.completionAction
        do {
            let image = try document.flattened()
            switch action {
            case .copy:
                try CaptureExporter.writePasteboard(image)
                document.message = "已复制图片"
            case .save, .saveAndCopy:
                let url = try saveToDefaultDirectory(image)
                if action == .saveAndCopy || settings.settings.copyOnSave {
                    try CaptureExporter.writePasteboard(image)
                }
                document.message = "已保存到 \(url.lastPathComponent)"
            case .pin:
                if settings.settings.copyOnPin { try CaptureExporter.writePasteboard(image) }
                onFinish(.pinned(image, name: document.name, lastRegion: makeLastRegion()))
                return
            }
            onFinish(.finished(lastRegion: makeLastRegion()))
        } catch {
            committing = false
            document.message = error.localizedDescription
            showError(error)
        }
    }

    private func performSave() {
        canvas?.commitText()
        guard let document, !committing else { return }
        committing = true
        onPhase?(.committing)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = "拾影-\(CaptureExporter.timestamp()).\(settings.settings.saveFormat.fileExtension)"
        panel.canCreateDirectories = true
        panel.directoryURL = lastSavedURL ?? settings.saveDirectoryURL
        let response = presentPanel(panel)
        guard response == .OK, let url = panel.url else {
            committing = false
            return
        }
        do {
            let image = try document.flattened()
            try CaptureExporter.writeFile(image, to: url, format: saveFormat(for: url), quality: settings.settings.jpegQuality)
            if settings.settings.copyOnSave { try CaptureExporter.writePasteboard(image) }
            lastSavedURL = url.deletingLastPathComponent()
            onFinish(.finished(lastRegion: makeLastRegion()))
        } catch {
            committing = false
            document.message = error.localizedDescription
            showError(error)
        }
    }

    private func performPin() {
        canvas?.commitText()
        guard let document, !committing else { return }
        do {
            let image = try document.flattened()
            if settings.settings.copyOnPin { try CaptureExporter.writePasteboard(image) }
            onFinish(.pinned(image, name: document.name, lastRegion: makeLastRegion()))
        } catch {
            document.message = error.localizedDescription
            showError(error)
        }
    }

    private func saveToDefaultDirectory(_ image: CGImage) throws -> URL {
        let directory = settings.saveDirectoryURL
        try CaptureExporter.ensureDirectory(directory)
        let url = CaptureExporter.defaultFileURL(directory: directory, format: settings.settings.saveFormat)
        try CaptureExporter.writeFile(image, to: url, format: settings.settings.saveFormat, quality: settings.settings.jpegQuality)
        lastSavedURL = directory
        return url
    }

    private func saveFormat(for url: URL) -> SaveFormat {
        ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg : .png
    }

    private var lastSavedURL: URL? {
        get { UserDefaults.standard.string(forKey: "framelet.lastSaveDir").map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { if let newValue { UserDefaults.standard.set(newValue.path, forKey: "framelet.lastSaveDir") } }
    }

    private func cancelCapture() {
        guard !committing else { return }
        canvas?.commitText()
        onFinish(.cancelled)
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "未能完成操作"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "知道了")
        let levels = window.map { [($0, $0.level)] } ?? []
        levels.forEach { $0.0.level = .normal }
        alert.runModal()
        levels.forEach { $0.0.level = $0.1 }
        if let window { window.makeKeyAndOrderFront(nil) }
    }

    func contains(_ candidate: CaptureDocument) -> Bool { document === candidate }

    // MARK: Key handling
    func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Esc
            cancelCapture()
            return true
        }
        guard let document else { return false }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": _ = document.copy(); return true
            case "s": performSave(); return true
            case "z": event.modifierFlags.contains(.shift) ? document.redo() : document.undo(); return true
            default: return false
            }
        }
        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if event.keyCode == 36 || event.keyCode == 76 { performComplete(); return true }
            if let action = toolAction(forKeyCode: event.keyCode) { applyToolAction(action); return true }
        }
        return false
    }

    private func toolAction(forKeyCode keyCode: UInt16) -> ToolKeyAction? {
        for action in ToolKeyAction.allCases {
            if let combo = settings.settings.toolShortcuts[action] ?? nil, combo.keyCode == keyCode {
                return action
            }
        }
        return nil
    }

    private func applyToolAction(_ action: ToolKeyAction) {
        switch action {
        case .move: setTool(nil)
        case .rectangle: setTool(.rectangle)
        case .ellipse: setTool(.ellipse)
        case .arrow: setTool(.arrow)
        case .pen: setTool(.pen)
        case .mosaic: setTool(.pixelate)
        case .text: setTool(.text)
        case .redact: setTool(.redact)
        case .pin: performPin()
        case .ocr: document?.recognize()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let toolbar, toolbar.frame.contains(point) { return super.hitTest(point) }
        if let selection, document?.tool == nil, CaptureGeometry.handleKind(at: point, selection: selection) != nil { return self }
        return super.hitTest(point)
    }
}

private extension Optional {
    func mapAsync<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        switch self { case .some(let value): return try await transform(value); case .none: return nil }
    }
}
