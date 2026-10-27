import AppKit
import SwiftUI
import FrameletCore

enum InlineAction: Equatable { case cancel, reselect, copy, save, pin, ocr, undo, redo }

struct InlineCaptureToolbar: View {
    @ObservedObject var document: ImageDocument
    let chooseTool: (MarkTool?) -> Void
    let action: (InlineAction) -> Void
    @State private var activeTool: MarkTool?
    @State private var showOCR = false
    private let colors: [NSColor] = [.systemRed,.systemBlue,.systemGreen,.systemOrange,.white,.black]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal,showsIndicators: false) {
                HStack(spacing: 5) {
                    Text("拾影").font(.system(size:12,weight:.semibold)).foregroundStyle(Palette.muted).padding(.horizontal,6)
                    toolButton("移动选区", symbol:"cursorarrow",selected:activeTool == nil) { activeTool = nil; chooseTool(nil) }
                    Divider().frame(height:22).padding(.horizontal,3)
                    ForEach(MarkTool.allCases) { tool in
                        toolButton(tool.title,symbol:tool.symbol,selected:activeTool == tool) {
                            activeTool = activeTool == tool ? nil : tool
                            chooseTool(activeTool)
                        }
                    }
                    Divider().frame(height:22).padding(.horizontal,3)
                    toolButton("撤销",symbol:"arrow.uturn.backward") { action(.undo) }.disabled(document.marks.isEmpty)
                    toolButton("重做",symbol:"arrow.uturn.forward") { action(.redo) }.disabled(!document.canRedo)
                    toolButton("重新选择",symbol:"viewfinder") { activeTool = nil; chooseTool(nil); action(.reselect) }
                    Divider().frame(height:22).padding(.horizontal,3)
                    toolButton(document.recognizing ? "识别中" : "提取文字",symbol:"text.viewfinder") { action(.ocr) }.disabled(document.recognizing)
                        .popover(isPresented:$showOCR,arrowEdge:.top) { ocrPopover }
                    toolButton("贴图",symbol:"pin") { action(.pin) }
                    toolButton("保存",symbol:"square.and.arrow.down") { action(.save) }
                    toolButton("取消",symbol:"xmark") { action(.cancel) }
                    Button { action(.copy) } label: {
                        Label("完成",systemImage:"checkmark").font(.system(size:12,weight:.semibold)).padding(.horizontal,10).frame(height:32)
                    }.buttonStyle(.plain).foregroundStyle(.white).background(Palette.blue,in:RoundedRectangle(cornerRadius:6))
                        .help("复制到剪贴板并退出截图 · Enter").accessibilityLabel("完成并复制")
                }.padding(.horizontal,10).padding(.vertical,9)
            }.frame(height:51)
            Divider().padding(.horizontal,10)
            HStack(spacing:7) {
                ForEach(Array(colors.enumerated()),id:\.offset) { _, color in
                    Button { document.color = color } label: {
                        Circle().fill(Color(nsColor:color)).frame(width:13,height:13)
                            .overlay(Circle().stroke(.gray.opacity(0.35),lineWidth:1)).padding(3)
                            .overlay(Circle().stroke(document.color == color ? Palette.blue : .clear,lineWidth:1.5))
                    }.buttonStyle(.plain).accessibilityLabel(color.accessibilityName)
                }
                Divider().frame(height:14).padding(.horizontal,3)
                Slider(value:$document.strokeWidth,in:2...12,step:1).frame(width:75).accessibilityLabel("标注粗细")
                Spacer(minLength:8)
                if document.recognizing { ProgressView().controlSize(.mini) }
                Text(document.message ?? hint).font(.system(size:10)).foregroundStyle(Palette.muted).lineLimit(1)
                Text("\(document.original.width) × \(document.original.height)").font(.system(size:10,design:.monospaced)).foregroundStyle(Palette.muted)
            }.padding(.horizontal,13).frame(height:41)
        }.background(.white,in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(Palette.ink.opacity(0.12),lineWidth:1))
            .foregroundStyle(Palette.ink).preferredColorScheme(.light)
            .onChange(of: document.ocrText) { _, value in if value != nil { showOCR = true } }
    }

    private var hint: String {
        if activeTool == .text { return "点击选区输入文字 · 回车确认文字" }
        if activeTool == .redact { return "拖动覆盖敏感内容" }
        if activeTool == .pixelate { return "敏感文字建议使用遮挡" }
        return activeTool == nil ? "Enter 复制 · Esc 取消" : "在选区内直接标注"
    }
    private func toolButton(_ title: String,symbol:String,selected:Bool = false,action:@escaping ()->Void) -> some View {
        Button(action:action) {
            Image(systemName:symbol).font(.system(size:16,weight:.medium)).frame(width:31,height:32)
                .foregroundStyle(selected ? Palette.blue : Palette.ink)
                .background(selected ? Palette.blue.opacity(0.10) : .clear,in:RoundedRectangle(cornerRadius:6))
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
    private var ocrPopover: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text("提取文字").font(.headline); Spacer(); Text("本机识别").font(.caption).foregroundStyle(.secondary) }
            TextEditor(text:Binding(get:{document.ocrText ?? ""},set:{document.ocrText = $0})).font(.system(size:13)).border(.gray.opacity(0.2))
            HStack {
                Button("收起") { showOCR = false }
                Spacer()
                Button("复制文字") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(document.ocrText ?? "",forType:.string) }.buttonStyle(.borderedProminent).tint(Palette.blue)
            }
        }.padding(18).frame(width:400,height:300)
    }
}
