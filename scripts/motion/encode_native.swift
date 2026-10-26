import AppKit
import AVFoundation

// Encode native offscreen captures without drawing or recreating any controls.
@main struct EncodeNative {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("encode-native <frames-directory> <output.mp4>") }
        let frames = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 2000, AVVideoHeightKey: 1480,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000, AVVideoMaxKeyFrameIntervalKey: 15]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 2000, kCVPixelBufferHeightKey as String: 1480,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NSError(domain: "NativeFilm", code: 1) }
        writer.startSession(atSourceTime: .zero)
        for index in 0..<450 {
            try autoreleasepool {
                while !input.isReadyForMoreMediaData {
                    if writer.status == .failed { throw writer.error ?? NSError(domain: "NativeFilm", code: 2) }
                    Thread.sleep(forTimeInterval: 0.005)
                }
                let url = frames.appendingPathComponent(String(format: "%04d.png", index))
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Missing frame \(index)") }
                var buffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer) == kCVReturnSuccess, let buffer else { fatalError("Pixel allocation failed") }
                CVPixelBufferLockBaseAddress(buffer, [])
                let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 2000, height: 1480, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: 2000, height: 1480))
                CVPixelBufferUnlockBaseAddress(buffer, [])
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 15)) else { throw writer.error ?? NSError(domain: "NativeFilm", code: 3) }
            }
        }
        writer.endSession(atSourceTime: CMTime(seconds: 30, preferredTimescale: 600))
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else { throw writer.error ?? NSError(domain: "NativeFilm", code: 4) }
        print("Encoded actual native UI: 30 seconds, 2000x1480, 15 fps")
    }
}
