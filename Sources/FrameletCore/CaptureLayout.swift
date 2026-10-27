import Foundation

public enum CaptureLayout {
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
