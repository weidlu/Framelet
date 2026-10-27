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
    public var fontSize: CGFloat
    public var text: String
    public init(tool: MarkTool, points: [CGPoint], color: NSColor = .systemRed, width: CGFloat = 5, fontSize: CGFloat = 0, text: String = "") {
        self.tool = tool; self.points = points; self.color = color; self.width = width; self.fontSize = fontSize; self.text = text
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
        draw(mark, on: ctx, base: base, offset: .zero, clip: CGRect(x: 0, y: 0, width: base.width, height: base.height))
    }

    /// Renders the full screenshot cropped to `selectionPixelRect` (bottom-left
    /// image pixel coordinates). Marks live in full-image coordinates; they are
    /// composited before cropping to integral device-pixel boundaries. Marks
    /// outside the selection are cropped away without resampling its pixels.
    public static func renderCropped(_ image: CGImage, marks: [Mark], selectionPixelRect: CGRect) throws -> CGImage {
        let selection = selectionPixelRect.standardized
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !selection.isNull, selection.width >= 1, selection.height >= 1 else { throw ImagingError.render }
        let crop = CaptureGeometry.cropRect(selection, imageSize: CGSize(width: image.width, height: image.height))
        // Render in fixed full-image coordinates, then take the actual device
        // pixels. Never squeeze an integral crop into fractional dimensions:
        // doing so resamples screenshot text every time the selection moves.
        let composite = marks.isEmpty ? image : try render(image, marks: marks)
        guard let output = composite.cropping(to: crop) else { throw ImagingError.render }
        return output
    }

    /// Composites an independently captured window image into a frozen desktop
    /// snapshot at `viewRect` (view points, local to `viewBounds`). Window
    /// captures are occlusion-independent, so this is what makes a window shot
    /// show the window itself rather than whatever desktop pixels were on top.
    /// The window image is drawn into the exact pixel rect of the window frame,
    /// so export matches the selection without a second scaling path.
    public static func compositeWindow(_ windowImage: CGImage, into base: CGImage,
                                       viewRect: CGRect, viewBounds: CGRect,
                                       imageSize: CGSize) throws -> CGImage {
        guard base.width > 0, base.height > 0 else { throw ImagingError.render }
        let pixel = CaptureGeometry.pixelRect(viewRect, viewBounds: viewBounds, imageSize: imageSize)
        let visible = pixel.intersection(CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height))
        guard !visible.isNull, visible.width >= 1, visible.height >= 1 else { throw ImagingError.render }
        guard let ctx = context(width: base.width, height: base.height) else { throw ImagingError.render }
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        // Marks/pixels use a bottom-left origin; CGContext.draw is already
        // bottom-left, so only the rect needs to be expressed in that space.
        ctx.interpolationQuality = .high
        ctx.draw(windowImage, in: pixel)
        guard let output = ctx.makeImage() else { throw ImagingError.render }
        return output
    }

    /// Writes the final image to a pasteboard. Both PNG and TIFF are provided so
    /// native targets can paste reliably. Encoding happens before
    /// `clearContents()`, so a failure can never empty the user's clipboard.
    public static func writePasteboard(_ image: CGImage, to pasteboard: NSPasteboard) throws {
        let png = try data(image, type: .png)
        guard let tiff = NSImage(cgImage: image, size: .zero).tiffRepresentation else { throw ImagingError.export }
        pasteboard.clearContents()
        guard pasteboard.setData(png, forType: .png) else { throw ImagingError.export }
        pasteboard.setData(tiff, forType: .tiff)
    }

    private static func draw(_ mark: Mark, on ctx: CGContext, base: CGImage, offset: CGPoint, clip: CGRect) {
        guard let first = mark.points.first, let last = mark.points.last else { return }
        let p1 = CGPoint(x: first.x - offset.x, y: first.y - offset.y)
        let p2 = CGPoint(x: last.x - offset.x, y: last.y - offset.y)
        ctx.saveGState(); defer { ctx.restoreGState() }
        ctx.clip(to: clip)
        ctx.setStrokeColor(mark.color.cgColor); ctx.setFillColor(mark.color.cgColor)
        ctx.setLineWidth(mark.width); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        let rect = CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p1.x - p2.x), height: abs(p1.y - p2.y))
        switch mark.tool {
        case .rectangle: ctx.stroke(rect)
        case .ellipse: ctx.strokeEllipse(in: rect)
        case .arrow:
            ctx.move(to: p1); ctx.addLine(to: p2); ctx.strokePath()
            let angle = atan2(p2.y-p1.y, p2.x-p1.x), length = max(18, mark.width*4)
            let a = CGPoint(x: p2.x-length*cos(angle - .pi/6), y: p2.y-length*sin(angle - .pi/6))
            let b = CGPoint(x: p2.x-length*cos(angle + .pi/6), y: p2.y-length*sin(angle + .pi/6))
            ctx.move(to: a); ctx.addLine(to: p2); ctx.addLine(to: b); ctx.strokePath()
        case .pen:
            let translated = mark.points.map { CGPoint(x: $0.x - offset.x, y: $0.y - offset.y) }
            ctx.addLines(between: translated); ctx.strokePath()
        case .redact:
            ctx.setBlendMode(.copy); ctx.setFillColor(NSColor.black.cgColor); ctx.fill(rect.integral)
        case .pixelate:
            let clamped = rect.integral.intersection(clip)
            guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else { return }
            let crop = CGRect(x: clamped.minX, y: CGFloat(base.height)-clamped.maxY, width: clamped.width, height: clamped.height)
            guard let piece = base.cropping(to: crop),
                  let small = context(width: max(1, Int(clamped.width/16)), height: max(1, Int(clamped.height/16))) else { return }
            small.interpolationQuality = .low
            small.draw(piece, in: CGRect(x: 0, y: 0, width: small.width, height: small.height))
            guard let pixels = small.makeImage() else { return }
            ctx.interpolationQuality = .none; ctx.draw(pixels, in: clamped)
        case .text:
            let size = mark.fontSize > 0 ? mark.fontSize : max(20, mark.width*5)
            let font = NSFont.systemFont(ofSize: size, weight: .semibold)
            let value = NSAttributedString(string: mark.text, attributes: [.font: font, .foregroundColor: mark.color])
            let line = CTLineCreateWithAttributedString(value)
            ctx.textMatrix = .identity; ctx.textPosition = p1; CTLineDraw(line, ctx)
        }
    }

    public static func data(_ image: CGImage, type: UTType = .png, quality: Double = 0.92) throws -> Data {
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, type.identifier as CFString, 1, nil) else { throw ImagingError.export }
        let toEncode: CGImage
        if type == .jpeg && image.alphaInfo != .none && image.alphaInfo != .noneSkipLast && image.alphaInfo != .noneSkipFirst {
            guard let ctx = context(width: image.width, height: image.height) else { throw ImagingError.export }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let flattened = ctx.makeImage() else { throw ImagingError.export }
            toEncode = flattened
        } else {
            toEncode = image
        }
        CGImageDestinationAddImage(destination, toEncode, type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary : nil)
        guard CGImageDestinationFinalize(destination) else { throw ImagingError.export }
        return bytes as Data
    }
}
