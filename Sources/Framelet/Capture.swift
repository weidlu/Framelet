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
    case permission, noDisplay, emptyRegion, overlayUnavailable
    var errorDescription: String? {
        switch self {
        case .permission: return "请在“系统设置 → 隐私与安全性 → 屏幕与系统音频录制”中允许拾影。授权后若仍无法截图，请退出并重新打开拾影。"
        case .noDisplay: return "未找到可截图的显示器，请检查显示器连接后重试。"
        case .emptyRegion: return "选区太小，请重新拖动选择截图范围。"
        case .overlayUnavailable: return "截图覆盖层未能显示，请重试。"
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
    private var activeRegionView: RegionView?
    private var sessionToken = UUID()
    private var escapeMonitor: Any?

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
        // SCWindow.frame uses CoreGraphics top-left global coordinates; NSScreen
        // uses AppKit bottom-left. Flip against the topmost edge of the whole
        // desktop (not just the primary display) so windows on a raised or
        // secondary display land in the right place.
        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let targetRect = targetWindow.map { window in
            CGRect(x: window.frame.minX, y: desktopTop - window.frame.maxY,
                   width: window.frame.width, height: window.frame.height)
        }
        OverlayDiag.log("window capture frame=\(targetWindow.map { NSStringFromRect($0.frame) } ?? "nil") "
            + "targetRect=\(targetRect.map { NSStringFromRect($0) } ?? "nil") desktopTop=\(desktopTop) "
            + "image=\(windowImage.map { "\($0.width)x\($0.height)" } ?? "nil")")
        return try await runRegion(selectFullScreen: selectFullScreen, targetRect: targetRect, windowImage: windowImage, windowName: targetWindow?.title, preset: nil)
    }

    /// Local acceptance hook: drives the real overlay/toolbar/canvas code with a
    /// synthetic snapshot instead of a ScreenCaptureKit capture. Used only by the
    /// `--capture synthetic` argument so the interaction chain can be exercised
    /// on machines where screen-recording permission is not granted.
    func syntheticCapture(image: CGImage) async throws -> CaptureOutcome {
        try await runRegion(selectFullScreen: false, targetRect: nil, windowImage: nil, windowName: nil, preset: nil, overrideSnapshots: image)
    }

    func lastRegionCapture(_ last: LastRegion) async throws -> CaptureOutcome {
        guard NSScreen.screens.contains(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == last.displayID
                && $0.frame.equalTo(last.screenFrame)
        }) else { throw CaptureError.emptyRegion }
        return try await runRegion(selectFullScreen: false, targetRect: nil, windowImage: nil, windowName: nil, preset: last)
    }

    private func runRegion(selectFullScreen: Bool, targetRect: CGRect?, windowImage: CGImage?, windowName: String?, preset: LastRegion?, overrideSnapshots: CGImage? = nil) async throws -> CaptureOutcome {
        guard !capturing else { return .cancelled }
        capturing = true; defer { capturing = false }
        var snapshots: [(NSScreen, UInt32, CGImage)] = []
        if let overrideSnapshots {
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { throw CaptureError.noDisplay }
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
            snapshots = [(screen, id, overrideSnapshots)]
        } else {
            try requirePermission()
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let app = content.applications.first { $0.processID == ProcessInfo.processInfo.processIdentifier }
            for screen in NSScreen.screens {
                guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                      let display = content.displays.first(where: { $0.displayID == id }) else { continue }
                snapshots.append((screen, id, try await screenshot(display, excluding: app)))
            }
        }
        guard !snapshots.isEmpty else { throw CaptureError.noDisplay }
        sessionToken = UUID()
        let token = sessionToken
        DebugLog.write("runRegion: snapshots=\(snapshots.count) screens=\(NSScreen.screens.count) token=\(token)")
        return try await withCheckedThrowingContinuation { continuation in
            selectionContinuation = continuation
            // Build every overlay first, then present them in one pass. These are
            // non-activating panels, so they do not need (and must not require)
            // our app to be active before they become visible and key.
            var prepared: [(window: NSWindow, view: RegionView, screen: NSScreen)] = []
            for (screen, displayID, image) in snapshots {
                let window = SelectionWindow(screenFrame: screen.frame)
                window.title = "截图 · Framelet"
                window.level = .screenSaver
                window.acceptsMouseMovedEvents = true
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
                OverlayDiag.log("created \(OverlayDiag.describe(window)) screenFrame=\(NSStringFromRect(screen.frame)) image=\(image.width)x\(image.height)")
                window.contentView = view; overlays.append(window)
                OverlayDiag.log("contentView assigned \(OverlayDiag.describe(view))")
                prepared.append((window, view, screen))
            }

            // Robust Esc: accept the key event when it targets any overlay, or
            // when no key window exists yet but an overlay is on screen. This is
            // the fallback that guarantees the session can always be exited.
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, !self.overlays.isEmpty else { return event }
                // Never intercept keys meant for a modal panel or sheet.
                if NSApp.modalWindow != nil { return event }
                if let window = event.window, window.isSheet { return event }
                if event.window?.firstResponder is NSTextView { return event }
                if let window = event.window, self.overlays.contains(window),
                   let view = window.contentView as? RegionView {
                    return view.handleKey(event) ? nil : event
                }
                if let keyWindow = NSApp.keyWindow, self.overlays.contains(keyWindow),
                   let view = keyWindow.contentView as? RegionView {
                    return view.handleKey(event) ? nil : event
                }
                if NSApp.keyWindow == nil, let view = self.activeRegionView {
                    return view.handleKey(event) ? nil : event
                }
                return event
            }

            self.installEscapeFallback(token: token)
            self.present(prepared: prepared, selectFullScreen: selectFullScreen,
                         targetRect: targetRect, windowImage: windowImage,
                         windowName: windowName, preset: preset, token: token)
        }
    }

    /// Presents the overlay immediately. A non-activating panel is visible and
    /// key-capable while another app stays active, so `NSApp.isActive` is NOT a
    /// precondition. Only the key/visible outcome is bounded: if no overlay ever
    /// becomes visible or key, the session is cleaned up with an explicit error.
    private func present(prepared: [(window: NSWindow, view: RegionView, screen: NSScreen)],
                         selectFullScreen: Bool, targetRect: CGRect?, windowImage: CGImage?,
                         windowName: String?, preset: LastRegion?, token: UUID) {
        guard sessionToken == token, selectionContinuation != nil else { return }
        for item in prepared {
            item.window.orderFrontRegardless()
            OverlayDiag.log("reveal orderFrontRegardless \(OverlayDiag.describe(item.window))")
        }
        let target = prepared.first { NSMouseInRect(NSEvent.mouseLocation, $0.screen.frame, false) } ?? prepared.first
        if let target {
            target.window.makeKey()
            target.window.makeFirstResponder(target.view)
            activeRegionView = target.view
            OverlayDiag.log("reveal makeKey \(OverlayDiag.describe(target.window)) firstResponder=\(OverlayDiag.firstResponder())")
        }
        // Preset selections run only now, when bounds are real.
        for item in prepared {
            if let targetRect, let windowImage, item.screen.frame.contains(CGPoint(x: targetRect.midX, y: targetRect.midY)) {
                let local = targetRect.offsetBy(dx: -item.screen.frame.minX, dy: -item.screen.frame.minY).intersection(item.view.bounds)
                item.view.select(local, name: windowName ?? "窗口截图",
                                 windowImage: windowImage, windowViewRect: local)
                item.window.makeKey(); item.window.makeFirstResponder(item.view)
                activeRegionView = item.view
            } else if let preset, item.screen.frame.equalTo(preset.screenFrame) {
                let local = preset.selection.offsetBy(dx: -item.screen.frame.minX, dy: -item.screen.frame.minY).intersection(item.view.bounds)
                item.view.select(local, name: "上次区域截图")
                item.window.makeKey(); item.window.makeFirstResponder(item.view)
                activeRegionView = item.view
            } else if selectFullScreen && NSMouseInRect(NSEvent.mouseLocation, item.screen.frame, false) {
                item.view.select(item.view.bounds, name: "全屏截图")
                item.window.makeKey(); item.window.makeFirstResponder(item.view)
                activeRegionView = item.view
            }
        }
        assertKeyWindow(prepared: prepared, token: token)
        verifyPresentation(prepared: prepared, token: token)
    }

    /// Bounded verification that the overlay is genuinely usable. Success
    /// requires ONE panel that is simultaneously visible, key, on the active
    /// Space and not occluded — `isVisible` alone is exactly the false signal
    /// that let the original "visible but occluded and never key" failure pass.
    /// A single re-assert attempt is allowed; if that still fails, the session is
    /// torn down and reported instead of hanging on a dead overlay.
    private func verifyPresentation(prepared: [(window: NSWindow, view: RegionView, screen: NSScreen)],
                                    token: UUID, attempt: Int = 0) {
        let delay: TimeInterval = 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.sessionToken == token, self.selectionContinuation != nil else { return }
            let target = prepared.first { NSMouseInRect(NSEvent.mouseLocation, $0.screen.frame, false) } ?? prepared.first
            guard let target else {
                OverlayDiag.log("verifyPresentation FAILED: no candidate panel")
                self.finish(.failure(CaptureError.overlayUnavailable))
                return
            }
            let ready = Self.isUsable(target.window)
            OverlayDiag.log("verifyPresentation attempt=\(attempt) ready=\(ready) isActive=\(NSApp.isActive) "
                + "windows=\(prepared.map { OverlayDiag.describe($0.window) })")
            if ready { return }
            if attempt == 0 {
                // One bounded re-assert: a later activation or Space switch can
                // still take key status away right after we ordered the panel.
                if !target.window.isVisible { target.window.orderFrontRegardless() }
                target.window.makeKey()
                target.window.makeFirstResponder(target.view)
                self.activeRegionView = target.view
                self.verifyPresentation(prepared: prepared, token: token, attempt: attempt + 1)
                return
            }
            OverlayDiag.log("presentation FAILED: panel not visible+key+onActiveSpace+unoccluded after re-assert")
            self.finish(.failure(CaptureError.overlayUnavailable))
        }
    }

    /// The single acceptance predicate for a capture overlay.
    private static func isUsable(_ window: NSWindow) -> Bool {
        window.isVisible
            && window.isKeyWindow
            && window.isOnActiveSpace
            && window.occlusionState.contains(.visible)
    }

    /// Re-asserts key window + first responder once the run loop settles. Some
    /// systems deliver activation after our ordering, and a later activation can
    /// steal key status back.
    private func assertKeyWindow(prepared: [(window: NSWindow, view: RegionView, screen: NSScreen)], token: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.sessionToken == token, self.selectionContinuation != nil else { return }
            let target = prepared.first { $0.window.isKeyWindow }
                ?? prepared.first { NSMouseInRect(NSEvent.mouseLocation, $0.screen.frame, false) }
                ?? prepared.first
            guard let target else { return }
            // `makeKey` (not `makeKeyAndOrderFront`) keeps this a non-activating
            // overlay: it must not pull activation away from the user's app.
            if !target.window.isVisible { target.window.orderFrontRegardless() }
            if !target.window.isKeyWindow { target.window.makeKey() }
            if target.window.firstResponder !== target.view {
                target.window.makeFirstResponder(target.view)
            }
            self.activeRegionView = target.view
            OverlayDiag.log("assertKey \(OverlayDiag.describe(target.window)) \(OverlayDiag.firstResponder())")
        }
    }

    /// Last-resort Esc handling. The local monitor in `runRegion` only sees
    /// events that reach the overlay; if activation or key status failed, this
    /// app-level monitor still guarantees the user can leave the session.
    private func installEscapeFallback(token: UUID) {
        removeEscapeFallback()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.sessionToken == token, self.selectionContinuation != nil else { return event }
            guard event.keyCode == 53 else { return event }
            // A modal save panel (or any sheet) owns its own Esc semantics.
            if NSApp.modalWindow != nil { return event }
            if let window = event.window, window.isSheet { return event }
            if event.window?.firstResponder is NSTextView { return event }
            if let view = self.activeRegionView {
                if view.handleKey(event) { return nil }
                return event
            }
            // No interactive overlay view at all: tear the session down.
            OverlayDiag.log("escapeFallback: no active region view, cancelling session")
            self.finish(.success(.cancelled))
            return nil
        }
    }

    /// Forcefully ends any live session (used on quit) so no overlay or event
    /// monitor can outlive the app.
    func cancelActiveSession() {
        guard selectionContinuation != nil else { return }
        OverlayDiag.log("cancelActiveSession")
        finish(.success(.cancelled))
    }

    private func removeEscapeFallback() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    private func finish(_ result: Result<CaptureOutcome, Error>) {
        guard let continuation = selectionContinuation else { return }
        selectionContinuation = nil
        activeRegionView = nil
        sessionToken = UUID()
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor) }; clickMonitor = nil
        removeEscapeFallback()
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

