import CoreVideo
import UIKit
import Vision

/// What the photo analysis found.
struct PhotoAnalysis {
    /// Silhouette of the largest foreground object, nil if none was found.
    let shape: ShapeMeasurement?
    /// The silhouette's length in pixels of the analysed image, and that image's long side.
    var lengthPixels: Double?
    var imageLongSide: Double = 0
    /// Where the cartridges that compete for the measurement are, as fractions of the upright
    /// photo (0…1), the one measured first; empty when there is at most one.
    var candidates: [CGRect] = []
    /// The measured silhouette's rotated bounding box: four corners as fractions of the upright
    /// photo (x of the width, y of the height); nil if nothing was measured. Drawn as the frame,
    /// so it shows exactly what was matched.
    var outline: [CGPoint]?
    /// The silhouette is brass-coloured: a case, not a lead ball or pellet.
    var isBrass = false

    /// How many cartridges compete for the measurement.
    var objectCount: Int { max(1, candidates.count) }

    /// More than one cartridge in the photo: the user picks the one to identify.
    var hasSeveralObjects: Bool { candidates.count > 1 }

    /// Size from the silhouette and the LiDAR distance, if the photo was taken with depth.
    func size(depth: DepthScale?) -> Result<MeasuredSize, SizeFailure> {
        guard let shape, let lengthPixels else { return .failure(depth == nil ? .noDepth : .endView) }
        return SizeEstimator.estimate(lengthPixels: lengthPixels, aspect: shape.aspect, imageLongSide: imageLongSide, depth: depth)
    }
}

/// Runs Vision on a photo of the cartridge lying on its side: foreground segmentation for the silhouette.
enum PhotoAnalyzer {
    /// Photos are scaled down to this many pixels on the long side first; plenty for the shape.
    static let maxDimension: CGFloat = 1600
    /// Upper bound on silhouette points handed to the shape measurement.
    static let maxPoints = 40_000

    static func analyze(_ image: UIImage) async -> PhotoAnalysis {
        await Task.detached(priority: .userInitiated) { analyzeNow(image) }.value
    }

    /// Analyses only the cartridge in `candidate` (fractions of the photo, from `candidates`):
    /// the photo is cut down to a margin around it, so the others don't get in the way.
    static func analyze(_ image: UIImage, focusingOn candidate: CGRect) async -> PhotoAnalysis {
        await Task.detached(priority: .userInitiated) { analyzeNow(image, focusingOn: candidate) }.value
    }

    static func analyzeNow(_ image: UIImage, focusingOn candidate: CGRect) -> PhotoAnalysis {
        let region = focusRegion(candidate)
        let size = image.size
        let crop = CGRect(x: region.minX * size.width, y: region.minY * size.height,
                          width: region.width * size.width, height: region.height * size.height)
        let cropped = Self.cropped(image, to: region)
        var analysis = analyzeNow(cropped)
        // The size measurement compares pixels with the whole photo's long side, at the scale
        // the cut-out was analysed at.
        let scale = min(1, maxDimension / max(crop.width, crop.height))
        analysis.imageLongSide = Double(max(size.width, size.height) * scale)
        analysis.candidates = []
        // From the cut-out back to the whole photo.
        analysis.outline = analysis.outline?.map {
            CGPoint(x: region.minX + $0.x * region.width, y: region.minY + $0.y * region.height)
        }
        return analysis
    }

    /// The part of the photo inside `region` (fractions of the upright photo), upright.
    static func cropped(_ image: UIImage, to region: CGRect) -> UIImage {
        let size = image.size
        let crop = CGRect(x: region.minX * size.width, y: region.minY * size.height,
                          width: region.width * size.width, height: region.height * size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: crop.size, format: format).image { _ in
            image.draw(at: CGPoint(x: -crop.minX, y: -crop.minY))
        }
    }

