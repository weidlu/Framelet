import Foundation

/// Front-to-back, frozen window geometry. No Accessibility permission is needed.
public struct CaptureWindowCandidate {
    public let id: UInt32
    public let frame: CGRect
    public let name: String

    public init(id: UInt32, frame: CGRect, name: String) {
        self.id = id; self.frame = frame; self.name = name
    }
}

public enum WindowSelection {
    public static let dragThreshold: CGFloat = 3

    public static func target(at point: CGPoint, candidates: [CaptureWindowCandidate]) -> CaptureWindowCandidate? {
        candidates.first { $0.frame.contains(point) }
    }

    public static func isDrag(from start: CGPoint, to end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) >= dragThreshold
    }
}
