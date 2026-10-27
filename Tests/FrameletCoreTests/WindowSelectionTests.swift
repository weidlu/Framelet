import Foundation
import FrameletCore

extension ImagingChecks {
    static func windowHoverOrdering() throws {
        let front = CaptureWindowCandidate(id: 11, frame: CGRect(x: 100, y: 100, width: 200, height: 200), name: "front")
        let back = CaptureWindowCandidate(id: 22, frame: CGRect(x: 0, y: 0, width: 600, height: 500), name: "back")
        try expect(WindowSelection.target(at: CGPoint(x: 150, y: 150), candidates: [front, back])?.id == 11, "overlap must select frontmost window")
        try expect(WindowSelection.target(at: CGPoint(x: 400, y: 150), candidates: [front, back])?.id == 22, "uncovered area selects the background window")
        try expect(WindowSelection.target(at: CGPoint(x: -50, y: 600), candidates: [front, back]) == nil, "desktop outside windows has no automatic selection")
    }

    static func windowClickVersusDrag() throws {
        let start = CGPoint(x: 150, y: 200)
        try expect(!WindowSelection.isDrag(from: start, to: CGPoint(x: 151, y: 201)), "small mouse jitter stays a window click")
        try expect(WindowSelection.isDrag(from: start, to: CGPoint(x: 153, y: 200)), "threshold starts manual selection")
        try expect(WindowSelection.isDrag(from: start, to: CGPoint(x: 50, y: 80)), "reverse dragging also starts manual selection")
    }
}
