import AppKit
import Foundation
import FrameletCore

extension ImagingChecks {
    static func settingsDefaults() throws {
        let defaults = AppSettings.defaults
        try expect(defaults.schemaVersion == AppSettings.currentSchemaVersion, "schema version")
        try expect(defaults.completionAction == .copy, "default completion copies")
        try expect(defaults.copyOnSave && defaults.copyOnPin, "default copy on save/pin")
        try expect(defaults.effectiveSelectionCornerRadius == 16, "selection defaults to a moderate rounded corner")
        try expect(defaults.globalShortcuts[.region]??.keyCode == 0x15, "default region key ⌃⌥4")
        try expect(defaults.globalShortcuts[.fullscreen]??.keyCode == 0x14, "default fullscreen key ⌃⌥3")
        try expect(defaults.toolShortcuts[.move]??.keyCode == 0x09, "default move key V")
        try expect(defaults.toolShortcuts[.ocr]??.keyCode == 0x1F, "default OCR key O")
    }

    static func settingsRoundTripAndRepair() throws {
        var settings = AppSettings.defaults
        settings.completionAction = .saveAndCopy
        settings.globalShortcuts[.window] = HotKeyCombo(keyCode: 0x20, modifiers: HotKeyModifier.command.rawValue)
        let data = try unwrap(settings.encode())
        let decoded = try unwrap(AppSettings.from(data: data))
        try expect(decoded == settings, "round-trip preserves typed settings")

        settings.selectionCornerRadius = 0
        let square = try unwrap(AppSettings.from(data: try unwrap(settings.encode())))
        try expect(square.effectiveSelectionCornerRadius == 0 && square.completionAction == .saveAndCopy, "square corner setting persists without changing other preferences")
        var legacy = try unwrap(JSONSerialization.jsonObject(with: try unwrap(settings.encode())) as? [String: Any])
        legacy.removeValue(forKey: "selectionCornerRadius")
        let migrated = try unwrap(AppSettings.from(data: try JSONSerialization.data(withJSONObject: legacy)))
        try expect(migrated.effectiveSelectionCornerRadius == 16, "existing preferences default to rounded corners")
        try expect(migrated.completionAction == .saveAndCopy && migrated.globalShortcuts[.window] == settings.globalShortcuts[.window], "existing preferences survive migration")

        var corrupt = AppSettings.defaults
        corrupt.jpegQuality = 42
        corrupt.strokeWidth = 999
        corrupt.selectionCornerRadius = 999
        corrupt.globalShortcuts[.window] = HotKeyCombo(keyCode: 0x20) // bare key: invalid global
        corrupt.globalShortcuts[.lastRegion] = HotKeyCombo(keyCode: 0x21, modifiers: HotKeyModifier.shift.rawValue) // shift-only: invalid
        corrupt.toolShortcuts[.pin] = HotKeyCombo(keyCode: 0x09) // duplicates move V: invalid tool key
        let repaired = corrupt.repaired
        try expect(repaired.jpegQuality == 1.0, "jpeg quality clamped")
        try expect(repaired.strokeWidth == 24, "stroke width clamped")
        try expect(repaired.selectionCornerRadius == 32, "corner radius clamped")
        try expect(repaired.globalShortcuts[.window] == nil, "bare global key rejected")
        try expect(repaired.globalShortcuts[.lastRegion] == nil, "shift-only global key rejected")
        try expect(repaired.toolShortcuts[.pin] == nil, "duplicate tool key rejected")
        try expect(repaired.globalShortcuts[.region]??.keyCode == 0x15, "valid key survives repair")
    }

    static func globalShortcutValidation() throws {
        try expect(!HotKeyCombo(keyCode: 0).isValidGlobal, "bare A is invalid as a global shortcut")
        try expect(!HotKeyCombo(keyCode: 0x20).isValidGlobal, "bare key invalid global")
        try expect(!HotKeyCombo(keyCode: 0x20, modifiers: HotKeyModifier.shift.rawValue).isValidGlobal, "shift-only invalid global")
        try expect(HotKeyCombo(keyCode: 0x20, modifiers: HotKeyModifier.command.rawValue).isValidGlobal, "cmd key valid")
        try expect(HotKeyCombo(keyCode: 0x20, modifiers: HotKeyModifier.control.rawValue | HotKeyModifier.option.rawValue).isValidGlobal, "ctrl+opt valid")
        try expect(HotKeyCombo(keyCode: 0x09).isBareKey, "bare V valid tool key")
        try expect(!HotKeyCombo(keyCode: 0x09, modifiers: HotKeyModifier.command.rawValue).isBareKey, "cmd V not a bare tool key")
    }

