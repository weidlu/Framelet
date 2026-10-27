import AppKit
import SwiftUI
import ScreenCaptureKit
import FrameletCore

@main enum FrameletMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppController()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        _ = delegate
    }
}

enum SessionState: Equatable { case idle, preparing, selecting, editing, committing }

@MainActor final class AppController: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var busy = false
    @Published var permission = CGPreflightScreenCaptureAccess()
    @Published var sessionState: SessionState = .idle
    @Published var shortcutsAvailable = true
    @Published var hotKeyFailures: [CaptureAction: String] = [:]
    let settings: AppSettingsStore
    private let captureService: CaptureService
    private let keys = HotKeyRegistry()
    private var home: NSWindow?
    private var settingsWindow: NSWindow?
    private var picker: NSWindow?
    private var statusItem: NSStatusItem?
    private var editors: [EditorWindow] = []
    private var pins: [NSWindow] = []

    override init() {
        settings = AppSettingsStore()
        captureService = CaptureService(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.configure()
        OverlayDiag.start()
        DebugLog.write("launched, args=\(ProcessInfo.processInfo.arguments)")
        buildMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "拾影")
        statusItem?.menu = captureMenu()
        keys.onTrigger = { [weak self] action in self?.run(action) }
        captureService.onPhase = { [weak self] phase in
            OverlayDiag.log("onPhase \(phase)")
            switch phase {
            case .selecting: self?.sessionState = .selecting
            case .editing: self?.sessionState = .editing
            case .committing: self?.sessionState = .committing
            }
        }
        applyHotKeys()
        showHome()
        // Local verification hooks: launch straight into a screen for manual
        // acceptance runs without needing synthetic input events.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--demo") { showDemo() }
        if arguments.contains("--settings") { showSettings() }
        // Verification hook: start a capture directly so the overlay can be
        // inspected without synthetic input events.
        if let index = arguments.firstIndex(of: "--capture"), arguments.indices.contains(index + 1) {
            let mode = arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                switch mode {
                case "full": self.capture(.full)
                case "window": self.chooseWindow()
                case "synthetic": self.captureSynthetic()
                default: self.capture(.region)
                }
            }
        }
        if let index = arguments.firstIndex(of: "--settings-tab"), arguments.indices.contains(index + 1),
           let tab = Int(arguments[index + 1]) {
            showSettings(tab: tab)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showHome(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Never trap the app in a stuck capture session: tear it down and quit.
        if sessionState != .idle { captureService.cancelActiveSession() }
        if editors.contains(where: { $0.document.hasUnsavedMarks }) {
            let alert = NSAlert(); alert.messageText = "退出拾影？"; alert.informativeText = "尚未保存的标注将丢失。"
            alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "退出")
            return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
        }
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { keys.unregisterAll() }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { do { openImage(try Imaging.load(url), name: url.lastPathComponent) } catch { showError(error) } }
    }

    // MARK: Menu
    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于拾影", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(withTitle: "设置…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        appMenu.addItem(withTitle: "打开截图面板", action: #selector(showHome), keyEquivalent: "1")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏拾影", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出拾影", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)

        let captureItem = NSMenuItem(); captureItem.title = "截图"
        let captureSubmenu = NSMenu(title: "截图")
        captureSubmenu.addItem(withTitle: "区域截图", action: #selector(regionAction), keyEquivalent: "")
        captureSubmenu.addItem(withTitle: "全屏截图", action: #selector(fullAction), keyEquivalent: "")
        captureSubmenu.addItem(withTitle: "窗口截图…", action: #selector(windowAction), keyEquivalent: "")
        captureSubmenu.addItem(withTitle: "上次区域截图", action: #selector(lastRegionAction), keyEquivalent: "")
        captureItem.submenu = captureSubmenu; main.addItem(captureItem)

        let file = NSMenuItem(); file.title = "文件"; let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(withTitle: "打开图片…", action: #selector(importImage), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "保存图片…", action: #selector(saveCurrent), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        file.submenu = fileMenu; main.addItem(file)

        let edit = NSMenuItem(); edit.title = "编辑"; let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销标注", action: #selector(undoCurrent), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做标注", action: #selector(redoCurrent), keyEquivalent: "z"); redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(copyCurrent), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu; main.addItem(edit)
        NSApp.mainMenu = main
        refreshCaptureMenuItems()
    }

    private func refreshCaptureMenuItems() {
        guard let submenu = NSApp.mainMenu?.items.first(where: { $0.title == "截图" })?.submenu else { return }
        let titles: [(CaptureAction, String)] = [(.region, "区域截图"), (.fullscreen, "全屏截图"), (.window, "窗口截图…"), (.lastRegion, "上次区域截图")]
        for (index, (action, title)) in titles.enumerated() {
            guard index < submenu.items.count else { continue }
            let item = submenu.items[index]
            item.title = shortcutSuffix(action).map { "\(title)  \($0)" } ?? title
        }
        statusItem?.menu = captureMenu()
    }

    private func shortcutSuffix(_ action: CaptureAction) -> String? {
        guard let combo = settings.settings.globalShortcuts[action] ?? nil else { return nil }
        return HotKeyFormat.display(combo)
    }

    private func captureMenu() -> NSMenu {
        let menu = NSMenu()
        let entries: [(String, Selector)] = [
            (menuTitle("区域截图", .region), #selector(regionAction)),
            (menuTitle("全屏截图", .fullscreen), #selector(fullAction)),
            (menuTitle("窗口截图", .window), #selector(windowAction)),
            (menuTitle("上次区域截图", .lastRegion), #selector(lastRegionAction)),
        ]
        for (title, action) in entries {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(showSettingsWindow), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "打开拾影", action: #selector(showHome), keyEquivalent: "").target = self
        let quit = menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        return menu
    }

    private func menuTitle(_ title: String, _ action: CaptureAction) -> String {
        shortcutSuffix(action).map { "\(title)  \($0)" } ?? title
    }

    // MARK: Hot keys
    private func applyHotKeys() {
        let failures = keys.registerAll(settings.settings.globalShortcuts)
        hotKeyFailures = failures
        shortcutsAvailable = failures.isEmpty
        refreshCaptureMenuItems()
    }

    func rebindHotKey(_ action: CaptureAction, to combo: HotKeyCombo?) {
        do {
            if let combo {
                try keys.rebind(action: action, to: combo)
                settings.settings.globalShortcuts[action] = combo
            } else {
                keys.clear(action: action)
                settings.settings.globalShortcuts[action] = nil
            }
            hotKeyFailures = [:]
        } catch {
            showShortcutError(action: action, error: error)
        }
        shortcutsAvailable = keysAvailable
        refreshCaptureMenuItems()
    }

    private var keysAvailable: Bool {
        hotKeyFailures.isEmpty
    }

    private func showShortcutError(action: CaptureAction, error: Error) {
        let alert = NSAlert()
        alert.messageText = "无法设置「\(action.title)」的快捷键"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }

    func setRecording(_ recording: Bool) {
        if recording {
            // Suspend global capture triggers while a recorder captures keys.
            keys.registerAll([:])
        } else {
            applyHotKeys()
        }
    }

    func restoreDefaultGlobalShortcuts() {
        settings.settings.globalShortcuts = AppSettings.defaultGlobalShortcuts
        applyHotKeys()
    }

    func restoreDefaultToolShortcuts() {
        settings.settings.toolShortcuts = AppSettings.defaultToolShortcuts
    }

    // MARK: Capture routing
    private func run(_ action: CaptureAction) {
        switch action {
        case .region: capture(.region)
        case .fullscreen: capture(.full)
        case .window: chooseWindow()
        case .lastRegion: captureLastRegion()
        }
    }

    enum Mode { case region, full }

    @objc private func regionAction() { capture(.region) }
    @objc private func fullAction() { capture(.full) }
    @objc private func windowAction() { chooseWindow() }
    @objc private func lastRegionAction() { captureLastRegion() }

    func capture(_ mode: Mode) {
        guard sessionState == .idle else { return }
        startCapture { try await self.captureService.region(selectFullScreen: mode == .full) }
    }

    /// Local acceptance path that reuses the production overlay without needing
    /// screen-recording permission.
    private func captureSynthetic() {
        guard sessionState == .idle else { return }
        guard let image = SyntheticSnapshot.make() else { return }
        startCapture { try await self.captureService.syntheticCapture(image: image) }
    }

    private func captureLastRegion() {
        guard sessionState == .idle else { return }
        guard let last = settings.settings.lastRegion else {
            let alert = NSAlert(); alert.messageText = "没有可用的上次区域"
            alert.informativeText = "请先完成一次区域截图，之后才能使用「上次区域截图」。"
            alert.addButton(withTitle: "知道了"); alert.runModal()
            return
        }
        startCapture { try await self.captureService.lastRegionCapture(last) }
    }

    private func startCapture(hiding windowsToHide: [NSWindow]? = nil, _ operation: @escaping () async throws -> CaptureOutcome) {
        OverlayDiag.log("startCapture state=\(sessionState) frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nil")")
        sessionState = .preparing
        busy = true
        let previousFrontmost = NSWorkspace.shared.frontmostApplication
        // Only hide the launch UI. Settings and image windows are legitimate
        // screenshot subjects and must remain visible in the frozen snapshot.
        let visible = (windowsToHide ?? [home, picker].compactMap { $0 }).filter { $0.isVisible }
        visible.forEach { $0.orderOut(nil) }
        Task {
            defer { sessionState = .idle; busy = false; permission = CGPreflightScreenCaptureAccess() }
            do {
                DebugLog.write("startCapture: sleeping")
                try await Task.sleep(nanoseconds: 200_000_000)
                sessionState = .selecting
                let outcome = try await operation()
                DebugLog.write("startCapture: outcome \(outcome)")
                handleCapture(outcome, restoring: visible, previousFrontmost: previousFrontmost)
            } catch {
                DebugLog.write("startCapture error: \(error)")
                restoreAfterSession(visible: visible, previousFrontmost: previousFrontmost)
                showError(error)
            }
        }
    }

    private func handleCapture(_ outcome: CaptureOutcome, restoring visible: [NSWindow], previousFrontmost: NSRunningApplication?) {
        switch outcome {
        case .cancelled:
            restoreAfterSession(visible: visible, previousFrontmost: previousFrontmost)
        case .finished(let lastRegion):
            if let lastRegion { settings.settings.lastRegion = lastRegion }
            restoreAfterSession(visible: visible, previousFrontmost: previousFrontmost)
        case .pinned(let image, let name, let lastRegion):
            if let lastRegion { settings.settings.lastRegion = lastRegion }
            pin(image, name: name)
            restoreAfterSession(visible: visible, previousFrontmost: previousFrontmost)
        }
    }

    /// Restores the pre-capture window visibility and frontmost app. Windows that
    /// were visible before the capture come back in the same state; a capture
    /// never forces the workbench open, and focus returns to the app the user was
    /// using before.
    private func restoreAfterSession(visible: [NSWindow], previousFrontmost: NSRunningApplication?) {
        visible.forEach { $0.orderFront(nil) }
        let selfPID = ProcessInfo.processInfo.processIdentifier
        if let app = previousFrontmost, app.processIdentifier == selfPID {
            NSApp.activate(ignoringOtherApps: true)
        } else if let app = previousFrontmost, !app.isTerminated {
            app.activate()
        }
    }

    // MARK: Window / picker
    func chooseWindow() {
        guard sessionState == .idle else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let windows = try await captureService.windows()
                let window = makeWindow(title: "选择要截图的窗口", size: CGSize(width: 580, height: 500))
                window.contentView = NSHostingView(rootView: WindowPicker(windows: windows) { [weak self] selected in
                    self?.picker?.orderOut(nil); self?.captureWindow(selected)
                })
                picker = window; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            } catch { showError(error) }
        }
    }

    private func captureWindow(_ window: SCWindow) {
        guard sessionState == .idle else { return }
        let launchWindows = [home, picker].compactMap { $0 }.filter { $0.windowNumber != Int(window.windowID) }
        startCapture(hiding: launchWindows) { try await self.captureService.region(window: window) }
    }

    // MARK: Home / settings / pin / image
    @objc func showHome() {
        guard sessionState == .idle else { return }
        if home == nil {
            let window = makeWindow(title: "拾影 · Framelet", size: CGSize(width: 380, height: 420))
            window.styleMask.remove(.resizable)
            window.contentView = NSHostingView(rootView: HomeView(controller: self, settings: settings))
            home = window
        }
        home?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettingsWindow() { showSettings(tab: 0) }

    @objc func showSettings() { showSettings(tab: 0) }

    func showSettings(tab: Int) {
        permission = CGPreflightScreenCaptureAccess()
        let window = settingsWindow ?? makeWindow(title: "拾影设置", size: CGSize(width: 800, height: 620))
        window.minSize = CGSize(width: 760, height: 560)
        window.contentView = NSHostingView(rootView: SettingsView(controller: self, settings: settings, keys: keys, initialTab: tab))
        settingsWindow = window
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    func openPermissionSettings() {
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func importImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .tiff]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { openImage(try Imaging.load(url), name: url.lastPathComponent) } catch { showError(error) }
    }

    func openImage(_ image: CGImage, name: String) {
        let editor = EditorWindow(document: ImageDocument(image: image, name: name), controller: self)
        editor.onClose = { [weak self, weak editor] in self?.editors.removeAll { $0 === editor } }
        editors.append(editor); editor.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    func pin(_ document: ImageDocument) {
        do { pin(try document.flattened(), name: document.name) } catch { showError(error) }
    }

    func pin(_ image: CGImage, name: String) {
        let width = min(640, CGFloat(image.width) / 2)
        let height = min(500, CGFloat(image.height) / 2)
        let window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: max(120, width), height: max(120, height)),
                             styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        window.title = "贴图 · \(name)"; window.level = .floating; window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = NSImageView(); view.image = NSImage(cgImage: image, size: .zero); view.imageScaling = .scaleProportionallyUpOrDown
        window.contentView = view; window.center(); window.makeKeyAndOrderFront(nil)
        pins.removeAll { !$0.isVisible }; pins.append(window)
    }

    private var currentDocument: ImageDocument? { (NSApp.keyWindow as? EditorWindow)?.document }
    @objc private func saveCurrent() { currentDocument?.save() }
    @objc private func undoCurrent() {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.undo() }
        else { currentDocument?.undo() }
    }
    @objc private func redoCurrent() {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.undoManager?.redo() }
        else { currentDocument?.redo() }
    }
    @objc private func copyCurrent() {
        if NSApp.keyWindow?.firstResponder is NSTextView { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) }
        else { currentDocument?.copy() }
    }
    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "拾影 · Framelet", .applicationVersion: "0.3.0", .credits: NSAttributedString(string: "截图，留住重点。\n本地处理 · 无账号 · 无付费墙")])
    }

    func showError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "未能完成操作"; alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "知道了")
        if !CGPreflightScreenCaptureAccess() { alert.addButton(withTitle: "打开权限设置") }
        if alert.runModal() == .alertSecondButtonReturn { openPermissionSettings() }
    }

    private func makeWindow(title: String, size: CGSize) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false; window.center()
        return window
    }

    func showDemo() {
        guard let image = DemoImage.make() else { return }
        openImage(image, name: "示例画布")
    }
}

@MainActor final class EditorWindow: NSWindow, NSWindowDelegate {
    let document: ImageDocument
    var onClose: (() -> Void)?
    init(document: ImageDocument, controller: AppController) {
        self.document = document
        super.init(contentRect: CGRect(x: 0, y: 0, width: 1120, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        title = "\(document.name) · 拾影"; minSize = CGSize(width: 1060, height: 600)
        isReleasedWhenClosed = false; delegate = self; center()
        contentView = NSHostingView(rootView: EditorView(document: document, controller: controller))
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard document.hasUnsavedMarks else { return true }
        let alert = NSAlert(); alert.messageText = "关闭这张图片？"; alert.informativeText = "尚未保存的标注将丢失。"
        alert.addButton(withTitle: "保存…"); alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "不保存")
        switch alert.runModal() {
        case .alertFirstButtonReturn: document.save(); return !document.hasUnsavedMarks
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
    func windowWillClose(_ notification: Notification) { onClose?() }
}
