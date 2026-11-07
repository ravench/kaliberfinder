import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// What the photo analysis found.
struct PhotoAnalysis {
    /// Silhouette of the largest foreground object, nil if none was found.
    let shape: ShapeMeasurement?
    /// The silhouette's length in pixels of the analysed image, and the whole photo's long side at
    /// that image's scale (more than the image's own after a look at a part, see `inPhoto`).
    var lengthPixels: Double?
    var imageLongSide: Double = 0
    /// Where the cartridges that compete for the measurement are, as fractions of the upright
    /// photo (0…1), the one measured first; empty when there is at most one.
    var candidates: [CGRect] = []
    /// The measured silhouette's rotated bounding box: four corners as fractions of the upright
    /// photo (x of the width, y of the height); nil if nothing was measured. Drawn as the frame,
    /// so it shows exactly what was matched.
    var outline: [CGPoint]?
    /// The measured silhouette's outline (detected bullet as a nose curve up to the case mouth, neck
    /// and taper), in the same fractions as `outline`; drawn instead of the box when there is one.
    var contour: ShapeContour?
    /// The silhouette is brass-coloured: a case, not a lead ball or pellet.
    var isBrass = false
    /// The silhouette is the colour cut-out's: Vision found no cartridge.
    var byColour = false

    /// How many cartridges compete for the measurement.
    var objectCount: Int { max(1, candidates.count) }

    /// More than one cartridge in the photo: the user picks the one to identify.
    var hasSeveralObjects: Bool { candidates.count > 1 }

    /// Size from the silhouette and the LiDAR distance, if the photo was taken with depth: the length
    /// at the axis's height, without the ends' rise (`EndRise`) for the part `mode` sees.
    func size(depth: DepthScale?, mode: ScanMode = .auto) -> Result<MeasuredSize, SizeFailure> {
        guard let shape, let lengthPixels else { return .failure(depth == nil ? .noDepth : .endView) }
        let rise = endRise(depth: depth, mode: mode)
        return SizeEstimator.estimate(lengthPixels: lengthPixels / rise, aspect: shape.aspect / rise, imageLongSide: imageLongSide, depth: depth)
    }
}

/// Runs Vision on a photo of the cartridge lying on its side: foreground segmentation for the silhouette.
enum PhotoAnalyzer {
    /// Photos are scaled down to this many pixels on the long side first; plenty for the shape.
    static let maxDimension: CGFloat = 1600
    /// Upper bound on silhouette points handed to the shape measurement.
    static let maxPoints = 40_000

