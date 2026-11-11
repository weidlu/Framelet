#!/bin/bash
# Render the production selection and loupe views with normal fonts and injected ObjC exceptions.
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/swift.sh build --product Framelet
BIN_DIR="$(bash scripts/swift.sh build --show-bin-path)"
mkdir -p work
CHECK_DIR="$(mktemp -d "$PWD/work/capture-label-check.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
export CHECK_DIR
python3 - <<'PYTHON'
import os
from pathlib import Path
root = Path.cwd()
out = Path(os.environ["CHECK_DIR"])
# Use the actual view; omit unrelated SwiftUI controls requiring the whole app.
chrome = (root / "Sources/Framelet/CaptureChrome.swift").read_text().split("/// Floating controls")[0]
(out / "Chrome.swift").write_text(chrome)
# Same diagnostics implementation with only its output destination relocated.
diag = (root / "Sources/Framelet/DebugLog.swift").read_text().replace(
    'FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]',
    'URL(fileURLWithPath: ProcessInfo.processInfo.environment["CHECK_DIR"]!)')
(out / "DebugLog.swift").write_text(diag)
PYTHON
cat > "$CHECK_DIR/main.swift" <<'SWIFT'
import AppKit
import FrameletCore
let app = NSApplication.shared
let failure = CommandLine.arguments.contains("dimension")
let loupeFailure = CommandLine.arguments.contains("loupe")
let view = CaptureSelectionChrome(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
for i in 1...1000 {
    view.selection = CGRect(x: 40, y: 50, width: 100 + i % 500, height: 100 + i % 300)
    view.pixelSize = CGSize(width: 2 * (100 + i % 500), height: 2 * (100 + i % 300))
    view.draw(view.bounds)
    precondition(NSGraphicsContext.current === context, "graphics state not restored")
}
precondition(CaptureRecoveryLog.isDisabled(.dimensionLabel) == failure, "wrong recovery state")
if failure {
    let log = try String(contentsOf: CaptureRecoveryLog.logURL, encoding: .utf8)
    precondition(log.contains("NSInvalidArgumentException") && log.contains("nil object"), "missing error evidence")
    precondition(log.components(separatedBy: "dimension-label-disabled").count == 2, "error repeated on every frame")
    // Drawing with the failed label matches explicitly hiding the label, including handles/border.
    let noLabel = CaptureSelectionChrome(frame: view.frame)
    noLabel.selection = view.selection; noLabel.pixelSize = view.pixelSize; noLabel.showLabel = false
    let expected = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: expected)
    noLabel.draw(noLabel.bounds)
    NSGraphicsContext.current = context
    context.cgContext.clear(view.bounds)
    view.draw(view.bounds)
    precondition(bitmap.tiffRepresentation == expected.tiffRepresentation, "recovery damaged selection chrome")
} else {
    precondition(!FileManager.default.fileExists(atPath: CaptureRecoveryLog.logURL.path), "normal redraw wrote errors")
    // Label must actually paint above the selection.
    precondition((bitmap.colorAt(x: 50, y: 338)?.alphaComponent ?? 0) > 0, "label did not render")
}
context.cgContext.clear(view.bounds)
let source = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
source.setFillColor(NSColor.red.cgColor)
source.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
let loupe = PrecisionCaptureGuide(image: source.makeImage()!)
loupe.frame = view.frame
for i in 1...500 {
    loupe.point = CGPoint(x: 320 + i % 16, y: 250 + i % 16)
    loupe.dragging = i.isMultiple(of: 2)
    loupe.message = loupe.dragging ? "已复制 HEX" : nil
    context.cgContext.clear(loupe.bounds)
    loupe.draw(loupe.bounds)
    precondition(NSGraphicsContext.current === context, "loupe graphics state not restored")
}
precondition(CaptureRecoveryLog.isDisabled(.loupeText) == loupeFailure, "wrong loupe recovery state")
precondition(CaptureRecoveryLog.isDisabled(.dimensionLabel) == failure, "loupe failure disabled the dimension label")
let panel = PixelInspection.panelFrame(at: loupe.point!, bounds: loupe.bounds, size: CGSize(width: 184, height: 224))
let gridColor = bitmap.colorAt(x: Int(panel.midX + 19), y: 599 - Int(panel.maxY - 51))!
precondition(gridColor.redComponent > 0.8 && gridColor.greenComponent < 0.2, "loupe grid did not survive")
let textPixels = (Int(panel.minX + 12)..<Int(panel.minX + 170)).contains { x in
    (Int(panel.minY + 7)..<Int(panel.minY + 85)).contains { y in
        (bitmap.colorAt(x: x, y: 599 - y)?.redComponent ?? 0) > 0.6
    }
}
precondition(textPixels != loupeFailure, "loupe text did not render or was not hidden")
if loupeFailure {
    let log = try String(contentsOf: CaptureRecoveryLog.logURL, encoding: .utf8)
    precondition(log.contains("NSInvalidArgumentException") && log.contains("nil object") && log.contains("coordinates"))
    precondition(log.components(separatedBy: "loupe-text-disabled").count == 2, "loupe error repeated on every frame")
}
NSGraphicsContext.restoreGraphicsState()
print("PASS: 1000 selection and 500 loupe redraws (\(CommandLine.arguments.last!))")
SWIFT
for mode in normal dimension loupe; do
    dimension=0
    loupe=0
    if [[ "$mode" == dimension ]]; then dimension=1; fi
    if [[ "$mode" == loupe ]]; then loupe=1; fi
    rm -f "$CHECK_DIR/Logs/Framelet/capture-errors.log"
    xcrun clang -fobjc-arc -fobjc-exceptions -DFRAMELET_TEST_LABEL_EXCEPTION="$dimension" -DFRAMELET_TEST_LOUPE_EXCEPTION="$loupe" \
        -I Sources/CaptureTextRenderer/include -c Sources/CaptureTextRenderer/CaptureTextRenderer.m -o "$CHECK_DIR/renderer.o"
    xcrun swiftc -I "$BIN_DIR/Modules" -I Sources/CaptureTextRenderer/include \
        "$BIN_DIR"/FrameletCore.build/*.o "$CHECK_DIR/renderer.o" Sources/Framelet/PrecisionCaptureGuide.swift \
        "$CHECK_DIR/Chrome.swift" "$CHECK_DIR/DebugLog.swift" "$CHECK_DIR/main.swift" -o "$CHECK_DIR/check"
    "$CHECK_DIR/check" "$mode"
done
