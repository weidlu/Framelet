import AppKit
import ScreenCaptureKit
import CoreImage
import FrameletCore

/// A bounded stream: slow matching drops stale frames instead of accumulating
/// full-resolution screen buffers. No audio or cursor is captured.
final class ScrollFrameStream: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let frames: AsyncThrowingStream<CGImage, Error>
    private let sink: AsyncThrowingStream<CGImage, Error>.Continuation
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let crop: CGRect
    private let queue = DispatchQueue(label: "com.framelet.scroll.frames", qos: .userInitiated)
    @MainActor private var stream: SCStream?

    private init(crop: CGRect) {
        self.crop = crop
        (frames, sink) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        super.init()
    }

    @MainActor static func start(region: LastRegion, excluding ids: [CGWindowID]) async throws -> ScrollFrameStream {
        guard NSScreen.screens.contains(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == region.displayID && $0.frame == region.screenFrame
        }) else { throw CaptureError.noDisplay }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else { throw CaptureError.noDisplay }
        let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { ids.contains($0.windowID) })
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        config.showsCursor = false; config.capturesAudio = false; config.captureResolution = .best
        config.minimumFrameInterval = CMTime(value: 1, timescale: 15)
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA
        let size = CGSize(width: config.width, height: config.height)
        let rect = region.selection.offsetBy(dx: -region.screenFrame.minX, dy: -region.screenFrame.minY)
        let pixels = CaptureGeometry.pixelRect(rect, viewBounds: CGRect(origin: .zero, size: region.screenFrame.size), imageSize: size)
        let source = ScrollFrameStream(crop: CaptureGeometry.cropRect(pixels, imageSize: size))
        let stream = SCStream(filter: filter, configuration: config, delegate: source)
        try stream.addStreamOutput(source, type: .screen, sampleHandlerQueue: source.queue)
        source.stream = stream
        do { try await stream.startCapture() }
        catch { await source.stop(); throw error }
        return source
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        autoreleasepool {
            let input = CIImage(cvPixelBuffer: pixels)
            guard let full = context.createCGImage(input, from: input.extent),
                  let image = full.cropping(to: crop) else { return }
            sink.yield(image)
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { sink.finish(throwing: error) }

    @MainActor func stop() async {
        guard let stream else { return }
        self.stream = nil
        sink.finish()
        try? await stream.stopCapture()
        try? stream.removeStreamOutput(self, type: .screen)
    }
}