    /// A candidate's box widened by half its larger side all round, kept inside the photo.
    static func focusRegion(_ candidate: CGRect) -> CGRect {
        let margin = max(candidate.width, candidate.height) / 2
        return candidate.insetBy(dx: -margin, dy: -margin).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// The analysis of an upright photo at most `maxDimension` pixels long, as on the phone:
    /// Vision's object, or the colour cut-out where Vision finds none.
    static func analyzeNow(_ cgImage: CGImage) -> PhotoAnalysis {
        analysis(of: cgImage, vision: visionResult(of: cgImage))
    }

    // MARK: - Second look

    /// The second look leaves out photos where the cartridge's region is at least this
    /// share of the photo both ways: cutting it out gains next to nothing.
    static let secondLookUpTo = 0.9

    /// Where the second look analyses the photo: the frame the first look measured (`outline`), with
    /// the margin `focusRegion` gives a picked cartridge. Nil when nothing was measured, when several
    /// cartridges compete (the picked one gets its own look), or when the region is nearly the whole photo.
    ///
    /// The first look sees the photo scaled to `maxDimension` pixels, and Vision's mask covers it with
    /// only about 512 × 512 labels: a .45 ACP case is some 20 labels wide, and its ends come out
    /// rounded. That shortens the rim, hides the flat case mouth and blurs the neck. Cut out of the
    /// full-size photo, the same cartridge fills the mask several times over.
    static func secondLookRegion(of first: PhotoAnalysis) -> CGRect? {
        guard first.shape != nil, !first.hasSeveralObjects, let outline = first.outline,
              let region = focusRegion(around: outline), region.width < secondLookUpTo || region.height < secondLookUpTo else { return nil }
        return region
    }

    /// `focusRegion` of the box around the frame `outline` (fractions of the photo); nil for no frame.
    static func focusRegion(around outline: [CGPoint]) -> CGRect? {
        guard let minX = outline.map(\.x).min(), let maxX = outline.map(\.x).max(),
              let minY = outline.map(\.y).min(), let maxY = outline.map(\.y).max() else { return nil }
        let region = focusRegion(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
        return region.isEmpty ? nil : region
    }

    /// An analysis of the part `region` of a photo (fractions of the photo, which is `photoSize`
    /// pixels upright), cut out at full size and analysed at up to `maxDimension` pixels, as one of the
    /// whole photo: frames in fractions of the photo, and the long side the size measurement compares
    /// pixels with at the scale the part was analysed at. A part has no competing cartridges of its own.
    static func inPhoto(_ part: PhotoAnalysis, region: CGRect, photoSize: CGSize) -> PhotoAnalysis {
        var analysis = part
        let cropLongSide = max(region.width * photoSize.width, region.height * photoSize.height)
        let scale = min(1, maxDimension / max(1, cropLongSide))
        analysis.imageLongSide = max(photoSize.width, photoSize.height) * scale
        analysis.candidates = []
        let toPhoto = { (p: CGPoint) in CGPoint(x: region.minX + p.x * region.width, y: region.minY + p.y * region.height) }
        analysis.outline = part.outline?.map(toPhoto)
        analysis.contour = part.contour?.map(toPhoto)
        return analysis
    }

    /// The first look's analysis, improved by the second look's (`inPhoto` of the part at
    /// `secondLookRegion`) where Vision found the same cartridge there: its frame's centre lies in the
    /// first look's frame. The colour cut-out of the part never replaces anything: it can pick a piece of
    /// the cartridge, such as a case without its neck (simulator screenshot of #88, 2026-11-07), and never
    /// replaces Vision's object (see `analysis(of:vision:)`). The cartridges competing for the
    /// measurement stay the first look's.
    static func secondLook(_ first: PhotoAnalysis, then second: PhotoAnalysis) -> PhotoAnalysis {
        guard second.shape != nil, !second.byColour, let outline = second.outline, !outline.isEmpty,
              let frame = first.outline, frame.count == 4 else { return first }
        let centre = CGPoint(x: outline.map(\.x).reduce(0, +) / Double(outline.count),
                             y: outline.map(\.y).reduce(0, +) / Double(outline.count))
        guard contains(frame, centre) else { return first }
        var analysis = second
        analysis.candidates = first.candidates
        return analysis
    }

    /// Whether the convex quadrilateral `corners` (in order) contains `p`.
    static func contains(_ corners: [CGPoint], _ p: CGPoint) -> Bool {
        let crossings = corners.indices.map { i -> Double in
            let a = corners[i], b = corners[(i + 1) % corners.count]
            return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
        }
        return crossings.allSatisfy { $0 >= 0 } || crossings.allSatisfy { $0 <= 0 }
    }

    /// Vision's foreground object in an upright photo (see `SubjectPicker`); nil when Vision finds
    /// none, only the table, box or paper, or isn't available (the simulator).
    static func visionResult(of cgImage: CGImage) -> VisionResult? {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let maskRequest = VNGenerateForegroundInstanceMaskRequest()
        guard (try? handler.perform([maskRequest])) != nil, let observation = maskRequest.results?.first else { return nil }
        var result = visionResult(silhouette(of: observation, handler: handler, imagePixels: cgImage.width * cgImage.height),
                                  width: cgImage.width, height: cgImage.height)
        let labels = observation.instanceMask
        result?.maskPixel = maskPixel(image: (cgImage.width, cgImage.height),
                                      mask: (CVPixelBufferGetWidth(labels), CVPixelBufferGetHeight(labels)))
        return result
    }

    /// The size of a pixel of Vision's instance mask (`mask` pixels) in the photo (`image` pixels): its
    /// longer side, as the mask is square whatever the photo's shape.
    static func maskPixel(image: (width: Int, height: Int), mask: (width: Int, height: Int)) -> Double {
        max(Double(image.width) / Double(max(1, mask.width)), Double(image.height) / Double(max(1, mask.height)))
    }

    /// The analysis of an upright photo with Vision's object `vision` (`visionResult`), or with
    /// the colour cut-out when that is nil. The colour test for brass uses the photo either way.
    static func analysis(of cgImage: CGImage, vision: VisionResult?) -> PhotoAnalysis {
        let rgb = rgbImage(cgImage)
        var vision = vision
        // Vision often leaves out the cartridge's dark side: give it back (see `DarkSide`).
        if let found = vision, let rgb, let restored = DarkSide.restored(found.raw, step: found.step, maskPixel: found.maskPixel, photo: rgb),
           var again = visionResult((restored, found.step, found.candidates), width: cgImage.width, height: cgImage.height) {
            again.maskPixel = found.maskPixel
            debugLog(String(format: "  DS restored: aspect %.3f -> %.3f (%dx%d)", found.shape.aspect, again.shape.aspect, cgImage.width, cgImage.height))
            vision = again
        } else if let found = vision {
            debugLog(String(format: "  DS kept: aspect %.3f (%dx%d)", found.shape.aspect, cgImage.width, cgImage.height))
        }
        var measured: (shape: ShapeMeasurement, length: Double)? = vision.map { ($0.shape, $0.length) }
        var candidates = vision?.candidates ?? []
        var outline = vision?.outline
        var contour = vision?.contour
        var measuredPoints = vision?.points ?? []
        let normalize = { (box: [Point]?) in
            box?.map { CGPoint(x: $0.x / Double(cgImage.width), y: $0.y / Double(cgImage.height)) }
        }
        let fraction = { (p: CGPoint) in CGPoint(x: p.x / Double(cgImage.width), y: p.y / Double(cgImage.height)) }
        // Vision's outline again with the photo's colours, for the case mouth.
        if let vision, let rgb, let box = vision.box {
            contour = ShapeContour.polygon(vision.points, pixelSize: Double(vision.step), shape: vision.shape, box: box, photo: rgb)?.map(fraction)
        }
        // Vision found only the table, box or paper (or isn't available, on the simulator): take
        // the colour cut-out. Never instead of Vision's object: the cut-out also takes in shadows
        // and can pick a stone or a tool next to the cartridge (build 1042).
        if measured == nil, let rgb, let colour = ColorSegmenter.best(rgb) {
            let (sampled, step) = thinned(colour.points)
            if let fromColour = ShapeMatcher.measureWithLength(sampled, pixelSize: Double(step)) {
                measured = fromColour
                let box = ShapeMatcher.orientedBox(sampled, pixelSize: Double(step))
                outline = normalize(box)
                contour = box.flatMap { ShapeContour.polygon(sampled, pixelSize: Double(step), shape: fromColour.shape, box: $0, photo: rgb) }?.map(fraction)
                candidates = ColorSegmenter.competitors(rgb).map { normalized($0, width: rgb.width, height: rgb.height) }
                measuredPoints = sampled
            }
        }
        return PhotoAnalysis(shape: measured?.shape, lengthPixels: measured?.length,
                             imageLongSide: Double(max(cgImage.width, cgImage.height)),
                             candidates: candidates.count > 1 ? candidates : [], outline: outline, contour: contour,
                             isBrass: rgb.map { isBrass($0, points: measuredPoints) } ?? false,
                             byColour: vision == nil && measured != nil)
    }

    /// What the analysis takes from Vision's silhouette of the cartridge.
    struct VisionResult {
        let shape: ShapeMeasurement
        let length: Double
        /// The measured points: the silhouette made mirror-symmetric (`measureSilhouette`).
        let points: [Point]
        /// The silhouette as Vision found it.
        let raw: [Point]
        /// A pixel of Vision's instance mask in photo pixels: the mask is coarser than the photo.
        var maskPixel = 1.0
        let candidates: [CGRect]
        let outline: [CGPoint]?
        /// Without the photo's colours (see `analysis(of:vision:)`).
        let contour: ShapeContour?
        /// The silhouette's rotated box in pixels and the pixels between its `points`.
        let box: [Point]?
        let step: Int
    }

    /// Measurement, frame and outline of a silhouette in a `width` × `height` photo (see
    /// `silhouette`); nil when it can't be measured.
    static func visionResult(_ found: (points: [Point], step: Int, boxes: [CGRect]), width: Int, height: Int) -> VisionResult? {
        guard let vision = measureSilhouette(found.points, step: found.step) else { return nil }
        let fraction = { (p: CGPoint) in CGPoint(x: p.x / Double(width), y: p.y / Double(height)) }
        let contour = vision.box.flatMap { ShapeContour.polygon(vision.points, pixelSize: Double(found.step), shape: vision.shape, box: $0) }
        return VisionResult(shape: vision.shape, length: vision.length, points: vision.points, raw: found.points, candidates: found.boxes,
                            outline: vision.box?.map { fraction(CGPoint(x: $0.x, y: $0.y)) }, contour: contour?.map(fraction),
                            box: vision.box, step: found.step)
    }

    /// The phone's path on a stored Vision instance mask (a training capture or golden shot): the
    /// same subject picking, measurement, frame and neck as `analyzeNow`, without Vision and without
    /// the photo (so also without `DarkSide`, which needs it), so it runs on the simulator. `labels`
    /// is Vision's instance mask (`mask` pixels, 0 = background) over the upright photo as analysed
    /// (`image` pixels, see `maxDimension`).
    /// `isBrass` comes from the phone: it needs the photo's colours.
    static func analyze(instanceLabels labels: [UInt8], mask: (width: Int, height: Int), image: (width: Int, height: Int),
                        isBrass: Bool) -> PhotoAnalysis {
        let longSide = Double(max(image.width, image.height))
        guard let vision = visionResult(instanceLabels: labels, mask: mask, image: image) else {
            return PhotoAnalysis(shape: nil, imageLongSide: longSide, isBrass: isBrass)
        }
        return PhotoAnalysis(shape: vision.shape, lengthPixels: vision.length, imageLongSide: longSide,
                             candidates: vision.candidates.count > 1 ? vision.candidates : [],
                             outline: vision.outline, contour: vision.contour, isBrass: isBrass)
    }

    /// Vision's object in a stored instance mask, as `visionResult(of:)` finds it in the photo.
    static func visionResult(instanceLabels labels: [UInt8], mask: (width: Int, height: Int),
                             image: (width: Int, height: Int)) -> VisionResult? {
        let (width, height) = mask, (imageWidth, imageHeight) = image
        let map = labels.map(Int.init)
        let found = silhouette(labels: map, width: width, height: height, imagePixels: imageWidth * imageHeight) { picked, step in
            // The label nearest each sampled photo pixel, as Vision scales the mask to the photo.
            var points: [Point] = []
            for y in stride(from: 0, to: imageHeight, by: step) {
                let row = min(height - 1, (2 * y + 1) * height / (2 * imageHeight)) * width
                for x in stride(from: 0, to: imageWidth, by: step)
                where picked.contains(map[row + min(width - 1, (2 * x + 1) * width / (2 * imageWidth))]) {
                    points.append(Point(x: Double(x), y: Double(y)))
                }
            }
            return points
        }
        var result = visionResult(found, width: imageWidth, height: imageHeight)
        result?.maskPixel = maskPixel(image: image, mask: mask)
        return result
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
    private static func silhouette(of observation: VNInstanceMaskObservation, handler: VNImageRequestHandler,
                                   imagePixels: Int) -> (points: [Point], step: Int, boxes: [CGRect]) {
        let labels = observation.instanceMask
        var map: [Int] = []
        forEachPixel(labels, step: 1) { _, _, value in map.append(Int(value.rounded())) }
        let width = CVPixelBufferGetWidth(labels), height = CVPixelBufferGetHeight(labels)
        return silhouette(labels: map, width: width, height: height, imagePixels: imagePixels) { picked, step in
            guard let mask = try? observation.generateScaledMaskForImage(forInstances: picked, from: handler) else { return nil }
            var result: [Point] = []
            forEachPixel(mask, step: step) { x, y, value in
                if value > 0.5 { result.append(Point(x: Double(x), y: Double(y))) }
            }
            return result
        }
    }

    /// The cartridge among Vision's foreground instances (`labels`, `width` × `height`, 0 =
    /// background): `mask` gives the picked labels' pixels in the photo (`imagePixels` of them),
    /// sampled every `step` pixels. Also where the instances competing with it are.
    static func silhouette(labels map: [Int], width: Int, height: Int, imagePixels: Int,
                           mask: (_ labels: IndexSet, _ step: Int) -> [Point]?) -> (points: [Point], step: Int, boxes: [CGRect]) {
        let pieces = map.count == width * height ? SubjectPicker.instances(labels: map, width: width) : []
        let instances = SubjectPicker.joiningParts(pieces, labels: map, width: width, height: height)
        guard let picked = SubjectPicker.pickInstance(instances, width: width, height: height) else { return ([], 1, []) }
        // The step from the object's size, not the photo's: from the whole photo it was 7 pixels
        // at 1600 px, which left a handgun cartridge only 8 or 9 points wide.
        let scale = Double(imagePixels) / Double(width * height)
        let step = maskStep(objectPixels: Double(picked.count) * scale)
        guard let points = mask(picked.labels, step) else { return ([], 1, []) }
        let boxes = SubjectPicker.competitors(instances, width: width, height: height).map {
            normalized($0.bounds, width: width, height: height)
        }
        return (points, step, boxes)
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
