import Foundation

/// A one-channel image (0…255), row by row.
struct GrayImage: Equatable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    /// The image turned by half a turn, so text that stood on its head reads upright.
    func rotatedHalfTurn() -> GrayImage {
        GrayImage(width: width, height: height, pixels: pixels.reversed())
    }

    /// Dark and light swapped.
    func inverted() -> GrayImage {
        GrayImage(width: width, height: height, pixels: pixels.map { 255 - $0 })
    }
}

/// Prepares a base photo for text recognition. A headstamp's letters run round the primer, each
/// turned a different way, and the case head often fills only part of the photo, so text
/// recognition on the plain photo reads nothing. Instead:
///
/// 1. Find the case head: the largest brass-coloured patch, or else the object the colour
///    segmentation finds, taken as a disc.
/// 2. Unroll the ring between primer and rim into a straight strip, so the letters stand in a row.
///    Letters may face outwards or inwards, so the strip is read both ways up.
enum HeadstampImage {
    /// The case head in the photo, in image pixels.
    struct Disc: Equatable {
        let cx: Double
        let cy: Double
        let radius: Double
    }

    /// Long side of the copy used to find the case head.
    static let locateSide = 400
    /// Smallest case head radius worth reading, in image pixels.
    static let minRadius = 20.0
    /// The ring with the letters, as fractions of the radius: inside is the primer, outside the rim's edge.
    static let innerRadius = 0.42
    static let outerRadius = 0.98
    /// The strip covers a bit more than one turn, so a word cut at the start is whole at the end.
    static let turns = 1.25
    /// Strips are scaled to at least this height, enough for text recognition.
    static let minStripHeight = 128.0

    /// Brass and copper: clearly more red and green than blue, unlike wood, paper or grey.
    static func isBrass(r: Float, g: Float, b: Float) -> Bool {
        r > 90 && r - b > 70 && g - b > 35 && r >= g
    }

    /// The case head, nil if the photo shows nothing that could be one.
    static func locate(_ image: RGBImage) -> Disc? {
        brassDisc(image) ?? segmentedDisc(image)
    }

