import AppKit
import SwiftUI

@MainActor final class CaptureCountdown: ObservableObject {
    @Published var remaining = 0
    private var panel: CountdownPanel?
    private var timer: Timer?
    private var continuation: CheckedContinuation<Bool, Never>?

    func wait(seconds: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            remaining = seconds
            let panel = CountdownPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 108), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.onCancel = { [weak self] in self?.cancel() }
            panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
            panel.level = .floating; panel.backgroundColor = .clear; panel.isOpaque = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: CountdownView(model: self))
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
                panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - 120, y: screen.visibleFrame.maxY - 140))
            }
            self.panel = panel; panel.orderFrontRegardless(); panel.makeKey()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.continuation != nil else { return }
                    self.remaining -= 1
                    if self.remaining <= 0 { self.finish(true) }
                }
            }
        }
    }
    func cancel() { finish(false) }
    private func finish(_ capture: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil); panel?.contentView = nil; panel = nil
        continuation.resume(returning: capture)
    }
}

private final class CountdownPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
private struct CountdownView: View {
    @ObservedObject var model: CaptureCountdown
    var body: some View {
        VStack(spacing: 9) {
            Text("\(model.remaining) 秒后开始截图").font(.system(size: 18, weight: .semibold, design: .rounded))
            Button("取消倒计时") { model.cancel() }.keyboardShortcut(.cancelAction)
        }.frame(width: 240, height: 108).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
