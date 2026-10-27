import AppKit
import Foundation
import FrameletCore

extension ImagingChecks {
    static func completionPolicyMatrix() throws {
        // Default: 完成 copies and exits, without saving.
        try expect(CompletionPlanner.steps(for: .copy, copyOnSave: true, copyOnPin: true) == [.copyToPasteboard, .exitSession],
                   "copy action copies then exits")
        // Save honours the "also copy" switch.
        try expect(CompletionPlanner.steps(for: .save, copyOnSave: true, copyOnPin: true) == [.saveToDefaultDirectory, .copyToPasteboard, .exitSession],
                   "save + copyOnSave copies")
        try expect(CompletionPlanner.steps(for: .save, copyOnSave: false, copyOnPin: true) == [.saveToDefaultDirectory, .exitSession],
                   "save without copyOnSave does not copy")
        // Save-and-copy always copies.
        try expect(CompletionPlanner.steps(for: .saveAndCopy, copyOnSave: false, copyOnPin: false) == [.saveToDefaultDirectory, .copyToPasteboard, .exitSession],
                   "saveAndCopy copies regardless of the switch")
        // Pin honours its own switch and opens the floating window.
        try expect(CompletionPlanner.steps(for: .pin, copyOnSave: true, copyOnPin: true) == [.copyToPasteboard, .pin, .exitSession],
                   "pin + copyOnPin copies")
        try expect(CompletionPlanner.steps(for: .pin, copyOnSave: true, copyOnPin: false) == [.pin, .exitSession],
                   "pin without copyOnPin does not copy")
        // Cmd+C never exits and never saves.
        try expect(CompletionPlanner.copyOnlySteps() == [.copyToPasteboard], "cmd+C copies only, keeps session")
        // Explicit save always goes through the panel.
        try expect(CompletionPlanner.savePanelSteps(copyOnSave: true) == [.saveWithPanel, .copyToPasteboard, .exitSession],
                   "explicit save opens the panel then copies")
        try expect(CompletionPlanner.savePanelSteps(copyOnSave: false) == [.saveWithPanel, .exitSession],
                   "explicit save without copy")
        // Double-click gating.
        try expect(CompletionPlanner.doubleClickCompletes(.followCompletion), "double-click follows completion")
        try expect(!CompletionPlanner.doubleClickCompletes(.none), "double-click can be disabled")
    }

    static func pasteboardWritesPNGAndTIFF() throws {
        // Isolated, named pasteboard: never touches the user's clipboard.
        let name = NSPasteboard.Name("com.framelet.checks.pasteboard.\(UUID().uuidString)")
        let pasteboard = NSPasteboard(name: name)
        defer { pasteboard.releaseGlobally() }
        let image = try whiteImage(wide: true)
        // Exercises the real production write path, not a copy of it.
        try Imaging.writePasteboard(image, to: pasteboard)
        try expect(pasteboard.data(forType: .png) != nil, "pasteboard has PNG data")
        try expect(pasteboard.data(forType: .tiff) != nil, "pasteboard has TIFF data")
        guard let png = pasteboard.data(forType: .png),
              let source = CGImageSourceCreateWithData(png as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure(description: "pasteboard PNG must decode")
        }
        try expect(decoded.width == image.width && decoded.height == image.height, "pasteboard PNG round-trips at full size")
    }

