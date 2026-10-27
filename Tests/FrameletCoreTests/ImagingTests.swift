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
            ("键盘逐像素移动和最小选区",keyboardPixelEditing),
            ("sRGB 取色和坐标方向",pixelColorSampling),
            ("长截图连续拼接与固定页头页脚",scrollStitchContinuity),
            ("真实网页重复段落不误拼",scrollRejectsRepeatedParagraphs),
            ("长图细条拼接及 PNG/TIFF 逐像素保真",scrollPixelFidelity),
            ("长截图拒绝无重叠和空白误拼",scrollRejectsAmbiguity),
            ("截图阶段与鼠标光标一致",capturePointerPhases),
            ("标注拖动限制在已确认选区",captureDrawingBoundary),
            ("窗口感应优先选择最前方窗口",windowHoverOrdering),
            ("单击选窗口与拖动框选阈值",windowClickVersusDrag),
            ("像素瞄准 Retina/1x 坐标与导出边界",precisionPixelCoordinates),
            ("放大镜四角取样与避让",precisionLoupeEdges),
            ("Retina 选区原点与倍率转换",retinaCrop),
            ("选区越界裁剪",clampedCrop),
            ("图像比例与居中",fitting),
            ("PNG 单层遮挡、原图不变",redaction),
            ("马赛克不能恢复先前遮挡",mosaicOverRedaction),
            ("JPEG 导出可解码且尺寸正确",jpeg),
            ("拒绝不可分配的图像尺寸",allocationBounds),
            ("悬浮工具栏优先放在选区下方",toolbarBelow),
            ("底部选区工具栏翻到上方",toolbarAbove),
            ("全屏和窄屏工具栏保持可操作",toolbarClamped),
            ("选区尺寸和圆角控件靠近左上角",cornerControlsLayout),
            ("设置默认值与类型安全",settingsDefaults),
            ("设置往返与坏值修复",settingsRoundTripAndRepair),
            ("全局快捷键合法性",globalShortcutValidation),
            ("Option+A 与零号 A 键持久化",optionAHotKey),
            ("选区到像素坐标映射",cropGeometry),
            ("八点调整手柄几何",eightHandles),
            ("裁剪渲染保持标注锚点",croppedRenderKeepsAnchor),
            ("圆角截图及 PNG/TIFF 透明角",roundedCaptureExport),
            ("小数像素选区裁剪保持原始像素",fractionalCropPreservesPixels),
            ("完成动作策略矩阵",completionPolicyMatrix),
            ("剪贴板同时写入 PNG 与 TIFF",pasteboardWritesPNGAndTIFF),
            ("JPEG 展平透明背景",jpegFlattensTransparency),
            ("设置编码往返保持选择",settingsEncodeDecodeRoundTrip),
            ("未知或损坏设置不崩溃",unknownEnumFallsBack),
            ("像素与视图坐标往返一致",viewRectRoundTrip),
            ("复制替换旧剪贴板类型",pasteboardReplacesExistingContents),
            ("窗口图合成替换桌面像素",windowCompositeReplacesDesktopPixels),
            ("窗口图按窗口frame定位并可裁剪导出",windowCompositeUsesWindowFrameNotSelection)
        ]
        for (name,run) in checks { try run(); print("PASS \(name)") }
        print("\(checks.count) 项检查全部通过")
    }
    static func retinaCrop() throws {
        let rect = Imaging.cropRect(selection: CGRect(x: 100,y: 50,width: 300,height: 200),screenSize: CGSize(width: 1000,height: 600),imageSize: CGSize(width: 2000,height: 1200))
        try expect(rect == CGRect(x: 200,y: 700,width: 600,height: 400),"Retina crop coordinates")
    }
    static func fractionalCropPreservesPixels() throws {
        let ctx = try unwrap(Imaging.context(width: 64, height: 64))
        for x in 0..<64 {
            ctx.setFillColor((x.isMultiple(of: 2) ? NSColor.black : NSColor.white).cgColor)
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: 64))
        }
        let source = try unwrap(ctx.makeImage())
        // Dragging can land between device pixels. Cropping must include those
        // pixels without squeezing the integral crop into a fractional width.
        for selection in [CGRect(x: 5.25, y: 6.25, width: 30.5, height: 20.5),
                          CGRect(x: 6.75, y: 9.5, width: 28.25, height: 18.25)] {
            let crop = CaptureGeometry.cropRect(selection, imageSize: CGSize(width: 64, height: 64))
            let output = try Imaging.renderCropped(source, marks: [], selectionPixelRect: selection)
            try expect(output.width == Int(crop.width) && output.height == Int(crop.height), "fractional crop must retain the full pixel extent")
            for x in 2..<(output.width - 2) {
                try expect(pixel(output, x: x, y: 5) == pixel(source, x: Int(crop.minX) + x, y: Int(crop.minY) + 5), "cropping resampled a sharp screenshot pixel at x=\(x)")
            }
        }
    }
    static func roundedCaptureExport() throws {
        let ctx = try unwrap(Imaging.context(width: 100, height: 80))
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        ctx.setFillColor(NSColor.red.cgColor); ctx.fill(CGRect(x: 15, y: 15, width: 50, height: 40))
        let source = try unwrap(ctx.makeImage())
        let selection = CGRect(x: 10, y: 10, width: 60, height: 50)
        let marks = [Mark(tool: .redact, points: [CGPoint(x: 25, y: 25), CGPoint(x: 35, y: 35)])]
        let square = try Imaging.renderCropped(source, marks: marks, selectionPixelRect: selection)
        let rounded = try Imaging.renderCropped(source, marks: marks, selectionPixelRect: selection, cornerRadius: 16)
        try expect(rounded.width == 60 && rounded.height == 50, "rounding must preserve output dimensions")
        for (x, y) in [(0, 0), (59, 0), (0, 49), (59, 49)] {
            try expect(try pixel(rounded, x: x, y: y)[3] == 0, "every outside corner is transparent")
        }
        try expect(try pixel(rounded, x: 30, y: 25) == pixel(square, x: 30, y: 25), "interior pixels and annotations stay unchanged")
        var antialiased = false
        for y in 0..<16 { for x in 0..<16 {
            let alpha = try pixel(rounded, x: x, y: y)[3]
            if alpha > 0 && alpha < 255 { antialiased = true }
        }}
        try expect(antialiased, "rounded edges should be antialiased")
        let board = NSPasteboard(name: .init("com.framelet.checks.rounded.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        try Imaging.writePasteboard(rounded, to: board)
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            let data = try unwrap(board.data(forType: type))
            let imageSource = try unwrap(CGImageSourceCreateWithData(data as CFData, nil))
            let decoded = try unwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
            try expect(try pixel(decoded, x: 0, y: 0)[3] == 0, "clipboard PNG and TIFF preserve transparent corners")
            try expect(try pixel(decoded, x: 30, y: 25) == pixel(square, x: 30, y: 25), "clipboard preserves interior")
        }
        let originalSquare = try Imaging.roundedCorners(square, radius: 0)
        try expect(try pixel(originalSquare, x: 0, y: 0) == pixel(square, x: 0, y: 0), "zero radius preserves square pixels")
        let onePixel = try unwrap(source.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)))
        let onePixelRounded = try Imaging.roundedCorners(onePixel, radius: 32)
        try expect(try pixel(onePixelRounded, x: 0, y: 0) == pixel(onePixel, x: 0, y: 0), "single-pixel selections must not become transparent")
        let retinaRect = CGRect(x: 0, y: 0, width: 120, height: 100)
        let largeRetinaRect = CGRect(x: 0, y: 0, width: 300, height: 200)
        try expect(CaptureGeometry.selectionCornerRadius(32, in: largeRetinaRect) == 32, "16pt at 2x uses 32 pixel radius")
        try expect(CaptureGeometry.selectionCornerRadius(999, in: retinaRect) == 25, "small selections stay rectangular")
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
    static func cornerControlsLayout() throws {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 240, height: 28)
        let selection = CGRect(x: 100, y: 300, width: 400, height: 200)
        let above = CaptureLayout.selectionControlsFrame(selection: selection, screen: screen, preferredSize: size)
        try expect(above.minX == selection.minX && above.minY == selection.maxY + 6, "controls sit beside the upper-left corner")
        let nearTop = CGRect(x: 900, y: 500, width: 100, height: 300)
        let inside = CaptureLayout.selectionControlsFrame(selection: nearTop, screen: screen, preferredSize: size)
        try expect(screen.contains(inside), "controls stay visible near top and right edges")
        try expect(inside.maxY <= nearTop.maxY, "no room above means controls move inside")
        let fullScreen = CaptureLayout.selectionControlsFrame(selection: screen, screen: screen, preferredSize: size)
        try expect(screen.contains(fullScreen), "full-screen selection keeps controls visible")
        let nearBottom = CGRect(x: 100, y: 10, width: 400, height: 100)
        let toolbar = CaptureLayout.toolbarFrame(selection: nearBottom, screen: screen, preferredSize: CGSize(width: 664, height: 45))
        let controls = CaptureLayout.selectionControlsFrame(selection: nearBottom, screen: screen, preferredSize: size, avoiding: toolbar)
        try expect(screen.contains(controls) && !controls.intersects(toolbar), "corner controls must not be hidden by a toolbar above a bottom-edge selection")
        let tiny = CGRect(x: 100, y: 0, width: 10, height: 10)
        let tinyToolbar = CaptureLayout.toolbarFrame(selection: tiny, screen: screen, preferredSize: CGSize(width: 664, height: 45))
        let tinyControls = CaptureLayout.selectionControlsFrame(selection: tiny, screen: screen, preferredSize: size, avoiding: tinyToolbar)
        try expect(screen.contains(tinyControls) && !tinyControls.intersects(tinyToolbar), "tiny bottom selections keep controls usable")
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
