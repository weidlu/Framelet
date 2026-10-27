import AppKit
import ImageIO
import FrameletCore

extension ImagingChecks {
    static func keyboardPixelEditing() throws {
        let rect = CGRect(x: 20, y: 30, width: 40, height: 50), size = CGSize(width: 100, height: 100)
        let moved = PrecisionEditing.nudge(rect, dx: 1, dy: -1, resize: false, imageSize: size)
        try expect(moved == CGRect(x: 21, y: 29, width: 40, height: 50), "arrows are original image pixels, not Retina points")
        let resized = PrecisionEditing.nudge(rect, dx: -100, dy: 100, resize: true, imageSize: size)
        try expect(resized == CGRect(x: 20, y: 79, width: 1, height: 1), "resize stops at one pixel and preserves top-left")
        let edge = PrecisionEditing.nudge(rect, dx: 500, dy: -500, resize: false, imageSize: size)
        try expect(edge == CGRect(x: 60, y: 0, width: 40, height: 50), "movement stays on image")
        let view = CaptureGeometry.viewRect(resized, viewBounds: CGRect(x: 0, y: 0, width: 50, height: 50), imageSize: size)
        try expect(view.size == CGSize(width: 0.5, height: 0.5), "one pixel on Retina is half a point")
    }
    static func pixelColorSampling() throws {
        let ctx = try unwrap(Imaging.context(width: 10, height: 10))
        ctx.setFillColor(NSColor.red.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 5))
        ctx.setFillColor(NSColor.blue.cgColor); ctx.fill(CGRect(x: 0, y: 5, width: 10, height: 5))
        let image = try unwrap(ctx.makeImage())
        let top = try unwrap(SampledColor.read(image, pixel: CGPoint(x: 2, y: 2)))
        try expect(top.hex == "#0000FF" && top.rgb == "rgb(0, 0, 255)", "top-left sampling with explicit sRGB conversion")
        try expect(SampledColor.read(image, pixel: CGPoint(x: 2, y: 8))?.hex == "#FF0000", "bottom stays bottom")
        try expect(SampledColor.read(image, pixel: CGPoint(x: 10, y: 0)) == nil, "out-of-range sampling rejected")
    }

    static func scrollFixture() throws -> CGImage {
        let ctx = try unwrap(Imaging.context(width: 120, height: 1400))
        var seed: UInt64 = 91731
        for y in 0..<1400 {
            for x in stride(from: 0, to: 120, by: 10) {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let v = CGFloat((seed >> 32) & 255) / 255
                ctx.setFillColor(NSColor(srgbRed: v, green: 1 - v, blue: v * 0.4, alpha: 1).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: 10, height: 1))
            }
        }
        return try unwrap(ctx.makeImage())
    }
    static func scrollViewport(_ source: CGImage, offset: Int, body: Int = 284) throws -> CGImage {
        let ctx = try unwrap(Imaging.context(width: 120, height: body + 36))
        ctx.setFillColor(NSColor.blue.cgColor); ctx.fill(CGRect(x: 0, y: body + 16, width: 120, height: 20))
        ctx.setFillColor(NSColor.red.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 16))
        ctx.draw(try unwrap(source.cropping(to: CGRect(x: 0, y: offset, width: 120, height: body))), in: CGRect(x: 0, y: 16, width: 120, height: body))
        return try unwrap(ctx.makeImage())
    }
    static func scrollStitchContinuity() throws {
        let source = try scrollFixture()
        let first = try scrollViewport(source, offset: 0)
        let stitcher = try ScrollStitcher(first: first)
        try expect(try stitcher.append(first) == .unchanged, "stationary frames must not duplicate")
        for offset in [120, 240, 410] {
            let result = try stitcher.append(scrollViewport(source, offset: offset))
            guard case .appended = result else { throw Failure(description: "could not match exact overlap at \(offset): \(result)") }
        }
        let result = try stitcher.image()
        let expected = try scrollViewport(source, offset: 0, body: 284 + 410)
        try expect(result.height == 730, "all added rows retained, fixed header/footer only once")
        try expect(try ScrollSignature(result).distance(to: ScrollSignature(expected)) < 0.01, "composed image must be continuous and oriented correctly")
        guard case .rejected = try stitcher.append(scrollViewport(source, offset: 240)) else { throw Failure(description: "upward scroll must not append old rows") }
        try expect(stitcher.height == 730, "rejected frames leave result unchanged")
    }
    static func scrollPixelFidelity() throws {
        let source = try scrollFixture()
        let stitcher = try ScrollStitcher(first: scrollViewport(source, offset: 0))
        for offset in stride(from: 8, through: 800, by: 8) {
            guard case .appended(8) = try stitcher.append(scrollViewport(source, offset: offset)) else {
                throw Failure(description: "thin 8px strips must align at \(offset)")
            }
        }
        let full = try stitcher.image(), expected = try scrollViewport(source, offset: 0, body: 1084)
        func bytes(_ image: CGImage) throws -> [UInt8] {
            let ctx = try unwrap(Imaging.context(width: image.width, height: image.height))
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return Array(UnsafeBufferPointer(start: try unwrap(ctx.data).assumingMemoryBound(to: UInt8.self), count: ctx.bytesPerRow * ctx.height))
        }
        let pixels = try bytes(expected)
        try expect(try bytes(full) == pixels, "native output must preserve every pixel across 100 thin seams")
        let board = NSPasteboard(name: .init("com.framelet.checks.long-pixels.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        try Imaging.writePasteboard(full, to: board)
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            let data = try unwrap(board.data(forType: type))
            let src = try unwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let decoded = try unwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
            try expect(decoded.width == full.width && decoded.height == full.height, "clipboard must not downsample")
            try expect(try bytes(decoded) == pixels, "PNG and TIFF must preserve pixels, not export the preview")
        }
        let preview = try stitcher.image(previewWidth: 60)
        try expect(preview.width == 60 && preview.height == 560, "preview follows width without a shrinking height cap")
    }

    static func scrollRejectsRepeatedParagraphs() throws {
        func fixture(_ name: String) throws -> CGImage {
            let url = try unwrap(Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Fixtures"))
            let source = try unwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            return try unwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        }
        // Real browser frames from our local numbered fixture. Repeated layout
        // falsely matched a backwards jump as +1100px before pixel validation.
        let a = try fixture("regression-a"), b = try fixture("regression-b")
        let stitcher = try ScrollStitcher(first: a)
        guard case .rejected = try stitcher.append(b) else { throw Failure(description: "repeated paragraphs must not invent a positive seam on a backwards jump") }
        try expect(stitcher.height == a.height, "bad frame must preserve accepted output")
        // The same real content still matches a legitimate 200px forward step.
        let first = try unwrap(b.cropping(to: CGRect(x: 0, y: 0, width: b.width, height: 1200)))
        let next = try unwrap(b.cropping(to: CGRect(x: 0, y: 200, width: b.width, height: 1200)))
        let valid = try ScrollStitcher(first: first)
        try expect(try valid.append(next) == .appended(200), "real text overlap remains accepted")
    }

    static func scrollRejectsAmbiguity() throws {
        let source = try scrollFixture()
        let stitcher = try ScrollStitcher(first: scrollViewport(source, offset: 0))
        guard case .rejected = try stitcher.append(scrollViewport(source, offset: 900)) else { throw Failure(description: "no overlap must not silently stitch") }
        let ctx = try unwrap(Imaging.context(width: 120, height: 320))
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 320))
        let blank = try unwrap(ctx.makeImage())
        let plain = try ScrollStitcher(first: blank)
        try expect(try plain.append(blank) == .unchanged, "blank content cannot invent scroll distance")
        try expect(plain.height == 320, "no duplicate blank pages")
        let pattern = try unwrap(Imaging.context(width: 120, height: 1000))
        for y in 0..<1000 {
            pattern.setFillColor((y % 16 < 8 ? NSColor.black : NSColor.white).cgColor)
            pattern.fill(CGRect(x: 0, y: y, width: 120, height: 1))
        }
        let repeating = try unwrap(pattern.makeImage())
        let repeated = try ScrollStitcher(first: unwrap(repeating.cropping(to: CGRect(x: 0, y: 0, width: 120, height: 320))))
        guard case .rejected = try repeated.append(unwrap(repeating.cropping(to: CGRect(x: 0, y: 3, width: 120, height: 320)))) else {
            throw Failure(description: "repeating stripes have multiple equally valid seams and must be rejected")
        }
    }
}
