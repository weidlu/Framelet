import Foundation

public enum CaptureLayout {
    /// Put dimensions and the corner slider next to the upper-left edge.
    /// If there is no room above the selection, place them just inside it.
    public static func selectionControlsFrame(selection: CGRect, screen: CGRect, preferredSize: CGSize, avoiding: CGRect? = nil) -> CGRect {
        let margin: CGFloat = 8, gap: CGFloat = 6
        let width = min(preferredSize.width, max(1, screen.width - margin * 2))
        let height = min(preferredSize.height, max(1, screen.height - margin * 2))
        let x = min(max(screen.minX + margin, selection.minX), screen.maxX - margin - width)
        let above = selection.maxY + gap
        let inside = selection.maxY - gap - height
        let below = selection.minY - gap - height
        var candidates = [above, inside, below]
        if let avoiding { candidates += [avoiding.maxY + gap, avoiding.minY - gap - height] }
        for y in candidates {
            let frame = CGRect(x: x, y: y, width: width, height: height)
            if frame.minY >= screen.minY + margin, frame.maxY <= screen.maxY - margin,
               avoiding?.intersects(frame) != true { return frame }
        }
        let fallback = min(max(screen.minY + margin, inside), screen.maxY - margin - height)
        return CGRect(x: x, y: fallback, width: width, height: height)
    }
    /// AppKit coordinates: prefer immediately below the selection, then above it.
    public static func toolbarFrame(selection: CGRect, screen: CGRect, preferredSize: CGSize) -> CGRect {
        let margin: CGFloat = 12, gap: CGFloat = 10
        let width = min(preferredSize.width, max(1, screen.width-margin*2))
        let height = min(preferredSize.height, max(1, screen.height-margin*2))
        let x = min(max(screen.minX+margin, selection.maxX-width), screen.maxX-margin-width)
        let below = selection.minY-gap-height
        let above = selection.maxY+gap
        let y: CGFloat
        if below >= screen.minY+margin { y = below }
        else if above+height <= screen.maxY-margin { y = above }
        else { y = min(max(screen.minY+margin, below), screen.maxY-margin-height) }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
