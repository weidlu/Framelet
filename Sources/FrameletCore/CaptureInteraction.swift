import Foundation

/// The pointer follows the capture phase and the region under the mouse.
/// A confirmed selection never turns the rest of the desktop into a new crop.
public enum CapturePointer: Equatable {
    case arrow, crosshair, text, openHand, closedHand
    case resize(CaptureGeometry.HandleKind)
}

public enum CaptureInteraction {
    public static func pointer(at point: CGPoint, selection: CGRect?, tool: MarkTool?,
                               moving: Bool = false, resizing: CaptureGeometry.HandleKind? = nil) -> CapturePointer {
        if let resizing { return .resize(resizing) }
        if moving { return .closedHand }
        guard let selection else { return .crosshair }
        if tool == nil, let handle = CaptureGeometry.handleKind(at: point, selection: selection) {
            return .resize(handle)
        }
        guard selection.contains(point) else { return .arrow }
        guard let tool else { return .openHand }
        return tool == .text ? .text : .crosshair
    }

    public static func clamped(_ point: CGPoint, to selection: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, selection.minX), selection.maxX),
                y: min(max(point.y, selection.minY), selection.maxY))
    }
}
