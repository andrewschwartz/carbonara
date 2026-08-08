import AVFoundation
import CoreVideo

enum FrameSequenceVideoError: LocalizedError {
    case noFrames
    case writeFailed
    case pixelBufferCreationFailed
    case appendFailed(frame: Int)

    var errorDescription: String? {
        switch self {
        case .noFrames: "No frames to encode."
        case .writeFailed: "The video writer failed."
        case .pixelBufferCreationFailed: "Couldn't allocate a pixel buffer."
        case .appendFailed(let frame): "Couldn't append frame \(frame)."
        }
    }
}

/// Encodes an ordered CGImage sequence into an H.264 `.mp4` at a fixed fps.
/// Used to bake Backlot camera moves into previs clips. Frames are drawn into
/// pool-backed pixel buffers off-main; PTS is integer-frame at the given fps.
enum FrameSequenceVideoWriter {

    /// Writes `frames` to `outputURL` at `fps`. All frames must share `size`.
    /// Honors cancellation between frames and finalizes atomically.
    @concurrent
    static func write(
        frames: [CGImage],
        size: CGSize,
        fps: Int,
        to outputURL: URL
    ) async throws {
        guard !frames.isEmpty else { throw FrameSequenceVideoError.noFrames }
        let width = encoderDimension(size.width)
        let height = encoderDimension(size.height)
        let timescale = CMTimeScale(max(1, fps))

        let fm = FileManager.default
        let parentDir = outputURL.deletingLastPathComponent()
        try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        let tempURL = parentDir.appendingPathComponent(".writing-\(UUID().uuidString).mp4")
        var finalized = false
        defer { if !finalized { try? fm.removeItem(at: tempURL) } }

        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            ]
        )
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FrameSequenceVideoError.writeFailed }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else { throw FrameSequenceVideoError.writeFailed }

        do {
            for (index, image) in frames.enumerated() {
                try Task.checkCancellation()
                let buffer = try makeBuffer(from: image, pool: pool, width: width, height: height)
                while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
                let pts = CMTime(value: CMTimeValue(index), timescale: timescale)
                guard adaptor.append(buffer, withPresentationTime: pts) else {
                    throw writer.error ?? FrameSequenceVideoError.appendFailed(frame: index)
                }
            }
        } catch {
            writer.cancelWriting()
            throw error
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? FrameSequenceVideoError.writeFailed }
        try fm.moveItem(at: tempURL, to: outputURL)
        finalized = true
    }

    private static func makeBuffer(from image: CGImage, pool: CVPixelBufferPool, width: Int, height: Int) throws -> CVPixelBuffer {
        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out) == kCVReturnSuccess,
              let buffer = out else { throw FrameSequenceVideoError.pixelBufferCreationFailed }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw FrameSequenceVideoError.pixelBufferCreationFailed }
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, colorSpace, .shouldPropagate)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    // H.264 encoder paths reject odd frame sizes.
    private static func encoderDimension(_ value: CGFloat) -> Int {
        let pixels = Int(value.rounded(.down))
        return max(2, pixels - pixels % 2)
    }
}