    /// The largest brass-coloured patch (holes such as the primer filled), as a disc of the same area.
    static func brassDisc(_ image: RGBImage) -> Disc? {
        let f = max(1, Int((Double(max(image.width, image.height)) / Double(locateSide)).rounded(.up)))
        let small = ColorSegmenter.downsample(image, factor: f)
        let w = small.width, h = small.height
        var mask = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) {
            mask[i] = isBrass(r: small.pixels[i * 3], g: small.pixels[i * 3 + 1], b: small.pixels[i * 3 + 2])
        }
        guard let largest = ColorSegmenter.components(mask, width: w, height: h).max(by: { $0.count < $1.count }),
              largest.count >= 30 else { return nil }
        var patch = [Bool](repeating: false, count: w * h)
        for i in largest { patch[i] = true }
        let filled = ColorSegmenter.fillHoles(patch, width: w, height: h)
        var n = 0.0, sx = 0.0, sy = 0.0
        for i in 0..<(w * h) where filled[i] {
            n += 1; sx += Double(i % w); sy += Double(i / w)
        }
        let scale = Double(f)
        let disc = Disc(cx: (sx / n + 0.5) * scale, cy: (sy / n + 0.5) * scale, radius: (n / .pi).squareRoot() * scale)
        return disc.radius >= minRadius ? disc : nil
    }

    /// For nickel-plated or steel cases: the object the colour segmentation finds, as a disc.
    static func segmentedDisc(_ image: RGBImage) -> Disc? {
        guard let points = ColorSegmenter.segment(image), !points.isEmpty else { return nil }
        let n = Double(points.count)
        let disc = Disc(cx: points.reduce(0) { $0 + $1.x } / n + 0.5,
                        cy: points.reduce(0) { $0 + $1.y } / n + 0.5,
                        radius: (n / .pi).squareRoot())
        return disc.radius >= minRadius ? disc : nil
    }

    /// The ring between primer and rim unrolled into a strip: the top row is the outer edge,
    /// columns go round clockwise in the image. Brightness is stretched to the full range.
    static func unwrap(_ image: RGBImage, disc: Disc) -> GrayImage {
        let ring = disc.radius * (outerRadius - innerRadius)
        let scale = max(1, minStripHeight / ring)
        let height = max(1, Int((ring * scale).rounded()))
        let width = max(1, Int((2 * .pi * disc.radius * turns * scale).rounded()))
        var values = [Float](repeating: 0, count: width * height)
        for column in 0..<width {
            let angle = Double(column) / Double(width) * 2 * .pi * turns
            let cosA = cos(angle), sinA = sin(angle)
            for row in 0..<height {
                let r = disc.radius * (outerRadius - (outerRadius - innerRadius) * Double(row) / Double(height))
                values[row * width + column] = gray(image, x: disc.cx + r * cosA, y: disc.cy + r * sinA)
            }
        }
        return stretched(values, width: width, height: height)
    }

    /// Text recognition scales a long, thin strip down until the letters are too small to read, so the
    /// strip is cut into overlapping pieces `tileAspect` times as wide as high, each with a margin.
    static let tileAspect = 4

    static func tiles(_ strip: GrayImage) -> [GrayImage] {
        let h = strip.height, tileWidth = tileAspect * h, step = tileWidth / 2
        var starts = Array(stride(from: 0, to: max(1, strip.width - tileWidth + 1), by: max(1, step)))
        if let last = starts.last, last + tileWidth < strip.width { starts.append(strip.width - tileWidth) }
        return starts.map { padded(crop(strip, x: max(0, $0), width: min(tileWidth, strip.width))) }
    }

    /// Columns `x ..< x + width` of an image.
    static func crop(_ image: GrayImage, x: Int, width: Int) -> GrayImage {
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * image.height)
        for row in 0..<image.height {
            let start = row * image.width + x
            pixels += image.pixels[start..<start + width]
        }
        return GrayImage(width: width, height: image.height, pixels: pixels)
    }

    /// The image with a margin of a quarter of its height all round, in its median brightness.
    static func padded(_ image: GrayImage) -> GrayImage {
        let m = image.height / 4
        let fill = image.pixels.sorted()[image.pixels.count / 2]
        let width = image.width + 2 * m, height = image.height + 2 * m
        var pixels = [UInt8](repeating: fill, count: width * height)
        for row in 0..<image.height {
            for column in 0..<image.width {
                pixels[(row + m) * width + column + m] = image.pixels[row * image.width + column]
            }
        }
        return GrayImage(width: width, height: height, pixels: pixels)
    }

    /// Brightness at a point between pixel centres (bilinear); outside the image, the nearest edge pixel.
    static func gray(_ image: RGBImage, x: Double, y: Double) -> Float {
        let fx = x - 0.5, fy = y - 0.5
        let x0 = Int(fx.rounded(.down)), y0 = Int(fy.rounded(.down))
        let tx = Float(fx - Double(x0)), ty = Float(fy - Double(y0))
        func at(_ px: Int, _ py: Int) -> Float {
            let cx = min(max(px, 0), image.width - 1), cy = min(max(py, 0), image.height - 1)
            let i = (cy * image.width + cx) * 3
            return (image.pixels[i] + image.pixels[i + 1] + image.pixels[i + 2]) / 3
        }
        let top = at(x0, y0) * (1 - tx) + at(x0 + 1, y0) * tx
        let bottom = at(x0, y0 + 1) * (1 - tx) + at(x0 + 1, y0 + 1) * tx
        return top * (1 - ty) + bottom * ty
    }

    /// Values mapped so the 2nd and 98th percentiles become black and white.
    static func stretched(_ values: [Float], width: Int, height: Int) -> GrayImage {
        var low = ColorSegmenter.quantile(values, 0.02), high = ColorSegmenter.quantile(values, 0.98)
        // Mostly one colour (a small mark on a plain disc): stretch between darkest and brightest.
        if high - low < 1 { low = values.min() ?? 0; high = values.max() ?? 255 }
        let span = max(1, high - low)
        let pixels = values.map { UInt8(min(255, max(0, ($0 - low) / span * 255))) }
        return GrayImage(width: width, height: height, pixels: pixels)
    }
}