    static func optionAHotKey() throws {
        let optionA = HotKeyCombo(keyCode: 0, modifiers: HotKeyModifier.option.rawValue)
        try expect(optionA.hasOption && optionA.isValidGlobal, "Option+A must be valid: macOS A has virtual key code zero")
        try expect(HotKeyCombo(keyCode: 0).isBareKey, "A is a valid bare annotation key")
        try expect(!HotKeyCombo(keyCode: 999, modifiers: HotKeyModifier.option.rawValue).isValidGlobal, "unknown key codes are invalid")
        var settings = AppSettings.defaults
        settings.globalShortcuts[.region] = optionA
        let restored = try unwrap(AppSettings.from(data: try unwrap(settings.encode())))
        try expect(restored.globalShortcuts[.region] == optionA, "settings repair must not drop Option+A")
    }

    static func cropGeometry() throws {
        // 2x retina: 1000×600 points → 2000×1200 pixels.
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let size = CGSize(width: 2000, height: 1200)
        let selection = CGRect(x: 100, y: 50, width: 300, height: 200)
        let pixel = CaptureGeometry.pixelRect(selection, viewBounds: bounds, imageSize: size)
        try expect(pixel == CGRect(x: 200, y: 100, width: 600, height: 400), "pixel rect scales uniformly")
        let crop = CaptureGeometry.cropRect(pixel, imageSize: size)
        try expect(crop == CGRect(x: 200, y: 700, width: 600, height: 400), "CGImage crop flips Y")
    }

    static func eightHandles() throws {
        let selection = CGRect(x: 100, y: 100, width: 200, height: 150)
        let handles = CaptureGeometry.resizeHandles(for: selection)
        try expect(handles.count == 8, "eight resize handles")
        try expect(handles.contains(CGPoint(x: 100, y: 100)), "bottom-left corner present")
        try expect(handles.contains(CGPoint(x: 300, y: 250)), "top-right corner present")
        try expect(handles.contains(CGPoint(x: 200, y: 100)), "bottom edge midpoint present")
        try expect(handles.contains(CGPoint(x: 300, y: 175)), "right edge midpoint present")

        let corner = try unwrap(CaptureGeometry.handleKind(at: CGPoint(x: 100, y: 100), selection: selection))
        try expect(corner == .bottomLeftCorner, "corner kind")
        let edge = try unwrap(CaptureGeometry.handleKind(at: CGPoint(x: 200, y: 100), selection: selection))
        try expect(edge == .bottomEdge, "edge kind")
        try expect(edge.isEdge, "edge handle is an edge")

        let resized = try unwrap(CaptureGeometry.resized(selection: selection, kind: .bottomLeftCorner, to: CGPoint(x: 60, y: 40), bounds: CGRect(x: 0, y: 0, width: 1000, height: 800)))
        try expect(resized.origin == CGPoint(x: 60, y: 40) && resized.maxX == 300 && resized.maxY == 250, "corner resize keeps opposite corner")
        // Dragging a corner far past the opposite corner clamps to the minimum size.
        let clamped = try unwrap(CaptureGeometry.resized(selection: selection, kind: .topRightCorner, to: CGPoint(x: 0, y: 0), bounds: CGRect(x: 0, y: 0, width: 1000, height: 800)))
        try expect(clamped == CGRect(x: 100, y: 100, width: 8, height: 8), "corner resize clamps at minimum")
        let edgeResized = try unwrap(CaptureGeometry.resized(selection: selection, kind: .topEdge, to: CGPoint(x: 400, y: 300), bounds: CGRect(x: 0, y: 0, width: 1000, height: 800)))
        try expect(edgeResized.minX == 100 && edgeResized.maxX == 300 && edgeResized.maxY == 300 && edgeResized.minY == 100, "edge resize only changes one edge")
    }

    static func croppedRenderKeepsAnchor() throws {
        let full = try whiteImage(wide: true)
        // A redaction at full-image (100,100)…(200,200), selection shifted to the right.
        let mark = Mark(tool: .redact, points: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200)])
        let selection = CGRect(x: 60, y: 60, width: 200, height: 200)
        let rendered = try Imaging.renderCropped(full, marks: [mark], selectionPixelRect: selection)
        try expect(rendered.width == 200 && rendered.height == 200, "cropped size")
        // `pixel` reads raw buffer rows from the top; a bottom-left point (x,y)
        // lives at memory row (height-1-y). Full (100,100) maps to crop (40,40).
        try expect(pixel(rendered, x: 40, y: 159) == [0, 0, 0, 255], "mark anchored to full-image coordinates")
        try expect(pixel(rendered, x: 10, y: 189) == [255, 255, 255, 255], "background stays white")
        // A mark fully outside the selection is cropped away.
        let outside = Mark(tool: .redact, points: [CGPoint(x: 900, y: 900), CGPoint(x: 950, y: 950)])
        let croppedAway = try Imaging.renderCropped(full, marks: [outside], selectionPixelRect: selection)
        try expect(pixel(croppedAway, x: 40, y: 159) == [255, 255, 255, 255], "outside mark cropped")
    }

    static func whiteImage(wide: Bool = false) throws -> CGImage {
        let w = wide ? 512 : 64, h = wide ? 512 : 64
        let context = try unwrap(Imaging.context(width: w, height: h))
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return try unwrap(context.makeImage())
    }
}
