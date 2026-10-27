import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let set = root.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for (size, name) in [(16,"icon_16x16"),(32,"icon_16x16@2x"),(32,"icon_32x32"),(64,"icon_32x32@2x"),(128,"icon_128x128"),(256,"icon_128x128@2x"),(256,"icon_256x256"),(512,"icon_256x256@2x"),(512,"icon_512x512"),(1024,"icon_512x512@2x")] {
    let image = NSImage(size: NSSize(width: size,height: size))
    image.lockFocus()
    let scale = CGFloat(size)/1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let bg = NSBezierPath(roundedRect: NSRect(x: 70,y: 70,width: 884,height: 884),xRadius: 196,yRadius: 196)
    NSColor(calibratedRed: 0.16,green: 0.35,blue: 0.77,alpha: 1).setFill(); bg.fill()
    let corners = NSBezierPath(); corners.lineWidth = 38; corners.lineCapStyle = .round; corners.lineJoinStyle = .round
    for (x,y,sx,sy) in [(CGFloat(285),CGFloat(285),CGFloat(1),CGFloat(1)),(739,285,-1,1),(285,739,1,-1),(739,739,-1,-1)] {
        corners.move(to: NSPoint(x: x+sx*100,y: y)); corners.line(to: NSPoint(x: x,y: y)); corners.line(to: NSPoint(x: x,y: y+sy*100))
    }
    NSColor.white.setStroke(); corners.stroke()
    NSColor(calibratedRed: 0.99,green: 0.78,blue: 0.49,alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 410,y: 410,width: 204,height: 204),xRadius: 42,yRadius: 42).fill()
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png,properties: [:])!.write(to: set.appendingPathComponent(name+".png"))
}
