import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

public enum MarkTool: String, CaseIterable, Identifiable {
    case arrow, rectangle, ellipse, pen, text, pixelate, redact
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .arrow: return "箭头"
        case .rectangle: return "方框"
        case .ellipse: return "圆圈"
        case .pen: return "画笔"
        case .text: return "文字"
        case .pixelate: return "马赛克"
        case .redact: return "遮挡"
        }
    }
    public var symbol: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .pixelate: return "square.grid.3x3.fill"
        case .redact: return "rectangle.fill"
        }
    }
}

public struct Mark {
    public var tool: MarkTool
    public var points: [CGPoint]
    public var color: NSColor
    public var width: CGFloat
    public var text: String
    public init(tool: MarkTool, points: [CGPoint], color: NSColor = .systemRed, width: CGFloat = 5, text: String = "") {
        self.tool = tool; self.points = points; self.color = color; self.width = width; self.text = text
    }
    public var rect: CGRect {
        guard let first = points.first, let last = points.last else { return .zero }
        return CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(last.x-first.x), height: abs(last.y-first.y))
    }
}

public enum ImagingError: LocalizedError {
    case render, invalidImage, export
    public var errorDescription: String? {
        switch self {
        case .render: return "无法生成图像，请尝试缩小截图范围。"
        case .invalidImage: return "无法读取这张图片，请选择 PNG、JPEG 或 TIFF 图片。"
        case .export: return "图片未能写入，请检查文件夹权限和可用空间。"
        }
    }
}

public enum Imaging {
    public static func fittedRect(image: CGSize, bounds: CGRect) -> CGRect {
        guard image.width > 0, image.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / image.width, bounds.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: bounds.midX-size.width/2, y: bounds.midY-size.height/2, width: size.width, height: size.height)
    }

    /// AppKit selections use a bottom-left origin; CGImage cropping uses top-left pixel coordinates.
    public static func cropRect(selection: CGRect, screenSize: CGSize, imageSize: CGSize) -> CGRect {
        guard screenSize.width > 0, screenSize.height > 0 else { return .zero }
        let selected = selection.standardized.intersection(CGRect(origin: .zero, size: screenSize))
        guard !selected.isNull, selected.width > 0, selected.height > 0 else { return .zero }
        let sx = imageSize.width / screenSize.width, sy = imageSize.height / screenSize.height
        return CGRect(x: selected.minX*sx, y: (screenSize.height-selected.maxY)*sy, width: selected.width*sx, height: selected.height*sy)
            .integral.intersection(CGRect(origin: .zero, size: imageSize))
    }

    public static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = props[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue * height.doubleValue <= 100_000_000,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw ImagingError.invalidImage }
        // ImageIO does not rotate raw pixels using EXIF automatically. Normalize through NSImage.
        if let orientation = props[kCGImagePropertyOrientation] as? Int, orientation != 1 {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width.intValue, height.intValue)]
            guard let normalized = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ImagingError.invalidImage }
            return normalized
        }
        return image
    }

    public static func context(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0, Double(width)*Double(height) <= 100_000_000 else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    public static func render(_ image: CGImage, marks: [Mark]) throws -> CGImage {
        guard let ctx = context(width: image.width, height: image.height) else { throw ImagingError.render }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // Pixelation samples the current composite, so a later mosaic cannot reveal an earlier redaction.
        for mark in marks {
            let source = mark.tool == .pixelate ? (ctx.makeImage() ?? image) : image
            draw(mark, on: ctx, base: source)
        }
        guard let output = ctx.makeImage() else { throw ImagingError.render }
        return output
    }

    public static func draw(_ mark: Mark, on ctx: CGContext, base: CGImage) {
        guard let first = mark.points.first, let last = mark.points.last else { return }
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.setStrokeColor(mark.color.cgColor); ctx.setFillColor(mark.color.cgColor)
        ctx.setLineWidth(mark.width); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        let rect = mark.rect
        switch mark.tool {
        case .rectangle: ctx.stroke(rect)
        case .ellipse: ctx.strokeEllipse(in: rect)
        case .arrow:
            ctx.move(to: first); ctx.addLine(to: last); ctx.strokePath()
            let angle = atan2(last.y-first.y, last.x-first.x), length = max(18, mark.width*4)
            let a = CGPoint(x: last.x-length*cos(angle - .pi/6), y: last.y-length*sin(angle - .pi/6))
            let b = CGPoint(x: last.x-length*cos(angle + .pi/6), y: last.y-length*sin(angle + .pi/6))
            ctx.move(to: a); ctx.addLine(to: last); ctx.addLine(to: b); ctx.strokePath()
        case .pen:
            ctx.addLines(between: mark.points); ctx.strokePath()
        case .redact:
            ctx.setBlendMode(.copy); ctx.setFillColor(NSColor.black.cgColor); ctx.fill(rect.integral)
        case .pixelate:
            let clamped = rect.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
            guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else { return }
            let crop = CGRect(x: clamped.minX, y: CGFloat(base.height)-clamped.maxY, width: clamped.width, height: clamped.height)
            guard let piece = base.cropping(to: crop),
                  let small = context(width: max(1, Int(clamped.width/16)), height: max(1, Int(clamped.height/16))) else { return }
            small.interpolationQuality = .low
            small.draw(piece, in: CGRect(x: 0, y: 0, width: small.width, height: small.height))
            guard let pixels = small.makeImage() else { return }
            ctx.interpolationQuality = .none; ctx.draw(pixels, in: clamped)
        case .text:
            let font = NSFont.systemFont(ofSize: max(20, mark.width*5), weight: .semibold)
            let value = NSAttributedString(string: mark.text, attributes: [.font: font, .foregroundColor: mark.color])
            let line = CTLineCreateWithAttributedString(value)
            ctx.textMatrix = .identity; ctx.textPosition = first; CTLineDraw(line, ctx)
        }
    }

    public static func data(_ image: CGImage, type: UTType = .png) throws -> Data {
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, type.identifier as CFString, 1, nil) else { throw ImagingError.export }
        CGImageDestinationAddImage(destination, image, type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary : nil)
        guard CGImageDestinationFinalize(destination) else { throw ImagingError.export }
        return bytes as Data
    }
}
