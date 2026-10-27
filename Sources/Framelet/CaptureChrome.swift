import AppKit
import FrameletCore

/// Selection chrome is a sibling ABOVE the annotation canvas. Drawing this in
/// the parent would let the opaque canvas cover the border and resize handles.
final class CaptureSelectionChrome: NSView {
    var selection: CGRect? { didSet { needsDisplay = true } }
    var pixelSize: CGSize = .zero { didSet { needsDisplay = true } }
    var showHandles = true { didSet { needsDisplay = true } }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let selection, selection.width > 0, selection.height > 0 else { return }
        // Keep the outline inside the display even for a full-screen selection.
        let border = NSBezierPath(rect: selection.insetBy(dx: 1.5, dy: 1.5))
        NSColor.black.withAlphaComponent(0.7).setStroke()
        border.lineWidth = 4; border.stroke()
        NSColor.white.setStroke()
        border.lineWidth = 1.5; border.stroke()
        if showHandles {
            for point in CaptureGeometry.resizeHandles(for: selection) {
                let center = CaptureInteraction.clamped(point, to: bounds.insetBy(dx: 5, dy: 5))
                let handle = NSBezierPath(roundedRect: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8), xRadius: 1, yRadius: 1)
                NSColor.white.setFill(); handle.fill()
                NSColor.systemBlue.setStroke(); handle.lineWidth = 1.5; handle.stroke()
            }
        }
        let label = NSAttributedString(string: "\(Int(pixelSize.width.rounded())) × \(Int(pixelSize.height.rounded()))", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white
        ])
        let size = label.size()
        let x = min(max(10, selection.minX + 6), max(10, bounds.maxX - size.width - 18))
        let proposedY = selection.maxY + 10
        let y = proposedY + size.height + 8 <= bounds.maxY ? proposedY : max(10, selection.maxY - size.height - 12)
        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: CGRect(x: x - 6, y: y - 4, width: size.width + 12, height: size.height + 8), xRadius: 5, yRadius: 5).fill()
        label.draw(at: CGPoint(x: x, y: y))
    }
}

extension CapturePointer {
    var cursor: NSCursor {
        switch self {
        case .arrow: return .arrow
        case .crosshair: return .crosshair
        case .text: return .iBeam
        case .openHand: return .openHand
        case .closedHand: return .closedHand
        case .resize(let kind):
            if #available(macOS 15.0, *) {
                let position: NSCursor.FrameResizePosition
                switch kind {
                case .bottomLeftCorner: position = .bottomLeft
                case .bottomRightCorner: position = .bottomRight
                case .topLeftCorner: position = .topLeft
                case .topRightCorner: position = .topRight
                case .bottomEdge: position = .bottom
                case .topEdge: position = .top
                case .leftEdge: position = .left
                case .rightEdge: position = .right
                }
                return NSCursor.frameResize(position: position, directions: .all)
            }
            switch kind {
            case .bottomEdge, .topEdge: return .resizeUpDown
            default: return .resizeLeftRight
            }
        }
    }
}
