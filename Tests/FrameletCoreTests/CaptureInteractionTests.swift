import Foundation
import FrameletCore

extension ImagingChecks {
    static func capturePointerPhases() throws {
        let rect = CGRect(x: 100, y: 100, width: 400, height: 250)
        let inside = CGPoint(x: 250, y: 200)
        let outside = CGPoint(x: 50, y: 50)
        try expect(CaptureInteraction.pointer(at: outside, selection: nil, tool: nil) == .crosshair, "only a new capture starts in selection mode")
        try expect(CaptureInteraction.pointer(at: outside, selection: rect, tool: nil) == .arrow, "confirmed selection restores arrow outside")
        try expect(CaptureInteraction.pointer(at: inside, selection: rect, tool: nil) == .openHand, "selection interior is movable")
        try expect(CaptureInteraction.pointer(at: outside, selection: rect, tool: nil, moving: true) == .closedHand, "dragging retains closed hand outside its original rect")
        try expect(CaptureInteraction.pointer(at: inside, selection: rect, tool: .text) == .text, "text tool has insertion cursor")
        try expect(CaptureInteraction.pointer(at: outside, selection: rect, tool: .arrow) == .arrow, "drawing tool cannot turn the desktop into a canvas")
        try expect(CaptureInteraction.pointer(at: CGPoint(x: 100, y: 100), selection: rect, tool: nil) == .resize(.bottomLeftCorner), "resize handles take priority over moving")
    }

    static func captureDrawingBoundary() throws {
        let rect = CGRect(x: 200, y: 80, width: 400, height: 250)
        try expect(CaptureInteraction.clamped(CGPoint(x: -100, y: 1000), to: rect) == CGPoint(x: 200, y: 330), "dragging out of the selection clamps both coordinates")
        try expect(CaptureInteraction.clamped(CGPoint(x: 350, y: 120), to: rect) == CGPoint(x: 350, y: 120), "interior drawing points stay unchanged")
    }
}