/// A borderless, non-activating panel. Capture is a system-wide overlay: it must
/// be visible and accept keys without stealing activation from the app the user
/// was in. `.nonactivatingPanel` is only legal on NSPanel, so it is applied at
/// initialization via the style mask.
private final class SelectionWindow: NSPanel {
    init(screenFrame: CGRect) {
        super.init(contentRect: screenFrame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        // Panel-specific behaviour: stay visible when our app deactivates, and
        // only take key status when something actually needs keyboard input.
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isFloatingPanel = true
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        // canJoinAllSpaces + fullScreenAuxiliary make it appear on every Space and
        // over full-screen apps; canJoinAllApplications is the documented flag for
        // floating/system overlays that must appear above other applications.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications]
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Esc reaching the panel goes through the region's single cancel entry, so
    /// overlay cleanup, monitors and the session all end together.
    override func cancelOperation(_ sender: Any?) {
        (contentView as? RegionView)?.handleCancelRequest()
    }
}

private final class RegionView: NSView {
    /// The frozen desktop snapshot for this display. Window capture replaces it
    /// with the same snapshot composited with the independently captured window,
    /// so export shows the window rather than whatever was drawn over it.
    private var image: CGImage
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
    private var exited = false
    private var pendingEditDocument: CaptureDocument?
    private var previousSelection: CGRect?

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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        OverlayDiag.log("RegionView.viewDidMoveToWindow \(OverlayDiag.describe(self)) \(OverlayDiag.describe(window))")
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        OverlayDiag.log("RegionView.backingChanged scale=\(window?.backingScaleFactor ?? -1)")
    }
    private var drewOnce = false
    override func resetCursorRects() {
        OverlayDiag.log("RegionView.resetCursorRects bounds=\(NSStringFromRect(bounds))")
        addCursorRect(bounds, cursor: .crosshair)
    }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Drawing
    override func draw(_ dirtyRect: NSRect) {
        if !drewOnce {
            drewOnce = true
            OverlayDiag.log("RegionView.firstDraw bounds=\(NSStringFromRect(bounds)) dirty=\(NSStringFromRect(dirtyRect)) \(OverlayDiag.describe(self))")
        }
        guard let ctx = NSGraphicsContext.current?.cgContext else {
            OverlayDiag.log("RegionView.draw has no cgContext")
            return
        }
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
        OverlayDiag.log("RegionView.mouseDown local=\(NSStringFromPoint(point)) eventWindow=\(event.window?.title ?? "nil") isOverlay=\(event.window === window) clickCount=\(event.clickCount)")
        if let selection, let document, document.tool == nil {
            if let kind = CaptureGeometry.handleKind(at: point, selection: selection) {
                pendingEditDocument = document
                resizing = (kind, selection)
                canvas?.isHidden = true; toolbar?.isHidden = true
                needsDisplay = true
                return
            }
            if selection.contains(point) {
                if event.clickCount == 2 { performDoubleClick(); return }
                pendingEditDocument = document
                moving = (selection, point)
                toolbar?.isHidden = true
                needsDisplay = true
                return
            }
            // Clicking outside starts a fresh selection, but the current marks
            // are only discarded once the new drag produces a usable rect.
            previousSelection = selection
            start = point; current = point
            canvas?.isHidden = true; toolbar?.isHidden = true
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
            recordPendingEditIfNeeded()
            applySelection(newSelection)
            return
        }
        if let moving {
            let origin = CGPoint(x: moving.rect.minX + point.x - moving.point.x, y: moving.rect.minY + point.y - moving.point.y)
            recordPendingEditIfNeeded()
            applySelection(CaptureGeometry.moved(selection: moving.rect, to: origin, bounds: bounds))
            return
        }
        if previousSelection != nil || document == nil {
            // Drawing a brand-new selection, either from scratch or by dragging
            // outside the current one.
            current = CGPoint(x: max(0, min(bounds.width, point.x)), y: max(0, min(bounds.height, point.y)))
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        OverlayDiag.log("RegionView.mouseUp selection=\(selection.map { NSStringFromRect($0) } ?? "nil") document=\(document == nil ? "nil" : "set")")
        if document == nil, let selection {
            moving = nil; resizing = nil; pendingEditDocument = nil
            select(selection, name: "区域截图")
            return
        }
        if let previous = previousSelection {
            previousSelection = nil
            if let newSelection = selection, newSelection.width >= 4, newSelection.height >= 4 {
                select(newSelection, name: "区域截图")
            } else {
                start = previous.origin
                current = CGPoint(x: previous.maxX, y: previous.maxY)
                canvas?.isHidden = false; toolbar?.isHidden = false
                repositionToolbar()
                needsDisplay = true
            }
            return
        }
        moving = nil; resizing = nil; pendingEditDocument = nil
        canvas?.isHidden = false; toolbar?.isHidden = false
        repositionToolbar()
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) { OverlayDiag.log("RegionView.rightMouseDown"); cancelCapture() }

    /// Records the undo entry only once a drag actually starts, so a plain click
    /// inside the selection does not create a no-op undo step.
    private func recordPendingEditIfNeeded() {
        guard let pending = pendingEditDocument else { return }
        pendingEditDocument = nil
        pending.beginEdit()
    }

    private func applySelection(_ rect: CGRect) {
        start = rect.origin
        current = CGPoint(x: rect.maxX, y: rect.maxY)
        canvas?.frame = rect
        document?.selectionPixelRect = CaptureGeometry.pixelRect(rect, viewBounds: bounds, imageSize: imageSize)
        needsDisplay = true
    }

    // MARK: Selection lifecycle
    /// Starts an editing session for `rect`. When `windowImage` is supplied the
    /// independently captured window is composited into the frozen snapshot at
    /// `windowViewRect` first, so the document and every export contain the
    /// window itself.
    func select(_ rect: CGRect, name: String, windowImage: CGImage? = nil, windowViewRect: CGRect? = nil) {
        let rect = rect.standardized.intersection(bounds)
        guard !rect.isNull, rect.width >= 4, rect.height >= 4 else { resetSelection(); return }
        onPhase?(.editing)
        start = rect.origin; current = CGPoint(x: rect.maxX, y: rect.maxY)
        // Discard the previous document so its late OCR result cannot surface.
        document?.invalidate()
        documentObservation = nil
        canvas?.removeFromSuperview(); toolbar?.removeFromSuperview()
        if let windowImage, let windowViewRect {
            do {
                image = try Imaging.compositeWindow(windowImage, into: image,
                                                    viewRect: windowViewRect, viewBounds: bounds,
                                                    imageSize: imageSize)
                OverlayDiag.log("window composite applied rect=\(NSStringFromRect(windowViewRect)) "
                    + "window=\(windowImage.width)x\(windowImage.height) -> snapshot=\(image.width)x\(image.height)")
            } catch {
                OverlayDiag.log("window composite FAILED \(error)")
            }
        }
        let scale = CaptureGeometry.scale(viewBounds: bounds, imageSize: imageSize)
        let doc = CaptureDocument(fullImage: image, name: name,
                                  color: NSColor(rgb: settings.settings.annotationColor),
                                  strokeWidth: CGFloat(settings.settings.strokeWidth),
                                  fontSize: CGFloat(settings.settings.fontSize))
        doc.scale = scale
        doc.selectionPixelRect = CaptureGeometry.pixelRect(rect, viewBounds: bounds, imageSize: imageSize)
        document = doc
        let sessionDoc = doc
        documentObservation = doc.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let current = self.document, current === sessionDoc else { return }
                self.syncSelectionFromDocument()
                self.needsDisplay = true
                self.repositionToolbar()
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
        // This overlay is laid out manually, so the toolbar must NOT mix in Auto
        // Layout. `sizingOptions = []` stops NSHostingView from proposing its own
        // SwiftUI fitting size, and `CaptureLayout.toolbarFrame` remains the only
        // source of geometry. (Anchoring to the parent before `addSubview` also
        // raised "no common ancestor" at runtime.)
        if #available(macOS 13.0, *) { host.sizingOptions = [] }
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = []
        toolbar = host
        addSubview(host)
        repositionToolbar()
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    /// Keeps the overlay selection in step with the document after undo/redo of
    /// a selection adjustment, so the eight handles follow the restored rect.
    private func syncSelectionFromDocument() {
        guard let document else { return }
        let rect = CaptureGeometry.viewRect(document.selectionPixelRect, viewBounds: bounds, imageSize: imageSize)
        guard rect.width >= 1, rect.height >= 1 else { return }
        if start != rect.origin || current != CGPoint(x: rect.maxX, y: rect.maxY) {
            start = rect.origin
            current = CGPoint(x: rect.maxX, y: rect.maxY)
            canvas?.frame = rect
        }
    }

    private func resetSelection() {
        document?.invalidate()
        canvas?.removeFromSuperview(); toolbar?.removeFromSuperview()
        canvas = nil; toolbar = nil; document = nil; documentObservation = nil
        start = nil; current = nil; moving = nil; resizing = nil; pendingEditDocument = nil; previousSelection = nil
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
        // 44 (main row) + 1 (divider) + 40 (property row) when properties show.
        let preferred = CGSize(width: 900, height: showProps ? 86 : 45)
        let frame = CaptureLayout.toolbarFrame(selection: selection, screen: bounds, preferredSize: preferred)
        toolbar.frame = frame
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
                document.invalidate()
                exit(.pinned(image, name: document.name, lastRegion: makeLastRegion()))
                return
            }
            document.invalidate()
            exit(.finished(lastRegion: makeLastRegion()))
        } catch {
            committing = false
            onPhase?(.editing)
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
            // Cancelling the save panel returns to the same selection and marks.
            committing = false
            onPhase?(.editing)
            window?.makeFirstResponder(self)
            return
        }
        do {
            let image = try document.flattened()
            try CaptureExporter.writeFile(image, to: url, format: saveFormat(for: url), quality: settings.settings.jpegQuality)
            if settings.settings.copyOnSave { try CaptureExporter.writePasteboard(image) }
            lastSavedURL = url.deletingLastPathComponent()
            document.invalidate()
            exit(.finished(lastRegion: makeLastRegion()))
        } catch {
            committing = false
            onPhase?(.editing)
            document.message = error.localizedDescription
            showError(error)
        }
    }

    private func performPin() {
        canvas?.commitText()
        guard let document, !committing else { return }
        committing = true
        onPhase?(.committing)
        do {
            let image = try document.flattened()
            if settings.settings.copyOnPin { try CaptureExporter.writePasteboard(image) }
            document.invalidate()
            exit(.pinned(image, name: document.name, lastRegion: makeLastRegion()))
        } catch {
            committing = false
            onPhase?(.editing)
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

    /// Single cancel entry used by Esc, `cancelOperation`, the toolbar and the
    /// app-level fallback. Cancels an in-progress stroke or text edit first and
    /// keeps the session alive; otherwise exits the whole session.
    func handleCancelRequest() {
        if canvas?.cancelPendingStroke() == true { return }
        if canvas?.isEditingText == true {
            canvas?.abandonText()
            window?.makeFirstResponder(self)
            return
        }
        cancelCapture()
    }

    /// Single exit point. Esc while a stroke or text edit is in progress cancels
    /// that operation first and keeps the session alive; otherwise it exits.
    private func cancelCapture() {
        guard !committing, !exited else { return }
        exited = true
        canvas?.commitText()
        document?.invalidate()
        onFinish(.cancelled)
    }

    private func exit(_ outcome: CaptureOutcome) {
        guard !exited else { return }
        exited = true
        onFinish(outcome)
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
        if let window { window.orderFrontRegardless(); window.makeKey() }
    }

    func contains(_ candidate: CaptureDocument) -> Bool { document === candidate }

    // MARK: Key handling
    func handleKey(_ event: NSEvent) -> Bool {
        // Key code only: never record typed characters.
        OverlayDiag.log("RegionView.handleKey keyCode=\(event.keyCode) eventWindow=\(event.window?.title ?? "nil") overlay=\(event.window === window) document=\(document == nil ? "nil" : "set")")
        if event.keyCode == 53 { // Esc
            handleCancelRequest()
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
