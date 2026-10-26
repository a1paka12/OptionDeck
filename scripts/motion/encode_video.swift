import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main
struct QuickstartEncoder {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let frames = root.appendingPathComponent(".build/quickstart-frames")
        let output = root.appendingPathComponent("docs/assets/quickstart.mp4")
        guard FileManager.default.fileExists(atPath: frames.appendingPathComponent("0359.png").path) else {
            throw NSError(domain: "Quickstart", code: 1, userInfo: [NSLocalizedDescriptionKey: "Run render_quickstart.py first from the project root."])
        }
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1280, AVVideoHeightKey: 720,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_600_000, AVVideoExpectedSourceFrameRateKey: 12,
                                            AVVideoMaxKeyFrameIntervalKey: 24, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 1280, kCVPixelBufferHeightKey as String: 720,
            kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "Quickstart", code: 2) }
        writer.startSession(atSourceTime: .zero)
        for index in 0..<360 {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? NSError(domain: "Quickstart", code: 3) }
                try await Task.sleep(for: .milliseconds(2))
            }
            try autoreleasepool {
                let url = frames.appendingPathComponent(String(format: "%04d.png", index))
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                      let pool = adaptor.pixelBufferPool else { throw NSError(domain: "Quickstart", code: 4) }
                var raw: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &raw) == kCVReturnSuccess, let buffer = raw else { throw NSError(domain: "Quickstart", code: 5) }
                CVPixelBufferLockBaseAddress(buffer, [])
                defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 1280, height: 720, bitsPerComponent: 8,
                                              bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                    throw NSError(domain: "Quickstart", code: 6)
                }
                context.draw(image, in: CGRect(x: 0, y: 0, width: 1280, height: 720))
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 12)) else {
                    throw writer.error ?? NSError(domain: "Quickstart", code: 7)
                }
            }
        }
        writer.endSession(atSourceTime: CMTime(value: 30, timescale: 1))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "Quickstart", code: 8) }
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        guard abs(duration - 30) < 0.01 else { throw NSError(domain: "Quickstart", code: 9) }
        let generator = AVAssetImageGenerator(asset: asset)
        let frame = try await generator.image(at: .zero).image
        let preview = root.appendingPathComponent(".build/quickstart-video-first.png")
        if let destination = CGImageDestinationCreateWithURL(preview as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, frame, nil); CGImageDestinationFinalize(destination)
        }
        print("MP4: H.264, 1280×720, \(String(format: "%.2f", duration))s")
    }
}
