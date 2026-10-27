import AppKit
import SwiftUI
import FrameletCore

enum CaptureSelectionOutline {
    static func path(in rect: CGRect, cornerRadius: CGFloat, pixelScale: CGFloat = 1) -> NSBezierPath {
        let radius = CaptureGeometry.selectionCornerRadius(cornerRadius, in: rect, pixelScale: pixelScale)
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}

/// Selection chrome is a sibling ABOVE the annotation canvas. Drawing this in
/// the parent would let the opaque canvas cover the border and resize handles.
final class CaptureSelectionChrome: NSView {
    var selection: CGRect? { didSet { needsDisplay = true } }
    var pixelSize: CGSize = .zero { didSet { needsDisplay = true } }
    var showHandles = true { didSet { needsDisplay = true } }
    var showLabel = true { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 16 { didSet { needsDisplay = true } }
    var pixelScale: CGFloat = 1 { didSet { needsDisplay = true } }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let selection, selection.width > 0, selection.height > 0 else { return }
        // Keep the outline inside the display even for a full-screen selection.
        let inset = min(1.5, selection.width / 4, selection.height / 4)
        let radius = CaptureGeometry.selectionCornerRadius(cornerRadius, in: selection, pixelScale: pixelScale)
        let border = CaptureSelectionOutline.path(in: selection.insetBy(dx: inset, dy: inset), cornerRadius: max(0, radius - inset), pixelScale: pixelScale)
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
        guard showLabel else { return }
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

/// Floating controls beside the selection dimensions, kept separate from the
/// screenshot pixels so the slider can never appear in exported images.
struct CaptureCornerControls: View {
    @ObservedObject var document: CaptureDocument
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        HStack(spacing: 7) {
            Text("\(document.pixelWidth) × \(document.pixelHeight)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .fixedSize()
            Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: 14)
            Image(systemName: "rectangle.roundedcorner").font(.system(size: 11))
            Slider(value: Binding(get: { document.cornerRadius }, set: { value in
                document.cornerRadius = value
                settings.settings.selectionCornerRadius = Double(value)
            }), in: 0...32, step: 1)
            .frame(width: 80).accessibilityLabel("截图圆角大小")
            .help("向左调整为直角，向右调整圆角；PNG 和复制保留透明角")
            Text(document.cornerRadius == 0 ? "直角" : "\(Int(document.cornerRadius))")
                .font(.system(size: 10, design: .monospaced)).frame(width: 24, alignment: .trailing)
        }
        .padding(.horizontal, 8).frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white).tint(.white)
        .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 6))
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
