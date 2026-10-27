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

@MainActor final class AppController: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var busy = false
    @Published var permission = CGPreflightScreenCaptureAccess()
    @Published var shortcutsAvailable = true
    private let captureService = CaptureService()
    private let keys = HotKeys()
    private var home: NSWindow?
    private var settings: NSWindow?
    private var picker: NSWindow?
    private var statusItem: NSStatusItem?
    private var editors: [EditorWindow] = []
    private var pins: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "拾影")
        statusItem?.menu = captureMenu()
        keys.onTrigger = { [weak self] id in self?.capture(id == 1 ? .region : .full) }
        shortcutsAvailable = keys.register()
        showHome()
        if ProcessInfo.processInfo.arguments.contains("--demo") { showDemo() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showHome(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if editors.contains(where: { $0.document.hasUnsavedMarks }) {
            let alert = NSAlert(); alert.messageText = "退出拾影？"; alert.informativeText = "尚未保存的标注将丢失。"
            alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "退出")
            return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
        }
        return .terminateNow
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { do { openImage(try Imaging.load(url), name: url.lastPathComponent) } catch { showError(error) } }
    }
    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于拾影", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(withTitle: "打开工作台", action: #selector(showHome), keyEquivalent: "1")
        appMenu.addItem(withTitle: "权限与快捷键…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏拾影", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出拾影", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
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
    }
    private func captureMenu() -> NSMenu {
        let menu = NSMenu()
        let entries: [(String, Selector)] = [("区域截图  ⌃⌥4", #selector(regionAction)), ("全屏截图  ⌃⌥3", #selector(fullAction)), ("窗口截图…", #selector(windowAction)), ("打开图片…", #selector(importImage))]
        for (title, action) in entries { let item = menu.addItem(withTitle: title, action: action, keyEquivalent: ""); item.target = self }
        menu.addItem(.separator())
        let item = menu.addItem(withTitle: "打开拾影", action: #selector(showHome), keyEquivalent: ""); item.target = self
        let quit = menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); quit.target = NSApp
        return menu
    }
    @objc func showHome() {
        guard !busy else { return }
        if home == nil {
            let window = makeWindow(title: "拾影 · Framelet", size: CGSize(width: 960, height: 660))
            window.minSize = CGSize(width: 900, height: 640)
            window.contentView = NSHostingView(rootView: HomeView(controller: self))
            home = window
        }
        home?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func showSettings() {
        permission = CGPreflightScreenCaptureAccess()
        if settings == nil {
            let window = makeWindow(title: "权限与快捷键", size: CGSize(width: 520, height: 440))
            window.contentView = NSHostingView(rootView: SettingsView(controller: self)); settings = window
        }
        settings?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func openPermissionSettings() {
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
    @objc func importImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .tiff]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { openImage(try Imaging.load(url), name: url.lastPathComponent) } catch { showError(error) }
    }
    @objc private func regionAction() { capture(.region) }
    @objc private func fullAction() { capture(.full) }
    @objc private func windowAction() { chooseWindow() }
    enum Mode { case region, full }
    func capture(_ mode: Mode) {
        guard !busy else { return }
        busy = true
        let visible = NSApp.windows.filter { $0.isVisible && !pins.contains($0) }
        visible.forEach { $0.orderOut(nil) }
        Task {
            defer { busy = false; permission = CGPreflightScreenCaptureAccess() }
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                let outcome = try await captureService.region(selectFullScreen: mode == .full)
                handleCapture(outcome,restoring:visible)
            } catch { visible.forEach { $0.orderFront(nil) }; showError(error) }
        }
    }
    func chooseWindow() {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false; permission = CGPreflightScreenCaptureAccess() }
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
        guard !busy else { return }; busy = true
        let visible = NSApp.windows.filter { $0.isVisible && !pins.contains($0) }
        visible.forEach { $0.orderOut(nil) }
        Task {
            defer { busy = false }
            do { handleCapture(try await captureService.region(window:window),restoring:visible) }
            catch { visible.forEach { $0.orderFront(nil) }; showError(error) }
        }
    }
    private func handleCapture(_ outcome: CaptureOutcome, restoring visible: [NSWindow]) {
        switch outcome {
        case .cancelled: visible.forEach { $0.orderFront(nil) }
        case .finished: break
        case .pinned(let document): pin(document)
        }
    }
    func openImage(_ image: CGImage, name: String) {
        let editor = EditorWindow(document: ImageDocument(image: image, name: name), controller: self)
        editor.onClose = { [weak self, weak editor] in self?.editors.removeAll { $0 === editor } }
        editors.append(editor); editor.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func pin(_ document: ImageDocument) {
        do {
            let image = try document.flattened()
            let window = NSPanel(contentRect: CGRect(x: 0, y: 0, width: min(640,CGFloat(image.width)/2), height: min(500,CGFloat(image.height)/2)),
                                 styleMask: [.titled,.closable,.resizable,.utilityWindow], backing: .buffered, defer: false)
            window.title = "贴图 · \(document.name)"; window.level = .floating; window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = NSImageView(); view.image = NSImage(cgImage: image, size: .zero); view.imageScaling = .scaleProportionallyUpOrDown
            window.contentView = view; window.center(); window.makeKeyAndOrderFront(nil)
            pins.removeAll { !$0.isVisible }; pins.append(window)
        } catch { showError(error) }
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
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "拾影 · Framelet", .applicationVersion: "0.2.0", .credits: NSAttributedString(string: "截图，留住重点。\n本地处理 · 无账号 · 无付费墙")])
    }
    func showError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "未能完成操作"; alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "知道了")
        if !CGPreflightScreenCaptureAccess() { alert.addButton(withTitle: "打开权限设置") }
        if alert.runModal() == .alertSecondButtonReturn { openPermissionSettings() }
    }
    private func makeWindow(title: String, size: CGSize) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false; window.center()
        window.appearance = NSAppearance(named: .aqua)
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
        super.init(contentRect: CGRect(x: 0, y: 0, width: 1120, height: 780), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        title = "\(document.name) · 拾影"; minSize = CGSize(width: 1060, height: 600)
        isReleasedWhenClosed = false; delegate = self; appearance = NSAppearance(named: .aqua); center()
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
