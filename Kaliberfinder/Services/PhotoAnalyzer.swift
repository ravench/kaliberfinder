import CoreVideo
import UIKit
import Vision

/// What the photo analysis found.
struct PhotoAnalysis {
    /// Silhouette of the largest foreground object, nil if none was found.
    let shape: ShapeMeasurement?
    /// Text read from the photo (headstamp, box label).
    let texts: [String]
    /// The silhouette's length in pixels of the analysed image, and that image's long side.
    var lengthPixels: Double?
    var imageLongSide: Double = 0

    /// Size from the silhouette and the LiDAR distance, if the photo was taken with depth.
    func size(depth: DepthScale?) -> Result<MeasuredSize, SizeFailure> {
        guard let shape, let lengthPixels else { return .failure(depth == nil ? .noDepth : .endView) }
        return SizeEstimator.estimate(lengthPixels: lengthPixels, aspect: shape.aspect, imageLongSide: imageLongSide, depth: depth)
    }
}

/// Which photo of the two-shot flow is analysed.
enum PhotoKind {
    /// The cartridge lying on its side: shape and size only.
    case side
    /// The case head seen from below: only the headstamp text counts.
    case base

    /// Whether text read from this photo is used. A side photo is only read when it turned out
    /// to show a round end (someone photographed the base anyway); otherwise the shape counts.
    func readsText(shape: ShapeMeasurement?) -> Bool {
        switch self {
        case .base: true
        case .side: shape?.isEndView == true
        }
    }
}

/// Runs Vision on a photo: foreground segmentation for the silhouette, text recognition for the headstamp.
enum PhotoAnalyzer {
    /// Photos are scaled down to this many pixels on the long side first; plenty for the shape.
    static let maxDimension: CGFloat = 1600
    /// Upper bound on silhouette points handed to the shape measurement.
    static let maxPoints = 40_000

    static func analyze(_ image: UIImage, kind: PhotoKind = .side) async -> PhotoAnalysis {
        await Task.detached(priority: .userInitiated) { analyzeNow(image, kind: kind) }.value
    }

    static func analyzeNow(_ image: UIImage, kind: PhotoKind = .side) -> PhotoAnalysis {
        guard let cgImage = upright(image) else { return PhotoAnalysis(shape: nil, texts: []) }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // Not available on the simulator; then the colour cut-out below does the work.
        let maskRequest = VNGenerateForegroundInstanceMaskRequest()
        var measured: (shape: ShapeMeasurement, length: Double)?
        if kind == .side, (try? handler.perform([maskRequest])) != nil, let observation = maskRequest.results?.first {
            let (points, step) = silhouette(of: observation, handler: handler)
            measured = ShapeMatcher.measureWithLength(points, pixelSize: Double(step))
        }
        // Vision found only the table, box or paper: find the cartridge by its colour.
        if kind == .side, measured == nil, let rgb = rgbImage(cgImage), let points = ColorSegmenter.segment(rgb) {
            let (sampled, step) = thinned(points)
            measured = ShapeMatcher.measureWithLength(sampled, pixelSize: Double(step))
        }
        var texts: [String] = []
        if kind.readsText(shape: measured?.shape) {
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = false
            try? handler.perform([textRequest])
            texts = (textRequest.results ?? []).flatMap { $0.topCandidates(3).map(\.string) }
        }
        return PhotoAnalysis(shape: measured?.shape, texts: texts, lengthPixels: measured?.length,
                             imageLongSide: Double(max(cgImage.width, cgImage.height)))
    }

    /// The image scaled down and with its orientation applied, so pixels are upright.
    private static func upright(_ image: UIImage) -> CGImage? {
        let longSide = max(image.size.width, image.size.height)
        guard longSide > 0 else { return nil }
        let factor = min(1, maxDimension / longSide)
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }

    /// The image's pixels as RGB values.
    static func rgbImage(_ cgImage: CGImage) -> RGBImage? {
        let width = cgImage.width, height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? RGBImage(width: width, height: height, rgba: bytes) : nil
    }

    /// At most `maxPoints` of the points, keeping every `step`-th pixel in both directions.
    static func thinned(_ points: [Point]) -> (points: [Point], step: Int) {
        let step = max(1, Int((Double(points.count) / Double(maxPoints)).squareRoot().rounded(.up)))
        guard step > 1 else { return (points, 1) }
        return (points.filter { Int($0.x) % step == 0 && Int($0.y) % step == 0 }, step)
    }

    /// Pixels of the foreground instance that is the cartridge (see `SubjectPicker`), sampled every
    /// `step` pixels; empty if every instance is the table, a box or the paper.
    private static func silhouette(of observation: VNInstanceMaskObservation, handler: VNImageRequestHandler) -> (points: [Point], step: Int) {
        let labels = observation.instanceMask
        var map: [Int] = []
        forEachPixel(labels, step: 1) { _, _, value in map.append(Int(value.rounded())) }
        let width = CVPixelBufferGetWidth(labels), height = CVPixelBufferGetHeight(labels)
        guard map.count == width * height,
              let label = SubjectPicker.pick(SubjectPicker.instances(labels: map, width: width), width: width, height: height),
              let mask = try? observation.generateScaledMaskForImage(forInstances: IndexSet(integer: label), from: handler)
        else { return ([], 1) }
        let pixels = CVPixelBufferGetWidth(mask) * CVPixelBufferGetHeight(mask)
        let step = max(1, Int((Double(pixels) / Double(maxPoints)).squareRoot().rounded(.up)))
        var result: [Point] = []
        forEachPixel(mask, step: step) { x, y, value in
            if value > 0.5 { result.append(Point(x: Double(x), y: Double(y))) }
        }
        return (result, step)
    }

    /// Calls `body` with the value of every `step`-th pixel of a one-channel buffer
    /// (8-bit values as is, 32-bit float values as is).
    private static func forEachPixel(_ buffer: CVPixelBuffer, step: Int, _ body: (Int, Int, Float) -> Void) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let isFloat = CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float
        for y in stride(from: 0, to: height, by: step) {
            let row = base.advanced(by: y * rowBytes)
            for x in stride(from: 0, to: width, by: step) {
                let value = isFloat ? row.load(fromByteOffset: x * 4, as: Float.self) : Float(row.load(fromByteOffset: x, as: UInt8.self))
                body(x, y, value)
            }
        }
    }
}
