import AppKit
import SwiftUI
import FrameletCore
import Combine

struct ImageCanvas: NSViewRepresentable {
    @ObservedObject var document: ImageDocument
    func makeNSView(context: Context) -> CanvasView { CanvasView(document: document) }
    func updateNSView(_ nsView: CanvasView, context: Context) { nsView.needsDisplay = true }
}

final class CanvasView: NSView, NSTextFieldDelegate {
    let document: ImageDocument
    private var pending: Mark?
    var drawingEnabled = true
    private let padding: CGFloat
    private let inlineText: Bool
    private var textField: NSTextField?
    private var textPosition: CGPoint?
    private var observation: AnyCancellable?
    private var fitted: CGRect { Imaging.fittedRect(image: CGSize(width: document.original.width, height: document.original.height), bounds: bounds.insetBy(dx: padding, dy: padding)) }
    init(document: ImageDocument, padding: CGFloat = 32, inlineText: Bool = false) {
        self.document = document; self.padding = padding; self.inlineText = inlineText
        super.init(frame: .zero)
        observation = document.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(fitted, cursor: drawingEnabled ? .crosshair : .openHand) }
    override func hitTest(_ point: NSPoint) -> NSView? { drawingEnabled ? super.hitTest(point) : nil }
    override func draw(_ dirtyRect: NSRect) {
        if !inlineText {
        NSColor(calibratedWhite: 0.92, alpha: 1).setFill(); bounds.fill()
        let checker: CGFloat = 12
        NSColor(calibratedWhite: 0.89, alpha: 1).setFill()
        for x in stride(from: CGFloat(0), to: bounds.width, by: checker) {
            for y in stride(from: CGFloat(0), to: bounds.height, by: checker) where (Int(x/checker)+Int(y/checker))%2 == 0 {
                NSRect(x: x, y: y, width: checker, height: checker).fill()
            }
        }
        }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = fitted
        ctx.saveGState(); defer { ctx.restoreGState() }
        if !inlineText { ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 18, color: NSColor.black.withAlphaComponent(0.16).cgColor) }
        let marks = document.marks + (pending.map { [$0] } ?? [])
        let output = marks.isEmpty ? document.original : ((try? Imaging.render(document.original, marks: marks)) ?? document.original)
        ctx.draw(output, in: r)
    }
    private func point(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil), r = fitted
        return CGPoint(x: min(max(0, (local.x-r.minX)/r.width), 1)*CGFloat(document.original.width),
                       y: min(max(0, (local.y-r.minY)/r.height), 1)*CGFloat(document.original.height))
    }
    override func mouseDown(with event: NSEvent) {
        guard fitted.contains(convert(event.locationInWindow, from: nil)) else { return }
        window?.makeFirstResponder(self)
        let p = point(event)
        if document.tool == .text {
            if inlineText { beginText(at: p, viewPoint: convert(event.locationInWindow, from: nil)); return }
            let alert = NSAlert(); alert.messageText = "添加文字"; alert.addButton(withTitle: "添加"); alert.addButton(withTitle: "取消")
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 30))
            field.placeholderString = "输入标注文字"; alert.accessoryView = field
            alert.window.initialFirstResponder = field
            if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                document.append(Mark(tool: .text, points: [p], color: document.color, width: document.strokeWidth, text: field.stringValue))
            }
        } else {
            pending = Mark(tool: document.tool, points: [p, p], color: document.color, width: document.strokeWidth)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard var mark = pending else { return }
        if mark.tool == .pen { mark.points.append(point(event)) } else { mark.points[mark.points.count-1] = point(event) }
        pending = mark; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let mark = pending else { return }
        pending = nil
        if let first = mark.points.first, let last = mark.points.last, hypot(last.x-first.x, last.y-first.y) > 2 {
            document.append(mark)
        }
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { pending = nil; needsDisplay = true } else { super.keyDown(with: event) }
    }
    private func beginText(at point: CGPoint, viewPoint: CGPoint) {
        commitText()
        let width = min(260, max(80, bounds.width-viewPoint.x))
        let field = NSTextField(frame: CGRect(x: min(viewPoint.x, max(0,bounds.width-width)), y: max(0,viewPoint.y-8), width: width, height: 32))
        field.placeholderString = "输入文字，按回车确认"
        field.font = .systemFont(ofSize: 16,weight: .semibold)
        field.textColor = document.color; field.delegate = self
        field.backgroundColor = .white; field.isBezeled = true
        textPosition = point; textField = field
        addSubview(field); window?.makeFirstResponder(field)
    }
    func commitText() {
        guard let field = textField else { return }
        let value = field.stringValue
        let point = textPosition
        textField = nil; textPosition = nil
        field.delegate = nil; field.removeFromSuperview()
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let point {
            document.append(Mark(tool: .text,points: [point],color: document.color,width: document.strokeWidth,text: value))
        }
        needsDisplay = true
    }
    func controlTextDidEndEditing(_ notification: Notification) { commitText() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            textField?.stringValue = ""; commitText(); window?.makeFirstResponder(self); return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitText(); window?.makeFirstResponder(self); return true
        }
        return false
    }
}
