import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Reproducible, resolution-independent artwork. No font or external image assets.
// Usage: swift scripts/make-icon.swift <output-directory>
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources")
let iconset = root.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func render(size: Int) throws -> Data {
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)

    // Match the optical footprint of native macOS icons, with genuine alpha outside.
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                      cornerWidth: 184, cornerHeight: 184, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -9), blur: 20, color: color(0x102F2B, alpha: 0.20))
    context.addPath(tile)
    context.setFillColor(color(0xF5F9F7))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(tile)
    context.clip()
    let background = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                colors: [color(0xE4EEEA), color(0xFEFFFE)] as CFArray,
                                locations: [0, 1])!
    context.drawLinearGradient(background, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    context.restoreGState()

    // Two interlocking crop strokes: an open frame rather than a camera or editor.
    // The shorter amber stroke is the picked corner, giving the mark its direction.
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(size <= 32 ? 76 : 68)
    context.setStrokeColor(color(0x195B52))
    context.beginPath()
    context.move(to: CGPoint(x: 320, y: 744))
    context.addLine(to: CGPoint(x: 320, y: 365))
    context.addQuadCurve(to: CGPoint(x: 365, y: 320), control: CGPoint(x: 320, y: 320))
    context.addLine(to: CGPoint(x: 744, y: 320))
    context.strokePath()

    context.setStrokeColor(color(0x288071))
    context.beginPath()
    context.move(to: CGPoint(x: 280, y: 704))
    context.addLine(to: CGPoint(x: 659, y: 704))
    context.addQuadCurve(to: CGPoint(x: 704, y: 659), control: CGPoint(x: 704, y: 704))
    context.addLine(to: CGPoint(x: 704, y: 280))
    context.strokePath()

    // Amber replaces one corner of the frame and evokes the live selection handle.
    context.setStrokeColor(color(0xED9560))
    context.beginPath()
    context.move(to: CGPoint(x: 564, y: 704))
    context.addLine(to: CGPoint(x: 659, y: 704))
    context.addQuadCurve(to: CGPoint(x: 704, y: 659), control: CGPoint(x: 704, y: 704))
    context.addLine(to: CGPoint(x: 704, y: 564))
    context.strokePath()

    guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    return data as Data
}

let sizes = [(16,"icon_16x16"), (32,"icon_16x16@2x"), (32,"icon_32x32"),
             (64,"icon_32x32@2x"), (128,"icon_128x128"), (256,"icon_128x128@2x"),
             (256,"icon_256x256"), (512,"icon_256x256@2x"),
             (512,"icon_512x512"), (1024,"icon_512x512@2x")]
for (size, name) in sizes {
    try render(size: size).write(to: iconset.appendingPathComponent(name + ".png"))
}
try render(size: 1024).write(to: root.appendingPathComponent("AppIcon.png"))
print("图标源图与全部尺寸已生成：\(root.path)")

// ICNS stores the PNG representations in length-prefixed chunks. Writing the
// container directly also works on CLT-only machines where iconutil is unavailable.
func bigEndianLength(_ value: Int) -> Data {
    var length = UInt32(value).bigEndian
    return withUnsafeBytes(of: &length) { Data($0) }
}
let representations = [
    ("icp4", "icon_16x16"), ("icp5", "icon_32x32"), ("icp6", "icon_32x32@2x"),
    ("ic07", "icon_128x128"), ("ic08", "icon_256x256"), ("ic09", "icon_512x512"),
    ("ic10", "icon_512x512@2x"), ("ic11", "icon_16x16@2x"),
    ("ic12", "icon_32x32@2x"), ("ic13", "icon_128x128@2x"), ("ic14", "icon_256x256@2x")
]
var chunks = Data()
for (type, name) in representations {
    let png = try Data(contentsOf: iconset.appendingPathComponent(name + ".png"))
    chunks.append(Data(type.utf8))
    chunks.append(bigEndianLength(png.count + 8))
    chunks.append(png)
}
var icns = Data("icns".utf8)
icns.append(bigEndianLength(chunks.count + 8))
icns.append(chunks)
try icns.write(to: root.appendingPathComponent("AppIcon.icns"))
print("应用图标已打包：\(root.appendingPathComponent("AppIcon.icns").path)")