    static func pasteboardReplacesExistingContents() throws {
        let pasteboard = NSPasteboard(name: .init("com.framelet.checks.replace.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("previous clipboard", forType: .string)
        let image = try unwrap(Imaging.context(width: 1, height: 1)?.makeImage())
        try Imaging.writePasteboard(image, to: pasteboard)
        try expect(pasteboard.string(forType: .string) == nil, "copy replaces the old clipboard types")
        try expect(pasteboard.data(forType: .png) != nil && pasteboard.data(forType: .tiff) != nil, "replacement contains both native image types")
    }

    static func jpegFlattensTransparency() throws {
        // A fully transparent image must encode to JPEG as opaque, not crash.
        let ctx = try unwrap(Imaging.context(width: 32, height: 32))
        ctx.clear(CGRect(x: 0, y: 0, width: 32, height: 32))
        let transparent = try unwrap(ctx.makeImage())
        let data = try Imaging.data(transparent, type: .jpeg, quality: 0.8)
        let source = try unwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try unwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        try expect(decoded.width == 32 && decoded.height == 32, "transparent JPEG keeps size")
        try expect(decoded.alphaInfo == .none || decoded.alphaInfo == .noneSkipLast || decoded.alphaInfo == .noneSkipFirst,
                   "JPEG output has no alpha channel")
    }

    static func settingsEncodeDecodeRoundTrip() throws {
        // Simulate the on-disk path: encode → decode → repaired, twice.
        var settings = AppSettings.defaults
        settings.completionAction = .pin
        settings.doubleClickAction = .none
        settings.copyOnSave = false
        settings.saveFormat = .jpeg
        settings.jpegQuality = 0.75
        settings.strokeWidth = 9
        settings.fontSize = 28
        settings.globalShortcuts[.window] = HotKeyCombo(keyCode: 0x0D, modifiers: HotKeyModifier.command.rawValue | HotKeyModifier.option.rawValue)
        let first = try unwrap(AppSettings.from(data: try unwrap(settings.encode())))
        try expect(first == settings, "settings survive a reload")
        let second = try unwrap(AppSettings.from(data: try unwrap(first.encode())))
        try expect(second == first, "second reload is stable")
    }

    static func unknownEnumFallsBack() throws {
        // A payload written by a future/unknown schema must not crash; invalid
        // JSON returns nil and the app falls back to defaults.
        try expect(AppSettings.from(data: Data("not json".utf8)) == nil, "garbage decodes to nil")
        let missingKeys = Data(#"{"schemaVersion":1}"#.utf8)
        try expect(AppSettings.from(data: missingKeys) == nil, "incomplete payload decodes to nil rather than crashing")
    }

    static func viewRectRoundTrip() throws {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let size = CGSize(width: 2000, height: 1200)
        let selection = CGRect(x: 100, y: 50, width: 300, height: 200)
        let pixel = CaptureGeometry.pixelRect(selection, viewBounds: bounds, imageSize: size)
        let back = CaptureGeometry.viewRect(pixel, viewBounds: bounds, imageSize: size)
        try expect(abs(back.minX - selection.minX) < 0.001 && abs(back.minY - selection.minY) < 0.001
                   && abs(back.width - selection.width) < 0.001 && abs(back.height - selection.height) < 0.001,
                   "pixel↔view round trip is lossless")
        // Negative-origin display (secondary screen to the left).
        let negative = CGRect(x: -1280, y: 0, width: 1280, height: 720)
        let pixelRect = CaptureGeometry.pixelRect(CGRect(x: -1200, y: 100, width: 400, height: 300), viewBounds: negative, imageSize: CGSize(width: 2560, height: 1440))
        try expect(pixelRect == CGRect(x: 160, y: 200, width: 800, height: 600), "negative-origin display maps correctly")
    }
}

extension ImagingChecks {
    static func windowCompositeReplacesDesktopPixels() throws {
        // A 2x "retina" desktop where the left half is white (desktop) and the
        // independently captured window is red. After compositing, the window
        // rect must be red — i.e. the window image, not the desktop, is exported.
        let desktop = try solidImage(width: 200, height: 100, color: .white)
        let window = try solidImage(width: 100, height: 100, color: .red)
        let viewBounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        let imageSize = CGSize(width: 200, height: 100)
        // Window covers the left half in view points.
        let windowRect = CGRect(x: 0, y: 0, width: 50, height: 50)
        let result = try Imaging.compositeWindow(window, into: desktop,
                                                 viewRect: windowRect, viewBounds: viewBounds,
                                                 imageSize: imageSize)
        try expect(result.width == 200 && result.height == 100, "composite keeps snapshot size")
        // `pixel` reads top-down; the left half must be red at any row.
        let left = try pixel(result, x: 10, y: 50)
        let right = try pixel(result, x: 190, y: 50)
        try expect(left[0] > 200 && left[1] < 60 && left[2] < 60, "window pixels replace desktop, got \(left)")
        try expect(right == [255, 255, 255, 255], "desktop outside the window stays untouched, got \(right)")
    }

    static func windowCompositeUsesWindowFrameNotSelection() throws {
        // The window image is drawn at the window's own rect, so a selection
        // inside it exports the window content, and a window offset from the
        // origin lands at the offset (no implicit stretching to the selection).
        let desktop = try solidImage(width: 120, height: 120, color: .white)
        let window = try solidImage(width: 40, height: 40, color: .blue)
        let viewBounds = CGRect(x: 0, y: 0, width: 120, height: 120)
        let imageSize = CGSize(width: 120, height: 120)
        let windowRect = CGRect(x: 40, y: 40, width: 40, height: 40)
        let composed = try Imaging.compositeWindow(window, into: desktop,
                                                   viewRect: windowRect, viewBounds: viewBounds,
                                                   imageSize: imageSize)
        // Centre of the window (bottom-left y=60 -> top-down row 59) is blue.
        let centre = try pixel(composed, x: 60, y: 59)
        try expect(centre[2] > 200 && centre[0] < 60, "window drawn at its frame, got \(centre)")
        // Just outside the window stays desktop white.
        let outside = try pixel(composed, x: 20, y: 59)
        try expect(outside == [255, 255, 255, 255], "outside window rect is untouched, got \(outside)")
        // Exporting a selection inside the window keeps the window content.
        let cropped = try Imaging.renderCropped(composed, marks: [], selectionPixelRect: windowRect)
        try expect(cropped.width == 40 && cropped.height == 40, "selection crop size")
        let croppedPixel = try pixel(cropped, x: 20, y: 20)
        try expect(croppedPixel[2] > 200 && croppedPixel[0] < 60, "cropped export contains window, got \(croppedPixel)")
    }

    static func solidImage(width: Int, height: Int, color: NSColor) throws -> CGImage {
        let ctx = try unwrap(Imaging.context(width: width, height: height))
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try unwrap(ctx.makeImage())
    }
}
