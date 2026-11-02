#!/bin/bash
# Render the production selection view, with normal fonts and a real ObjC exception.
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
let app = NSApplication.shared
let failure = CommandLine.arguments.contains("--exception")
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
precondition(CaptureRecoveryLog.labelDisabled == failure, "wrong recovery state")
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
NSGraphicsContext.restoreGraphicsState()
print("PASS: 1000 redraws, \(failure ? "real nil-object exception contained; border/handles intact; one diagnostic" : "dimension label visible; no error log")")
SWIFT
for mode in normal exception; do
    inject=0
    args=()
    if [[ "$mode" == exception ]]; then inject=1; args=(--exception); fi
    xcrun clang -fobjc-arc -fobjc-exceptions -DFRAMELET_TEST_LABEL_EXCEPTION="$inject" \
        -I Sources/CaptureTextRenderer/include -c Sources/CaptureTextRenderer/CaptureTextRenderer.m -o "$CHECK_DIR/renderer.o"
    xcrun swiftc -I "$BIN_DIR/Modules" -I Sources/CaptureTextRenderer/include \
        "$BIN_DIR"/FrameletCore.build/*.o "$CHECK_DIR/renderer.o" \
        "$CHECK_DIR/Chrome.swift" "$CHECK_DIR/DebugLog.swift" "$CHECK_DIR/main.swift" -o "$CHECK_DIR/check"
    "$CHECK_DIR/check" "${args[@]+${args[@]}}"
done
