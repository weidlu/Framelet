import Foundation
import CoreGraphics

public enum ScrollAppendResult: Equatable {
    case appended(Int)
    case unchanged
    case rejected(String)
}

/// Confine an instance to one actor. Images stay at their original resolution;
/// only alignment signatures are reduced horizontally. Never invent a seam.
public final class ScrollStitcher {
    private var previous: CGImage
    private var signature: ScrollSignature
    private var strips: [CGImage] = []
    private var footer: CGImage?
    private var top = 0, bottom = 0
    private var started = false
    public private(set) var addedFrames = 0
    public private(set) var height: Int
    public var width: Int { previous.width }
    private let maxPixels = 40_000_000
    private let maxHeight = 30_000

    public init(first: CGImage) throws {
        guard first.width >= 32, first.height >= 100, first.width * first.height <= maxPixels else { throw ImagingError.invalidImage }
        previous = first; signature = try ScrollSignature(first); height = first.height
    }

    public func append(_ image: CGImage) throws -> ScrollAppendResult {
        guard image.width == width, image.height == previous.height else { return .rejected("窗口尺寸改变，请重新开始长截图。") }
        let next = try ScrollSignature(image)
        if signature.distance(to: next) < 0.35 { return .unchanged }
        var candidateTop = top, candidateBottom = bottom
        if !started {
            // Stationary edge bands (fixed header/footer) appear only once.
            candidateTop = signature.stationaryEdge(with: next, fromTop: true)
            candidateBottom = signature.stationaryEdge(with: next, fromTop: false)
        }
        let bodyHeight = image.height - candidateTop - candidateBottom
        guard bodyHeight >= 64 else { return .rejected("可滚动内容太小，请避开固定页头后重新框选。") }
        let maxShift = bodyHeight * 3 / 4
        var scores: [Int: Double] = [:]
        func score(_ shift: Int) -> Double {
            if let value = scores[shift] { return value }
            let value = signature.alignmentError(next, shift: shift, top: candidateTop, bottom: candidateBottom)
            scores[shift] = value; return value
        }
        // Probe every integer displacement. Skipping shifts is unsafe for
        // single-pixel patterns: nearby shifts need not have similar scores.
        for shift in -maxShift...maxShift where shift != 0 {
            scores[shift] = signature.alignmentError(next, shift: shift, top: candidateTop, bottom: candidateBottom, probe: true)
        }
        let coarse = scores.sorted { $0.value < $1.value }.prefix(10).map(\.key)
        scores.removeAll(keepingCapacity: true)
        for center in coarse {
            for shift in max(-maxShift, center - 3)...min(maxShift, center + 3) where shift != 0 { _ = score(shift) }
        }
        guard let best = scores.min(by: { $0.value < $1.value }), best.value < 4.0 else {
            return .rejected("暂时跟不上滚动，请减速；若预览没有增长，请向上回到已截末尾附近。")
        }
        guard best.key > 0 else { return .rejected("检测到向上滚动，已保留结果。请回到末尾继续向下。") }
        let rival = scores.filter { abs($0.key - best.key) > 3 }.map(\.value).min() ?? 255
        guard rival - best.value > max(0.18, best.value * 0.25) else {
            return .rejected("重复或空白内容无法确定接缝，暂未追加；请继续缓慢向下滚动。")
        }
        let shift = best.key
        guard Self.validatesPixels(previous, image, shift: shift, top: candidateTop, bottom: candidateBottom) else {
            return .rejected("版式相似但内容不匹配，暂未追加；请回到已截末尾附近再向下滚动。")
        }
        guard height + shift <= maxHeight, width * (height + shift) <= maxPixels else {
            return .rejected("已到长截图大小上限，请完成当前截图后分段截取。")
        }
        guard let strip = Self.detachedCrop(image, rect: CGRect(x: 0, y: image.height - candidateBottom - shift, width: width, height: shift)) else { throw ImagingError.render }
        if !started {
            top = candidateTop; bottom = candidateBottom
            guard let first = Self.detachedCrop(previous, rect: CGRect(x: 0, y: 0, width: width, height: previous.height - bottom)) else { throw ImagingError.render }
            strips = [first]; started = true
        }
        strips.append(strip)
        footer = bottom > 0 ? Self.detachedCrop(image, rect: CGRect(x: 0, y: image.height - bottom, width: width, height: bottom)) : nil
        previous = image; signature = next; height += shift; addedFrames += 1
        return .appended(shift)
    }

