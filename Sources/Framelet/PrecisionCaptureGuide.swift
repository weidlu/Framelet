import AppKit
import FrameletCore

/// Decorative only: never intercepts selection, toolbar or editor events.
/// Samples the original image, so dimming, guides and annotations cannot feed
/// back into the loupe. No screen capture or full-image render on mouse motion.
final class PrecisionCaptureGuide: NSView {
    let image: CGImage
    var point: CGPoint? { didSet { needsDisplay = true } }
    var candidate: CGRect? { didSet { needsDisplay = true } }
    var message: String? { didSet { needsDisplay = true } }
    var dragging = false { didSet { needsDisplay = true } }
    init(image: CGImage) { self.image = image; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let point, bounds.insetBy(dx: -0.01, dy: -0.01).contains(point), let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setShouldAntialias(false)
        // A hover target is only a thin outline. Never brighten/dim its area or
        // present editing handles before the user actually chooses it.
        if let candidate, !dragging {
            ctx.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(candidate.insetBy(dx: 0.5, dy: 0.5))
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: bounds.minX, y: point.y)); path.addLine(to: CGPoint(x: bounds.maxX, y: point.y))
        path.move(to: CGPoint(x: point.x, y: bounds.minY)); path.addLine(to: CGPoint(x: point.x, y: bounds.maxY))
        ctx.addPath(path); ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.65).cgColor)
        ctx.setLineWidth(1.5); ctx.strokePath()
        ctx.addPath(path); ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(0.5); ctx.strokePath()

        let panel = PixelInspection.panelFrame(at: point, bounds: bounds, size: CGSize(width: 184, height: 224))
        ctx.setShouldAntialias(true)
        NSColor(calibratedWhite: 0.09, alpha: 0.97).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 8, yRadius: 8).fill()
        let pixel = PixelInspection.pixel(at: point, bounds: bounds, imageSize: CGSize(width: image.width, height: image.height))
        let sample = PixelInspection.sampleRect(pixel: pixel)
        let clipped = sample.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let cell: CGFloat = 8
        let grid = CGRect(x: panel.midX - 60, y: panel.maxY - 132, width: 120, height: 120)
        NSColor(calibratedWhite: 0.25, alpha: 1).setFill(); grid.fill()
        if let crop = image.cropping(to: clipped) {
            let destination = CGRect(x: grid.minX + (clipped.minX - sample.minX) * cell,
                                     y: grid.minY + (sample.maxY - clipped.maxY) * cell,
                                     width: clipped.width * cell, height: clipped.height * cell)
            ctx.interpolationQuality = .none
            ctx.draw(crop, in: destination)
        }
        ctx.setShouldAntialias(false)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.22).cgColor)
        ctx.setLineWidth(0.5)
        for i in 0...15 {
            let offset = CGFloat(i) * cell
            ctx.move(to: CGPoint(x: grid.minX + offset, y: grid.minY)); ctx.addLine(to: CGPoint(x: grid.minX + offset, y: grid.maxY))
            ctx.move(to: CGPoint(x: grid.minX, y: grid.minY + offset)); ctx.addLine(to: CGPoint(x: grid.maxX, y: grid.minY + offset))
        }
        ctx.strokePath()
        let center = CGRect(x: grid.minX + 7 * cell, y: grid.minY + 7 * cell, width: cell, height: cell)
        ctx.setStrokeColor(NSColor.black.cgColor); ctx.setLineWidth(3); ctx.stroke(center)
        ctx.setStrokeColor(NSColor.systemYellow.cgColor); ctx.setLineWidth(1); ctx.stroke(center)
        ctx.setShouldAntialias(true)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]
        ("X \(Int(pixel.x))  Y \(Int(pixel.y))" as NSString).draw(at: CGPoint(x: panel.minX + 12, y: panel.minY + 71), withAttributes: attrs)
        if let color = SampledColor.read(image, pixel: pixel) {
            (color.hex + "  " + "\(color.red),\(color.green),\(color.blue)" as NSString).draw(at: CGPoint(x: panel.minX + 12, y: panel.minY + 54), withAttributes: attrs)
        }
        ((message ?? "G 复制 HEX · R 复制 RGB") as NSString).draw(at: CGPoint(x: panel.minX + 12, y: panel.minY + 39), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.systemYellow])
        ("方向键微调 · 空格设起点" as NSString).draw(at: CGPoint(x: panel.minX + 12, y: panel.minY + 23), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.white])
        let hint = dragging ? "松开选定 · Esc 取消" : "单击选窗 · 拖动框选"
        (hint as NSString).draw(at: CGPoint(x: panel.minX + 12, y: panel.minY + 7), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor(white: 0.75, alpha: 1)])
    }
}
