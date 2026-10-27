import Foundation
import CoreGraphics

public enum PrecisionEditing {
    /// Delta follows AppKit axes; resize changes right/bottom edges so keyboard
    /// directions match their visible motion. Geometry is always image pixels.
    public static func nudge(_ rect: CGRect, dx: Int, dy: Int, resize: Bool, imageSize: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: imageSize)
        if resize {
            let right = min(bounds.maxX, max(rect.minX + 1, rect.maxX + CGFloat(dx)))
            let bottom = min(rect.maxY - 1, max(0, rect.minY + CGFloat(dy)))
            return CGRect(x: rect.minX, y: bottom, width: right - rect.minX, height: rect.maxY - bottom)
        }
        return CaptureGeometry.moved(selection: rect, to: CGPoint(x: rect.minX + CGFloat(dx), y: rect.minY + CGFloat(dy)), bounds: bounds)
    }
}

public struct SampledColor: Equatable {
    public let red: UInt8, green: UInt8, blue: UInt8
    public var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    public var rgb: String { "rgb(\(red), \(green), \(blue))" }
    public static func read(_ image: CGImage, pixel: CGPoint) -> SampledColor? {
        guard pixel.x >= 0, pixel.y >= 0, pixel.x < CGFloat(image.width), pixel.y < CGFloat(image.height),
              let crop = image.cropping(to: CGRect(x: floor(pixel.x), y: floor(pixel.y), width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1)); return true
        }
        return ok ? SampledColor(red: bytes[0], green: bytes[1], blue: bytes[2]) : nil
    }
}
