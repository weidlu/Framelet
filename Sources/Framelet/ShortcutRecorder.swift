import AppKit
import SwiftUI
import FrameletCore

/// A key recorder styled like a shortcut field. Click to start recording; the
/// next key press (or Delete to clear, Esc to cancel) finishes recording.
final class ShortcutRecorderView: NSView {
    var combo: HotKeyCombo?
    var placeholder: String = "未设置"
    var onCommit: ((HotKeyCombo?) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    private var recording = false
    private var tracking: NSTrackingArea?
    private var resignObserver: NSObjectProtocol?

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
    }

    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsDisplay = true }

    override func becomeFirstResponder() -> Bool {
        recording = true
        onRecordingChanged?(true)
        observeResignKey()
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return true
    }

    /// Losing the window (clicking another app, closing settings) must always
    /// end recording so suspended global hot keys come back.
    private func observeResignKey() {
        stopObservingResignKey()
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.stopRecording()
        }
    }

    private func stopObservingResignKey() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    private func stopRecording() {
        stopObservingResignKey()
        guard recording else { needsDisplay = true; return }
        recording = false
        onRecordingChanged?(false)
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRecording() }
    }

    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        let code = event.keyCode
        let modifiers = HotKeyFormat.modifiers(from: event.modifierFlags)
        if code == 53 { // Esc: cancel, no change
            finish(nil, commit: false)
            return
        }
        if code == 51 || code == 117 { // Delete / Forward Delete: clear
            finish(nil, commit: true)
            return
        }
        if Self.isModifierKey(code) { return } // ignore bare modifier presses
        finish(HotKeyCombo(keyCode: UInt32(code), modifiers: modifiers), commit: true)
    }

    private func finish(_ value: HotKeyCombo?, commit: Bool) {
        recording = false
        onRecordingChanged?(false)
        window?.makeFirstResponder(nil)
        if commit { onCommit?(value) }
        needsDisplay = true
    }

    private static func isModifierKey(_ code: UInt16) -> Bool {
        [54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 79, 80, 81, 82].contains(code)
    }

    override func draw(_ dirtyRect: NSRect) {
        let hovering = bounds.contains(convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil))
        let background = recording ? NSColor.systemBlue.withAlphaComponent(0.14) : (hovering ? NSColor.controlAccentColor.withAlphaComponent(0.08) : NSColor(white: 0.96, alpha: 1))
        let border = recording ? NSColor.systemBlue : (hovering ? NSColor.controlAccentColor : NSColor(white: 0.80, alpha: 1))
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        background.setFill(); path.fill()
        border.setStroke(); path.lineWidth = 1; path.stroke()
        let text: String
        let color: NSColor
        if recording {
            text = "请按快捷键…（Esc 取消，Delete 清除）"; color = NSColor.systemBlue
        } else if let combo {
            text = HotKeyFormat.display(combo); color = .labelColor
        } else {
            text = placeholder; color = .secondaryLabelColor
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: color]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        attributed.draw(at: CGPoint(x: bounds.midX - size.width/2, y: bounds.midY - size.height/2))
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let combo: HotKeyCombo?
    let placeholder: String
    let onCommit: (HotKeyCombo?) -> Void
    let onRecordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.combo = combo
        view.placeholder = placeholder
        view.onCommit = onCommit
        view.onRecordingChanged = onRecordingChanged
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        nsView.combo = combo
        nsView.placeholder = placeholder
        nsView.onCommit = onCommit
        nsView.onRecordingChanged = onRecordingChanged
        nsView.needsDisplay = true
    }
}
