import Foundation
import CoreGraphics

/// Pure geometry for the in-place capture overlay. Coordinates follow the
/// conventions already used by the app:
/// - View space: AppKit points, bottom-left origin (a screen `NSScreen.frame`).
/// - Image space: full screenshot pixels, bottom-left origin (matching the
///   marks drawn by `Imaging`). Conversion to CGImage top-left happens only at
///   crop time.
public enum CaptureGeometry {
    /// Uniform scale factor from view points to full-image pixels.
    public static func scale(viewBounds: CGRect, imageSize: CGSize) -> CGFloat {
        guard viewBounds.width > 0, imageSize.width > 0 else { return 1 }
        return imageSize.width / viewBounds.width
    }

    /// Maps a view-points rect to full-image pixel rect (bottom-left origin).
    public static func pixelRect(_ rect: CGRect, viewBounds: CGRect, imageSize: CGSize) -> CGRect {
        guard viewBounds.width > 0, viewBounds.height > 0 else { return .zero }
        let sx = imageSize.width / viewBounds.width
        let sy = imageSize.height / viewBounds.height
        return CGRect(x: rect.minX * sx, y: rect.minY * sy, width: rect.width * sx, height: rect.height * sy)
    }

    /// CGImage top-left-origin crop rect for a bottom-left-origin image rect.
    public static func cropRect(_ pixelRect: CGRect, imageSize: CGSize) -> CGRect {
        let rect = pixelRect.standardized.intersection(CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height))
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return .zero }
        return CGRect(x: rect.minX, y: imageSize.height - rect.maxY, width: rect.width, height: rect.height).integral
    }

    public enum HandleKind: Int, CaseIterable {
        case bottomLeftCorner = 0, bottomRightCorner, topLeftCorner, topRightCorner
        case bottomEdge, topEdge, leftEdge, rightEdge
        public var isEdge: Bool { rawValue >= 4 }
    }

    /// The eight resize handles for a selection rect: four corners and four
    /// edge midpoints.
    public static func resizeHandles(for selection: CGRect) -> [CGPoint] {
        let minX = selection.minX, maxX = selection.maxX
        let minY = selection.minY, maxY = selection.maxY
        let midX = selection.midX, midY = selection.midY
        return [
            CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY),
            CGPoint(x: minX, y: maxY), CGPoint(x: maxX, y: maxY),
            CGPoint(x: midX, y: minY), CGPoint(x: midX, y: maxY),
            CGPoint(x: minX, y: midY), CGPoint(x: maxX, y: midY),
        ]
    }

    /// Which handle (if any) is under `point`.
    public static func handleKind(at point: CGPoint, selection: CGRect, hitRadius: CGFloat = 9) -> HandleKind? {
        for (index, handle) in resizeHandles(for: selection).enumerated() {
            if hypot(point.x - handle.x, point.y - handle.y) <= hitRadius {
                return HandleKind(rawValue: index)
            }
        }
        return nil
    }

    /// Resizes `selection` by dragging the given handle to `point`, clamped to
    /// `bounds`. Edge handles change one edge; corner handles move two edges.
    /// Returns nil when the result would be degenerate.
    public static func resized(selection: CGRect, kind: HandleKind, to point: CGPoint, bounds: CGRect, minimum: CGFloat = 8) -> CGRect? {
        let p = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
        var minX = selection.minX, maxX = selection.maxX, minY = selection.minY, maxY = selection.maxY
        switch kind {
        case .bottomLeftCorner: minX = min(p.x, maxX - minimum); minY = min(p.y, maxY - minimum)
        case .bottomRightCorner: maxX = max(p.x, minX + minimum); minY = min(p.y, maxY - minimum)
        case .topLeftCorner: minX = min(p.x, maxX - minimum); maxY = max(p.y, minY + minimum)
        case .topRightCorner: maxX = max(p.x, minX + minimum); maxY = max(p.y, minY + minimum)
        case .bottomEdge: minY = min(p.y, maxY - minimum)
        case .topEdge: maxY = max(p.y, minY + minimum)
        case .leftEdge: minX = min(p.x, maxX - minimum)
        case .rightEdge: maxX = max(p.x, minX + minimum)
        }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return (rect.width >= minimum && rect.height >= minimum) ? rect : nil
    }

    /// Moves `selection` so its origin lands at `origin`, clamped to `bounds`.
    public static func moved(selection: CGRect, to origin: CGPoint, bounds: CGRect) -> CGRect {
        let x = min(max(origin.x, bounds.minX), bounds.maxX - selection.width)
        let y = min(max(origin.y, bounds.minY), bounds.maxY - selection.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: selection.size)
    }
}