    /// A candidate's box widened by half its larger side all round, kept inside the photo.
    static func focusRegion(_ candidate: CGRect) -> CGRect {
        let margin = max(candidate.width, candidate.height) / 2
        return candidate.insetBy(dx: -margin, dy: -margin).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    static func analyzeNow(_ image: UIImage) -> PhotoAnalysis {
        guard let cgImage = upright(image, maxSide: maxDimension) else { return PhotoAnalysis(shape: nil) }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // Not available on the simulator; then the colour cut-out below does the work.
        let maskRequest = VNGenerateForegroundInstanceMaskRequest()
        var measured: (shape: ShapeMeasurement, length: Double)?
        var candidates: [CGRect] = []
        var outline: [CGPoint]?
        let normalize = { (box: [Point]?) in
            box?.map { CGPoint(x: $0.x / Double(cgImage.width), y: $0.y / Double(cgImage.height)) }
        }
        let rgb = rgbImage(cgImage)
        var measuredPoints: [Point] = []
        if (try? handler.perform([maskRequest])) != nil, let observation = maskRequest.results?.first {
            let (found, step, boxes) = silhouette(of: observation, handler: handler)
            if let vision = measureSilhouette(found, step: step) {
                measured = (vision.shape, vision.length)
                candidates = boxes
                outline = normalize(vision.box)
                measuredPoints = vision.points
            }
        }
        // Vision found only the table, box or paper (or isn't available, on the simulator): take
        // the colour cut-out. Never instead of Vision's object: the cut-out also takes in shadows
        // and can pick a stone or a tool next to the cartridge (build 1042).
        if measured == nil, let rgb, let colour = ColorSegmenter.best(rgb) {
            let (sampled, step) = thinned(colour.points)
            if let fromColour = ShapeMatcher.measureWithLength(sampled, pixelSize: Double(step)) {
                measured = fromColour
                outline = normalize(ShapeMatcher.orientedBox(sampled, pixelSize: Double(step)))
                candidates = ColorSegmenter.competitors(rgb).map { normalized($0, width: rgb.width, height: rgb.height) }
                measuredPoints = sampled
            }
        }
        return PhotoAnalysis(shape: measured?.shape, lengthPixels: measured?.length,
                             imageLongSide: Double(max(cgImage.width, cgImage.height)),
                             candidates: candidates.count > 1 ? candidates : [], outline: outline,
                             isBrass: rgb.map { isBrass($0, points: measuredPoints) } ?? false)
    }

    /// The measurement of Vision's silhouette (`step`: pixels between the points): made
    /// mirror-symmetric first, so a shadow clinging to part of one side is left out.
    static func measureSilhouette(_ points: [Point], step: Int) -> (shape: ShapeMeasurement, length: Double, points: [Point], box: [Point]?)? {
        let pixelSize = Double(step)
        let trimmed = ShapeMatcher.mirrorTrimmed(points, pixelSize: pixelSize)
        guard let measured = ShapeMatcher.measureWithLength(trimmed, pixelSize: pixelSize) else { return nil }
        return (measured.shape, measured.length, trimmed, ShapeMatcher.orientedBox(trimmed, pixelSize: pixelSize))
    }

    /// How much red and green must each exceed blue, relative to it, for brass (yellow). Lead and
    /// nickel are grey (all three about equal). Copper is red with little green, so green must
    /// also be close to red.
    static let brassRedOverBlue: Float = 1.25
    static let brassGreenOverBlue: Float = 1.1
    static let brassGreenOfRed: Float = 0.75

    /// Whether the pixels at `points` are, on average, brass-coloured.
    static func isBrass(_ image: RGBImage, points: [Point]) -> Bool {
        var sum: [Float] = [0, 0, 0], n: Float = 0
        for p in points {
            let x = Int(p.x), y = Int(p.y)
            guard x >= 0, y >= 0, x < image.width, y < image.height else { continue }
            let i = (y * image.width + x) * 3
            for c in 0..<3 { sum[c] += image.pixels[i + c] }
            n += 1
        }
        guard n > 0, sum[2] > 0 else { return false }
        return sum[0] >= brassRedOverBlue * sum[2] && sum[1] >= brassGreenOverBlue * sum[2] && sum[1] >= brassGreenOfRed * sum[0]
    }

    /// The image scaled down and with its orientation applied, so pixels are upright.
    private static func upright(_ image: UIImage, maxSide: CGFloat) -> CGImage? {
        let longSide = max(image.size.width, image.size.height)
        guard longSide > 0 else { return nil }
        let factor = min(1, maxSide / longSide)
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

    /// Every how many pixels to sample an object's mask so it gives at most about `maxPoints` points.
    static func maskStep(objectPixels: Double) -> Int {
        max(1, Int((objectPixels / Double(maxPoints)).squareRoot().rounded(.up)))
    }

    /// A box in pixels of a `width` × `height` image as fractions of it.
    static func normalized(_ box: ColorSegmenter.Box, width: Int, height: Int) -> CGRect {
        CGRect(x: Double(box.x0) / Double(width), y: Double(box.y0) / Double(height),
               width: Double(box.x1 - box.x0 + 1) / Double(width), height: Double(box.y1 - box.y0 + 1) / Double(height))
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Pixels of the foreground instance that is the cartridge (see `SubjectPicker`), sampled every
    /// `step` pixels, and where the instances that compete with it are (fractions of the photo);
    /// empty if every instance is the table, a box or the paper.
    private static func silhouette(of observation: VNInstanceMaskObservation,
                                   handler: VNImageRequestHandler) -> (points: [Point], step: Int, boxes: [CGRect]) {
        let labels = observation.instanceMask
        var map: [Int] = []
        forEachPixel(labels, step: 1) { _, _, value in map.append(Int(value.rounded())) }
        let width = CVPixelBufferGetWidth(labels), height = CVPixelBufferGetHeight(labels)
        let pieces = map.count == width * height ? SubjectPicker.instances(labels: map, width: width) : []
        let instances = SubjectPicker.joiningParts(pieces, labels: map, width: width, height: height)
        guard let picked = SubjectPicker.pickInstance(instances, width: width, height: height),
              let mask = try? observation.generateScaledMaskForImage(forInstances: picked.labels, from: handler)
        else { return ([], 1, []) }
        // The step from the object's size, not the photo's: from the whole photo it was 7 pixels
        // at 1600 px, which left a handgun cartridge only 8 or 9 points wide.
        let scale = Double(CVPixelBufferGetWidth(mask) * CVPixelBufferGetHeight(mask)) / Double(width * height)
        let step = maskStep(objectPixels: Double(picked.count) * scale)
        var result: [Point] = []
        forEachPixel(mask, step: step) { x, y, value in
            if value > 0.5 { result.append(Point(x: Double(x), y: Double(y))) }
        }
        let boxes = SubjectPicker.competitors(instances, width: width, height: height).map {
            normalized($0.bounds, width: width, height: height)
        }
        return (result, step, boxes)
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
