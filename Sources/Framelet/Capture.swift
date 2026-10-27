import AppKit
import ScreenCaptureKit
import FrameletCore
import SwiftUI
import Combine

enum CaptureOutcome {
    case cancelled
    case finished
    case pinned(ImageDocument)
}

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

@MainActor final class CaptureService {
    private var overlays: [NSWindow] = []
    private var selectionContinuation: CheckedContinuation<CaptureOutcome, Error>?
    private var clickMonitor: Any?
    private var capturing = false

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
        guard !capturing else { return .cancelled }
        capturing = true; defer { capturing = false }
        try requirePermission()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let app = content.applications.first { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let windowImage = try await targetWindow.mapAsync { try await self.window($0) }
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        let targetRect = targetWindow.map { CGRect(x: $0.frame.minX, y: desktopTop-$0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
        var snapshots: [(NSScreen, CGImage)] = []
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            snapshots.append((screen, try await screenshot(display, excluding: app)))
        }
        guard !snapshots.isEmpty else { throw CaptureError.noDisplay }
        return try await withCheckedThrowingContinuation { continuation in
            selectionContinuation = continuation
            for (screen, image) in snapshots {
                let window = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.title = "截图 · Framelet"
                window.level = .screenSaver; window.isOpaque = true; window.hasShadow = false
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                let view = RegionView(image: image) { [weak self] outcome in self?.finish(.success(outcome)) }
                view.saveRequested = { [weak self] document in
                    guard let self else { return }
                    let levels = self.overlays.map { ($0,$0.level) }
                    levels.forEach { $0.0.level = .normal }
                    let saved = document.save()
                    levels.forEach { $0.0.level = $0.1 }
                    if saved { self.finish(.success(.finished)) }
                    else {
                        levels.forEach { $0.0.orderFrontRegardless() }
                        if let active = levels.first(where: { ($0.0.contentView as? RegionView)?.contains(document) == true })?.0 {
                            active.makeKeyAndOrderFront(nil)
                        }
                    }
                }
                window.contentView = view; overlays.append(window)
                window.orderFrontRegardless()
                if NSMouseInRect(NSEvent.mouseLocation, screen.frame, false) { window.makeKeyAndOrderFront(nil) }
                if let targetRect, let windowImage, screen.frame.contains(CGPoint(x: targetRect.midX,y: targetRect.midY)) {
                    let local = targetRect.offsetBy(dx: -screen.frame.minX,dy: -screen.frame.minY).intersection(view.bounds)
                    view.select(local, image: windowImage, name: targetWindow?.title ?? "窗口截图")
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
    let image: CGImage
    let complete: (CaptureOutcome) -> Void
    var saveRequested: ((ImageDocument) -> Void)?
    private var document: ImageDocument?
    private var canvas: CanvasView?
    private var toolbar: NSView?
    private var moving: (rect: CGRect, point: CGPoint)?
    private var resizingAnchor: CGPoint?
    private var documentObservation: AnyCancellable?
    private var start: CGPoint?
    private var current: CGPoint?
    private var selection: CGRect? {
        guard let a = start, let b = current else { return nil }
        return CGRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(a.x-b.x), height: abs(a.y-b.y))
    }
    init(image: CGImage, complete: @escaping (CaptureOutcome) -> Void) {
        self.image = image; self.complete = complete; super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.draw(image, in: bounds)
        NSColor.black.withAlphaComponent(0.36).setFill(); bounds.fill()
        if let selection {
            ctx.saveGState(); ctx.clip(to: selection); ctx.draw(image, in: bounds); ctx.restoreGState()
            NSColor.white.setStroke(); let border = NSBezierPath(rect: selection); border.lineWidth = 1.5; border.stroke()
            if document?.marks.isEmpty == true {
                NSColor.white.setFill()
                for p in [CGPoint(x:selection.minX,y:selection.minY),CGPoint(x:selection.maxX,y:selection.minY),CGPoint(x:selection.minX,y:selection.maxY),CGPoint(x:selection.maxX,y:selection.maxY)] {
                    CGRect(x:p.x-3,y:p.y-3,width:6,height:6).fill()
                }
            }
            let scale = CGFloat(image.width)/max(1,bounds.width)
            let label = "\(Int(selection.width*scale)) × \(Int(selection.height*scale))"
            drawLabel(label, at: CGPoint(x: min(max(12,selection.minX),max(12,bounds.width-160)), y: min(bounds.height-40,max(12,selection.maxY+10))))
        } else {
            drawLabel("拖动选择区域 · Esc 取消", at: CGPoint(x: max(20,bounds.midX-130), y: bounds.midY+40))
        }
    }
    private func drawLabel(_ string: String, at point: CGPoint) {
        let value = NSAttributedString(string: string, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white])
        let size = value.size()
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: CGRect(x: point.x-10, y: point.y-7, width: size.width+20, height: size.height+14), xRadius: 7, yRadius: 7).fill()
        value.draw(at: point)
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let selection, document?.marks.isEmpty == true, let anchor = resizeAnchor(at: point,selection: selection) {
            resizingAnchor = anchor; canvas?.isHidden = true; toolbar?.isHidden = true
        } else if let selection, let document, selection.contains(point) {
            moving = (selection,point); canvas?.isHidden = document.marks.isEmpty; toolbar?.isHidden = true
        } else if document == nil {
            start = point; current = point
        }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let anchor = resizingAnchor {
            start = anchor
            current = CGPoint(x:max(0,min(bounds.width,point.x)),y:max(0,min(bounds.height,point.y)))
            needsDisplay = true; return
        }
        if let moving {
            let dx = min(max(point.x-moving.point.x,-moving.rect.minX),bounds.width-moving.rect.maxX)
            let dy = min(max(point.y-moving.point.y,-moving.rect.minY),bounds.height-moving.rect.maxY)
            start = moving.rect.origin.applying(CGAffineTransform(translationX:dx,y:dy))
            current = CGPoint(x:moving.rect.maxX+dx,y:moving.rect.maxY+dy)
            if document?.marks.isEmpty == false, let selection { canvas?.frame = selection }
            needsDisplay = true; return
        }
        guard document == nil else { return }
        current = CGPoint(x: max(0,min(bounds.width,point.x)), y: max(0,min(bounds.height,point.y)))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard document == nil || moving != nil || resizingAnchor != nil else { return }
        let preserveMarks = moving != nil && document?.marks.isEmpty == false
        moving = nil
        resizingAnchor = nil
        if preserveMarks, let selection {
            canvas?.isHidden = false; toolbar?.isHidden = false
            toolbar?.frame = CaptureLayout.toolbarFrame(selection:selection,screen:bounds,preferredSize:CGSize(width:820,height:94))
            needsDisplay = true; return
        }
        if let selection { select(selection) }
    }
    override func rightMouseDown(with event: NSEvent) { complete(.cancelled) }

    func select(_ rect: CGRect, image supplied: CGImage? = nil, name: String = "区域截图") {
        let rect = rect.standardized.intersection(bounds)
        guard !rect.isNull, rect.width >= 4, rect.height >= 4 else { resetSelection(); return }
        let crop = Imaging.cropRect(selection: rect, screenSize: bounds.size,imageSize: CGSize(width: image.width,height: image.height))
        guard let captured = supplied ?? image.cropping(to: crop) else { resetSelection(); return }
        start = rect.origin; current = CGPoint(x:rect.maxX,y:rect.maxY)
        canvas?.removeFromSuperview(); toolbar?.removeFromSuperview()
        let doc = ImageDocument(image: captured,name: name); document = doc
        documentObservation = doc.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.needsDisplay = true } }
        let canvas = CanvasView(document: doc,padding: 0,inlineText: true)
        canvas.drawingEnabled = false; canvas.frame = rect; self.canvas = canvas; addSubview(canvas)
        let controls = InlineCaptureToolbar(document: doc, chooseTool: { [weak self] tool in
            self?.canvas?.commitText()
            if let tool { doc.tool = tool }
            self?.canvas?.drawingEnabled = tool != nil
            self?.window?.invalidateCursorRects(for: canvas)
        }, action: { [weak self] action in self?.perform(action) })
        let host = NSHostingView(rootView: controls)
        host.frame = CaptureLayout.toolbarFrame(selection: rect,screen: bounds,preferredSize: CGSize(width: 820,height: 94))
        host.wantsLayer = true; host.layer?.cornerRadius = 12; host.layer?.masksToBounds = false
        host.layer?.shadowColor = NSColor.black.cgColor; host.layer?.shadowOpacity = 0.22
        host.layer?.shadowRadius = 16; host.layer?.shadowOffset = CGSize(width:0,height:-4)
        toolbar = host; addSubview(host); needsDisplay = true
        window?.makeFirstResponder(self)
    }
    private func resetSelection() {
        canvas?.removeFromSuperview(); toolbar?.removeFromSuperview()
        canvas = nil; toolbar = nil; document = nil; documentObservation = nil
        start = nil; current = nil; moving = nil; resizingAnchor = nil
        needsDisplay = true
    }
    private func perform(_ action: InlineAction) {
        canvas?.commitText()
        guard let document else { if action == .cancel { complete(.cancelled) }; return }
        switch action {
        case .cancel: complete(.cancelled)
        case .reselect: resetSelection()
        case .copy: if document.copy() { complete(.finished) }
        case .save: saveRequested?(document)
        case .pin: complete(.pinned(document))
        case .ocr: document.recognize()
        case .undo: document.undo()
        case .redo: document.redo()
        }
    }
    func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { complete(.cancelled); return true }
        guard document != nil else { return false }
        if event.keyCode == 36 || event.keyCode == 76 { perform(.copy); return true }
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": perform(.copy); return true
            case "s": perform(.save); return true
            case "z": perform(event.modifierFlags.contains(.shift) ? .redo : .undo); return true
            default: break
            }
        }
        return false
    }
    func contains(_ candidate: ImageDocument) -> Bool { document === candidate }
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let toolbar, toolbar.frame.contains(point) { return super.hitTest(point) }
        if let selection, document?.marks.isEmpty == true, resizeAnchor(at:point,selection:selection) != nil { return self }
        return super.hitTest(point)
    }
    private func resizeAnchor(at point: CGPoint, selection: CGRect) -> CGPoint? {
        let corners = [CGPoint(x:selection.minX,y:selection.minY),CGPoint(x:selection.maxX,y:selection.minY),CGPoint(x:selection.minX,y:selection.maxY),CGPoint(x:selection.maxX,y:selection.maxY)]
        for corner in corners where hypot(point.x-corner.x,point.y-corner.y) <= 9 {
            return CGPoint(x:selection.minX+selection.maxX-corner.x,y:selection.minY+selection.maxY-corner.y)
        }
        return nil
    }
}

private extension Optional {
    func mapAsync<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        switch self { case .some(let value): return try await transform(value); case .none: return nil }
    }
}
