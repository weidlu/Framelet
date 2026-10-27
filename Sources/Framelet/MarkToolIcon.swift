import SwiftUI
import FrameletCore

/// Shared by the inline toolbar, its overflow menu, and the image editor.
/// Effect tools show their result instead of borrowing unrelated layout symbols.
struct MarkToolIcon: View {
    let tool: MarkTool
    var color: Color = .primary

    var body: some View {
        Group {
            switch tool {
            case .pixelate:
                Canvas { context, size in
                    // Contiguous, uneven shades read as pixelation, not an app grid.
                    let shades: [[Double]] = [
                        [0.35, 0.80, 0.50, 0.95],
                        [0.70, 0.45, 1.00, 0.55],
                        [0.95, 0.60, 0.35, 0.80],
                        [0.50, 1.00, 0.70, 0.40]
                    ]
                    let step = min(size.width, size.height) / 4
                    for row in 0..<4 {
                        for column in 0..<4 {
                            let cell = CGRect(x: CGFloat(column) * step, y: CGFloat(row) * step,
                                              width: step, height: step)
                            context.fill(Path(cell), with: .color(color.opacity(shades[row][column])))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
            case .redact:
                Canvas { context, size in
                    let width = size.width
                    let height = size.height
                    for y in [height * 0.08, height * 0.80] {
                        let line = CGRect(x: width * 0.08, y: y, width: width * 0.84, height: height * 0.12)
                        context.fill(Path(roundedRect: line, cornerRadius: 0.5), with: .color(color.opacity(0.4)))
                    }
                    let bar = CGRect(x: 0, y: height * 0.31, width: width, height: height * 0.38)
                    context.fill(Path(roundedRect: bar, cornerRadius: 1), with: .color(color))
                }
            case .pen:
                Image(systemName: "pencil").resizable().scaledToFit()
            default:
                Image(systemName: tool.symbol).resizable().scaledToFit()
            }
        }
        .foregroundStyle(color)
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

extension MarkTool {
    var toolbarHint: String {
        switch self {
        case .arrow: return "拖动绘制箭头"
        case .rectangle: return "拖动框出重点"
        case .ellipse: return "拖动圈出重点"
        case .pen: return "按住拖动画线"
        case .text: return "点击输入文字 · 回车确认"
        case .pixelate: return "拖动添加像素块 · 敏感信息请用遮挡"
        case .redact: return "拖动用不透明黑条覆盖敏感内容"
        }
    }
}
