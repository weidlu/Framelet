import Foundation

/// Uses screenshot pixels, not logical display points. Image indices are
/// top-left based; AppKit points are bottom-left based.
public enum PixelInspection {
    public static func pixel(at point: CGPoint, bounds: CGRect, imageSize: CGSize) -> CGPoint {
        let x = floor((point.x - bounds.minX) * imageSize.width / max(1, bounds.width))
        let y = floor((bounds.maxY - point.y) * imageSize.height / max(1, bounds.height))
        return CGPoint(x: min(max(0, x), max(0, imageSize.width - 1)),
                       y: min(max(0, y), max(0, imageSize.height - 1)))
    }

    public static func aligned(_ point: CGPoint, bounds: CGRect, imageSize: CGSize) -> CGPoint {
        let sx = imageSize.width / max(1, bounds.width)
        let sy = imageSize.height / max(1, bounds.height)
        return CGPoint(x: bounds.minX + min(max(0, ((point.x - bounds.minX) * sx).rounded()), imageSize.width) / max(sx, 0.001),
                       y: bounds.minY + min(max(0, ((point.y - bounds.minY) * sy).rounded()), imageSize.height) / max(sy, 0.001))
    }

    /// Unclipped odd-sized sample: outside-image cells remain empty so the
    /// pointer's pixel stays in the center even at the edge of a display.
    public static func sampleRect(pixel: CGPoint, radius: Int = 7) -> CGRect {
        CGRect(x: pixel.x - CGFloat(radius), y: pixel.y - CGFloat(radius),
               width: CGFloat(radius * 2 + 1), height: CGFloat(radius * 2 + 1))
    }

    public static func panelFrame(at point: CGPoint, bounds: CGRect, size: CGSize) -> CGRect {
        let gap: CGFloat = 24
        var x = point.x + gap
        var y = point.y - gap - size.height
        if x + size.width > bounds.maxX - 8 { x = point.x - gap - size.width }
        if y < bounds.minY + 8 { y = point.y + gap }
        x = min(max(bounds.minX + 8, x), max(bounds.minX + 8, bounds.maxX - size.width - 8))
        y = min(max(bounds.minY + 8, y), max(bounds.minY + 8, bounds.maxY - size.height - 8))
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
