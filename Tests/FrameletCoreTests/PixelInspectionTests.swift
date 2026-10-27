import Foundation
import FrameletCore

extension ImagingChecks {
    static func precisionPixelCoordinates() throws {
        let bounds = CGRect(x: -100, y: 20, width: 100, height: 80)
        let size = CGSize(width: 200, height: 160)
        try expect(PixelInspection.pixel(at: CGPoint(x: -99.5, y: 99.5), bounds: bounds, imageSize: size) == CGPoint(x: 1, y: 1), "Retina top-left pixel must be unflipped and display-relative")
        try expect(PixelInspection.pixel(at: CGPoint(x: 0, y: 20), bounds: bounds, imageSize: size) == CGPoint(x: 199, y: 159), "outer edges clamp to last actual pixel")
        let p = PixelInspection.aligned(CGPoint(x: -95.2, y: 27.3), bounds: bounds, imageSize: size)
        try expect(p == CGPoint(x: -95, y: 27.5), "Retina selection edges align to half-point boundaries")
        let rect = CGRect(x: p.x, y: p.y, width: 10.5, height: 12.5)
        let crop = CaptureGeometry.cropRect(CaptureGeometry.pixelRect(rect, viewBounds: bounds, imageSize: size), imageSize: size)
        try expect(crop.size == CGSize(width: 21, height: 25), "export must match pixel-aligned selection without growing an extra pixel")
        let one = PixelInspection.pixel(at: CGPoint(x: 9.9, y: 10.1), bounds: CGRect(x: 0, y: 0, width: 100, height: 100), imageSize: CGSize(width: 100, height: 100))
        try expect(one == CGPoint(x: 9, y: 89), "1x screen pixel mapping")
    }

    static func precisionLoupeEdges() throws {
        let imageBounds = CGRect(x: 0, y: 0, width: 200, height: 160)
        for pixel in [CGPoint.zero, CGPoint(x: 199, y: 0), CGPoint(x: 0, y: 159), CGPoint(x: 199, y: 159), CGPoint(x: 100, y: 80)] {
            let sample = PixelInspection.sampleRect(pixel: pixel)
            let clipped = sample.intersection(imageBounds)
            // This is the same top-left crop / bottom-left destination mapping
            // used by PrecisionCaptureGuide; edge padding cannot move the center.
            let destX = clipped.minX - sample.minX
            let destY = sample.maxY - clipped.maxY
            try expect(destX + pixel.x - clipped.minX == 7, "center column must remain 7 at all edges")
            try expect(destY + clipped.maxY - pixel.y - 1 == 7, "center row must remain 7, without vertical flip")
        }
        let bounds = CGRect(x: 0, y: 0, width: 1512, height: 982)
        for point in [CGPoint(x: 1, y: 1), CGPoint(x: 1511, y: 1), CGPoint(x: 1, y: 981), CGPoint(x: 1511, y: 981), CGPoint(x: 500, y: 500)] {
            let panel = PixelInspection.panelFrame(at: point, bounds: bounds, size: CGSize(width: 144, height: 176))
            try expect(bounds.contains(panel), "loupe must stay inside display")
            try expect(!panel.contains(point), "loupe must not cover the capture endpoint")
        }
    }
}
