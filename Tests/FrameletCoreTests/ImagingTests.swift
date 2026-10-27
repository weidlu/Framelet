import AppKit
import ImageIO
import FrameletCore

/// A standalone test runner also usable on CLT-only machines without XCTest.
@main enum ImagingChecks {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw Failure(description: message) }
    }
    static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw Failure(description: "unexpected nil") }; return value
    }
    static func main() throws {
        let checks: [(String,() throws -> Void)] = [
            ("Retina 选区原点与倍率转换",retinaCrop),
            ("选区越界裁剪",clampedCrop),
            ("图像比例与居中",fitting),
            ("PNG 单层遮挡、原图不变",redaction),
            ("马赛克不能恢复先前遮挡",mosaicOverRedaction),
            ("JPEG 导出可解码且尺寸正确",jpeg),
            ("拒绝不可分配的图像尺寸",allocationBounds),
            ("悬浮工具栏优先放在选区下方",toolbarBelow),
            ("底部选区工具栏翻到上方",toolbarAbove),
            ("全屏和窄屏工具栏保持可操作",toolbarClamped)
        ]
        for (name,run) in checks { try run(); print("PASS \(name)") }
        print("\(checks.count) 项检查全部通过")
    }
    static func retinaCrop() throws {
        let rect = Imaging.cropRect(selection: CGRect(x: 100,y: 50,width: 300,height: 200),screenSize: CGSize(width: 1000,height: 600),imageSize: CGSize(width: 2000,height: 1200))
        try expect(rect == CGRect(x: 200,y: 700,width: 600,height: 400),"Retina crop coordinates")
    }
    static func clampedCrop() throws {
        let rect = Imaging.cropRect(selection: CGRect(x: -10,y: -20,width: 110,height: 120),screenSize: CGSize(width: 1000,height: 600),imageSize: CGSize(width: 2000,height: 1200))
        try expect(rect == CGRect(x: 0,y: 1000,width: 200,height: 200),"edge clamp")
        try expect(Imaging.cropRect(selection: CGRect(x: 3000,y: 0,width: 50,height: 50),screenSize: CGSize(width: 1000,height: 600),imageSize: CGSize(width: 2000,height: 1200)) == .zero,"off-screen selection")
    }
    static func fitting() throws {
        try expect(Imaging.fittedRect(image: CGSize(width: 2000,height: 1000),bounds: CGRect(x: 10,y: 20,width: 600,height: 600)) == CGRect(x: 10,y: 170,width: 600,height: 300),"aspect fit")
    }
    static func redaction() throws {
        let original = try whiteImage()
        let marks = [Mark(tool: .redact,points: [CGPoint(x: 16,y: 16),CGPoint(x: 48,y: 48)])]
        let png = try Imaging.data(Imaging.render(original,marks: marks))
        let source = try unwrap(CGImageSourceCreateWithData(png as CFData,nil))
        let decoded = try unwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        try expect(CGImageSourceGetCount(source) == 1,"one flattened image")
        try expect(pixel(decoded,x: 32,y: 32) == [0,0,0,255],"redacted pixels must be opaque black")
        try expect(pixel(decoded,x: 2,y: 2) == [255,255,255,255],"outside region remains white")
        try expect(pixel(original,x: 32,y: 32) == [255,255,255,255],"original remains unmodified")
    }
    static func mosaicOverRedaction() throws {
        let original = try whiteImage()
        let points = [CGPoint(x: 0,y: 0),CGPoint(x: 64,y: 64)]
        let result = try Imaging.render(original,marks: [Mark(tool: .redact,points: points),Mark(tool: .pixelate,points: points)])
        try expect(pixel(result,x: 32,y: 32) == [0,0,0,255],"mosaic revealed underlying original")
    }
    static func jpeg() throws {
        let data = try Imaging.data(whiteImage(),type: .jpeg)
        let source = try unwrap(CGImageSourceCreateWithData(data as CFData,nil))
        let image = try unwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        try expect(image.width == 64 && image.height == 64,"JPEG dimensions")
    }
    static func allocationBounds() throws {
        try expect(Imaging.context(width: 0,height: 64) == nil,"zero image")
        try expect(Imaging.context(width: 100001,height: 100001) == nil,"oversized image")
    }
    static func toolbarBelow() throws {
        let screen = CGRect(x:0,y:0,width:1512,height:982)
        let selection = CGRect(x:200,y:400,width:600,height:300)
        let toolbar = CaptureLayout.toolbarFrame(selection:selection,screen:screen,preferredSize:CGSize(width:820,height:94))
        try expect(toolbar.maxY == selection.minY-10,"toolbar must follow the selection below")
        try expect(screen.contains(toolbar),"toolbar must stay on screen")
    }
    static func toolbarAbove() throws {
        let screen = CGRect(x:0,y:0,width:1512,height:982)
        let selection = CGRect(x:100,y:20,width:600,height:200)
        let toolbar = CaptureLayout.toolbarFrame(selection:selection,screen:screen,preferredSize:CGSize(width:820,height:94))
        try expect(toolbar.minY == selection.maxY+10,"bottom-edge selection needs the toolbar above")
    }
    static func toolbarClamped() throws {
        for screen in [CGRect(x:0,y:0,width:1512,height:982),CGRect(x:0,y:0,width:640,height:480),CGRect(x:-1280,y:0,width:1280,height:720)] {
            let toolbar = CaptureLayout.toolbarFrame(selection:screen,screen:screen,preferredSize:CGSize(width:820,height:94))
            try expect(screen.contains(toolbar),"full-screen toolbar escapes display bounds")
            try expect(toolbar.width <= screen.width-24,"narrow screen toolbar must fit")
        }
    }
    static func whiteImage() throws -> CGImage {
        let context = try unwrap(Imaging.context(width: 64,height: 64))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0,y: 0,width: 64,height: 64))
        return try unwrap(context.makeImage())
    }
    static func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let context = try unwrap(Imaging.context(width: image.width,height: image.height))
        context.draw(image,in: CGRect(x: 0,y: 0,width: image.width,height: image.height))
        let data = try unwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = y*context.bytesPerRow+x*4
        return (0..<4).map { data[offset+$0] }
    }
}