    private static func validatesPixels(_ previous: CGImage, _ next: CGImage, shift: Int, top: Int, bottom: Int) -> Bool {
        // Signatures find a candidate, but repeated paragraphs can look almost
        // identical after averaging. Validate actual pixels before committing.
        // Ignore only a narrow scrollbar edge; retain the left content gutter.
        let width = previous.width - 18
        let height = previous.height - top - bottom - shift
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return false }
        func raster(_ image: CGImage, y: Int) -> CGContext? {
            guard let crop = image.cropping(to: CGRect(x: 2, y: y, width: width, height: height)),
                  let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
            ctx.interpolationQuality = .none
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height)); return ctx
        }
        guard let a = raster(previous, y: top + shift), let b = raster(next, y: top),
              let ap = a.data?.assumingMemoryBound(to: UInt8.self), let bp = b.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        var mismatches = 0, firstBadRow = height, lastBadRow = -1, groups = 0
        for y in 0..<height {
            var rowMismatch = 0
            for x in 0..<width {
                let i = (y * width + x) * 4
                if abs(Int(ap[i]) - Int(bp[i])) > 16 || abs(Int(ap[i + 1]) - Int(bp[i + 1])) > 16 || abs(Int(ap[i + 2]) - Int(bp[i + 2])) > 16 { rowMismatch += 1 }
            }
            mismatches += rowMismatch
            if rowMismatch > max(2, width / 500) {
                if lastBadRow < 0 || y - lastBadRow > 24 { groups += 1 }
                firstBadRow = min(firstBadRow, y); lastBadRow = y
            }
            if mismatches > width * height / 50 { return false }
        }
        if mismatches <= max(12, width * height / 5000) { return true }
        // A single localized cursor/animation patch is tolerable. Differences
        // spread over multiple text rows, or a whole gutter, are not a seam.
        return groups <= 1 && lastBadRow - firstBadRow < min(128, height / 4) && mismatches < width * height / 100
    }

    private static func detachedCrop(_ image: CGImage, rect: CGRect) -> CGImage? {
        // CGImage.cropping may retain the whole backing screenshot. Copy each
        // added strip so memory is bounded by the output, not frames × screen.
        guard let crop = image.cropping(to: rect),
              let ctx = CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        return ctx.makeImage()
    }

    public func image(previewWidth: Int? = nil) throws -> CGImage {
        guard started else { return previous }
        if let previewWidth {
            // Composite at native resolution first. Scaling individual thin
            // strips introduces fractional seams and blurred bands. Resize the
            // finished raster once, at the preview's actual backing resolution.
            let full = try image()
            let scale = min(1, Double(previewWidth) / Double(width))
            let w = max(1, Int((Double(width) * scale).rounded()))
            let h = max(1, Int((Double(height) * scale).rounded()))
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: full.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ImagingError.render }
            ctx.interpolationQuality = .high
            ctx.draw(full, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let result = ctx.makeImage() else { throw ImagingError.render }; return result
        }
        let w = width, h = height
        guard let space = previous.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ImagingError.render }
        ctx.interpolationQuality = .none
        var offset = 0
        for part in strips + (footer.map { [$0] } ?? []) {
            let y0 = CGFloat(h) * CGFloat(height - offset - part.height) / CGFloat(height)
            let y1 = CGFloat(h) * CGFloat(height - offset) / CGFloat(height)
            ctx.draw(part, in: CGRect(x: 0, y: y0, width: CGFloat(w), height: y1 - y0)); offset += part.height
        }
        guard let result = ctx.makeImage() else { throw ImagingError.render }; return result
    }
}

/// Compact RGB scanlines, inset horizontally to ignore scrollbars and shadows.
public struct ScrollSignature {
    private let rows: [UInt8]
    private let height: Int
    private static let columns = 48
    public init(_ image: CGImage) throws {
        height = image.height
        let inset = max(2, min(20, image.width / 20))
        guard let cropped = image.cropping(to: CGRect(x: inset, y: 0, width: image.width - inset * 2, height: image.height)),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Self.columns, height: height, bitsPerComponent: 8, bytesPerRow: Self.columns * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { throw ImagingError.render }
        ctx.interpolationQuality = .low
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: Self.columns, height: height))
        guard let data = ctx.data else { throw ImagingError.render }
        rows = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: Self.columns * height * 4))
    }
    private func rowError(_ y: Int, _ other: ScrollSignature, _ otherY: Int, columnStep: Int = 1) -> Double {
        var sum = 0
        for x in stride(from: 0, to: Self.columns, by: columnStep) {
            let a = (y * Self.columns + x) * 4, b = (otherY * Self.columns + x) * 4
            for c in 0..<3 { sum += abs(Int(rows[a + c]) - Int(other.rows[b + c])) }
        }
        return Double(sum) / Double((Self.columns / columnStep) * 3)
    }
    public func distance(to other: ScrollSignature) -> Double {
        guard height == other.height else { return 255 }
        var sum = 0.0, count = 0
        for y in stride(from: 0, to: height, by: max(1, height / 120)) {
            sum += rowError(y, other, y); count += 1
        }
        return sum / Double(count)
    }
    fileprivate func stationaryEdge(with other: ScrollSignature, fromTop: Bool) -> Int {
        var count = 0
        for offset in 0..<(height / 5) {
            let y = fromTop ? offset : height - offset - 1
            if rowError(y, other, y) > 0.6 { break }
            count += 1
        }
        return count
    }
    fileprivate func alignmentError(_ other: ScrollSignature, shift: Int, top: Int, bottom: Int, probe: Bool = false) -> Double {
        let start = top + max(0, -shift)
        let end = height - bottom - max(0, shift)
        guard end > start else { return 255 }
        var sum = 0.0, count = 0
        for y in stride(from: start, to: end, by: max(1, (end - start) / (probe ? 32 : 100))) {
            sum += rowError(y + shift, other, y, columnStep: probe ? 4 : 1); count += 1
        }
        return sum / Double(count)
    }
}
