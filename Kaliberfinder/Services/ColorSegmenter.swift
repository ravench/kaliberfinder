import Foundation

/// An image as plain RGB values (0…255), row by row, so the segmentation can be tested without UIKit.
struct RGBImage {
    let width: Int
    let height: Int
    /// Three values per pixel: red, green, blue.
    let pixels: [Float]

    init(width: Int, height: Int, pixels: [Float]) {
        precondition(pixels.count == width * height * 3)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// From 8-bit RGBA bytes, as a CGContext draws them.
    init(width: Int, height: Int, rgba: [UInt8]) {
        var p = [Float](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            p[i * 3] = Float(rgba[i * 4])
            p[i * 3 + 1] = Float(rgba[i * 4 + 1])
            p[i * 3 + 2] = Float(rgba[i * 4 + 2])
        }
        self.init(width: width, height: height, pixels: p)
    }
}

/// Finds a cartridge in a photo by colour (SCAN-05), for photos where Vision's foreground mask
/// picks the table, the box or the sheet of paper instead.
///
/// 1. Locate: in a small copy, pixels whose colour differs from their surroundings (the cartridge)
///    form a cluster near the centre that doesn't touch the frame.
/// 2. Cut out: around that cluster, pixels whose colour (not brightness, so shadows don't count)
///    differs from the background form the cartridge; holes from reflections are filled.
enum ColorSegmenter {
    /// Long side of the copy used to locate the cartridge.
    static let locateSide = 800
    /// Share of the most contrasting pixels kept when locating.
    static let locateQuantile: Float = 0.99
    /// Fewest pixels a silhouette may have.
    static let minPixels = 50

    struct Box: Equatable {
        var x0: Int, y0: Int, x1: Int, y1: Int
    }

    /// Pixels of the cartridge (x, y in image pixels), nil if nothing stands out.
    static func segment(_ image: RGBImage) -> [Point]? {
        guard let box = locate(image) else { return nil }
        let longSide = Double(max(image.width, image.height))
        var pad = max(Double(max(box.x1 - box.x0, box.y1 - box.y0)) * 0.6, longSide / 16)
        for _ in 0..<3 {
            let crop = Box(x0: max(0, box.x0 - Int(pad)), y0: max(0, box.y0 - Int(pad)),
                           x1: min(image.width, box.x1 + Int(pad)), y1: min(image.height, box.y1 + Int(pad)))
            guard let cut = cutOut(image, crop) else { return nil }
            if !cut.runsOff { return cut.points }
            // The object runs off the crop: look wider.
            pad *= 2
        }
        return nil
    }

    // MARK: - Locate

    /// Where the cartridge is, in image pixels.
    static func locate(_ image: RGBImage) -> Box? {
        guard let found = clusters(image) else { return nil }
        let w = found.width, h = found.height, f = found.factor
        guard let best = found.clusters.max(by: { centreScore($0, width: w, height: h) < centreScore($1, width: w, height: h) })
        else { return nil }
        let b = bounds(best, width: w)
        return Box(x0: b.x0 * f, y0: b.y0 * f, x1: min(image.width, (b.x1 + 1) * f), y1: min(image.height, (b.y1 + 1) * f))
    }

    /// How many objects stand out like a cartridge: clusters at least
    /// `SubjectPicker.sameSizeShare` the size of the largest; 0 if nothing stands out.
    static func objectCount(_ image: RGBImage) -> Int {
        SubjectPicker.similar(clusters(image)?.clusters.map(\.count) ?? [])
    }

    /// Clusters of pixels that stand out by colour and don't touch the frame, in a copy of the
    /// photo scaled down by `factor` to `width` × `height`.
    private static func clusters(_ image: RGBImage) -> (clusters: [[Int]], width: Int, height: Int, factor: Int)? {
        let f = max(1, Int((Double(max(image.width, image.height)) / Double(locateSide)).rounded(.up)))
        // Colour only, so shadow edges don't stand out.
        let small = chroma(downsample(image, factor: f))
        let w = small.width, h = small.height
        guard w > 2, h > 2 else { return nil }
        let blurred = boxBlur(small.pixels, width: w, height: h, channels: 3, radius: max(8, max(w, h) / 32))
        var contrast = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            var sum: Float = 0
            for c in 0..<3 {
                let d = small.pixels[i * 3 + c] - blurred[i * 3 + c]
                sum += d * d
            }
            contrast[i] = sum.squareRoot()
        }
        let threshold = quantile(contrast, locateQuantile)
        // Close small gaps, so the pieces of one cartridge form one cluster.
        let strong = contrast.map { $0 > threshold ? Float(1) : 0 }
        let mask = boxBlur(strong, width: w, height: h, channels: 1, radius: 2).map { $0 > 0 }
        let candidates = components(mask, width: w, height: h).filter {
            $0.count >= 20 && !touchesBorder($0, width: w, height: h)
        }
        return (candidates, w, h, f)
    }

    /// Size of a cluster, weighted down the further it is from the centre of the photo.
    static func centreScore(_ component: [Int], width w: Int, height h: Int) -> Double {
        var sx = 0.0, sy = 0.0
        for p in component { sx += Double(p % w); sy += Double(p / w) }
        let n = Double(component.count)
        let dx = (sx / n - Double(w) / 2) / (Double(w) / 2)
        let dy = (sy / n - Double(h) / 2) / (Double(h) / 2)
        let off = min(1, (dx * dx + dy * dy).squareRoot() / 2.0.squareRoot())
        return n * (1 - off) * (1 - off)
    }

    // MARK: - Cut out

    /// The largest patch inside `crop` whose colour differs from the crop's edge. `runsOff` is
    /// true when every such patch touches the edge, i.e. the crop is too small.
    static func cutOut(_ image: RGBImage, _ crop: Box) -> (points: [Point], runsOff: Bool)? {
        let w = crop.x1 - crop.x0, h = crop.y1 - crop.y0
        guard w > 6, h > 6 else { return nil }
        var cropped = [Float](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            let src = ((crop.y0 + y) * image.width + crop.x0) * 3
            for i in 0..<(w * 3) { cropped[y * w * 3 + i] = image.pixels[src + i] }
        }
        let colours = chroma(RGBImage(width: w, height: h, pixels: cropped)).pixels
        // Background colour: the median along the crop's edge.
        var ring: [[Float]] = [[], [], []]
        for y in 0..<h {
            for x in 0..<w where y < 3 || y >= h - 3 || x < 3 || x >= w - 3 {
                for c in 0..<3 { ring[c].append(colours[(y * w + x) * 3 + c]) }
            }
        }
        let background = ring.map { quantile($0, 0.5) }
        var distance = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            var sum: Float = 0
            for c in 0..<3 {
                let d = colours[i * 3 + c] - background[c]
                sum += d * d
            }
            distance[i] = sum.squareRoot()
        }
        let threshold = otsu(distance)
        let patches = components(distance.map { $0 > threshold }, width: w, height: h).filter { $0.count >= minPixels }
        let inner = patches.filter { !touchesBorder($0, width: w, height: h) }
        guard let best = (inner.isEmpty ? patches : inner).max(by: { $0.count < $1.count }) else { return nil }
        var mask = [Bool](repeating: false, count: w * h)
        for p in best { mask[p] = true }
        mask = fillHoles(mask, width: w, height: h)
        var points: [Point] = []
        for i in 0..<(w * h) where mask[i] {
            points.append(Point(x: Double(crop.x0 + i % w), y: Double(crop.y0 + i / w)))
        }
        return (points, inner.isEmpty)
    }

    // MARK: - Helpers

    /// Colour without brightness: each channel divided by the pixel's sum (plus a little, so
    /// dark noise doesn't blow up), scaled to 0…255. A shadow keeps the colour of what it falls on.
    static func chroma(_ image: RGBImage) -> RGBImage {
        var p = image.pixels
        for i in 0..<(image.width * image.height) {
            let scale = 255 / (p[i * 3] + p[i * 3 + 1] + p[i * 3 + 2] + 30)
            for c in 0..<3 { p[i * 3 + c] *= scale }
        }
        return RGBImage(width: image.width, height: image.height, pixels: p)
    }

    /// Averages `factor` × `factor` blocks.
    static func downsample(_ image: RGBImage, factor f: Int) -> RGBImage {
        guard f > 1 else { return image }
        let w = image.width / f, h = image.height / f
        var p = [Float](repeating: 0, count: w * h * 3)
        let n = Float(f * f)
        for y in 0..<h {
            for x in 0..<w {
                for c in 0..<3 {
                    var sum: Float = 0
                    for dy in 0..<f {
                        for dx in 0..<f { sum += image.pixels[((y * f + dy) * image.width + x * f + dx) * 3 + c] }
                    }
                    p[(y * w + x) * 3 + c] = sum / n
                }
            }
        }
        return RGBImage(width: w, height: h, pixels: p)
    }

    /// Mean over a (2r+1)² square around each pixel, clipped at the edges, via an integral image.
    static func boxBlur(_ values: [Float], width w: Int, height h: Int, channels: Int, radius r: Int) -> [Float] {
        let stride = w + 1
        var result = [Float](repeating: 0, count: values.count)
        for c in 0..<channels {
            var integral = [Double](repeating: 0, count: (w + 1) * (h + 1))
            for y in 0..<h {
                var row = 0.0
                for x in 0..<w {
                    row += Double(values[(y * w + x) * channels + c])
                    integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + row
                }
            }
            for y in 0..<h {
                let y0 = max(0, y - r), y1 = min(h, y + r + 1)
                for x in 0..<w {
                    let x0 = max(0, x - r), x1 = min(w, x + r + 1)
                    let sum = integral[y1 * stride + x1] - integral[y0 * stride + x1] - integral[y1 * stride + x0] + integral[y0 * stride + x0]
                    result[(y * w + x) * channels + c] = Float(sum / Double((y1 - y0) * (x1 - x0)))
                }
            }
        }
        return result
    }

    /// 4-connected patches of true pixels, as pixel indices.
    static func components(_ mask: [Bool], width w: Int, height h: Int) -> [[Int]] {
        var label = [Bool](repeating: false, count: mask.count)
        var result: [[Int]] = []
        for start in mask.indices where mask[start] && !label[start] {
            var patch = [start]
            label[start] = true
            var i = 0
            while i < patch.count {
                let p = patch[i]
                i += 1
                let x = p % w, y = p / w
                for (q, ok) in [(p - 1, x > 0), (p + 1, x < w - 1), (p - w, y > 0), (p + w, y < h - 1)] where ok && mask[q] && !label[q] {
                    label[q] = true
                    patch.append(q)
                }
            }
            result.append(patch)
        }
        return result
    }

    static func touchesBorder(_ component: [Int], width w: Int, height h: Int) -> Bool {
        component.contains { p in
            let x = p % w, y = p / w
            return x == 0 || y == 0 || x == w - 1 || y == h - 1
        }
    }

    static func bounds(_ component: [Int], width w: Int) -> Box {
        var b = Box(x0: Int.max, y0: Int.max, x1: Int.min, y1: Int.min)
        for p in component {
            b.x0 = min(b.x0, p % w); b.x1 = max(b.x1, p % w)
            b.y0 = min(b.y0, p / w); b.y1 = max(b.y1, p / w)
        }
        return b
    }

    /// Clears everything not reachable from the edge through false pixels, i.e. fills holes.
    static func fillHoles(_ mask: [Bool], width w: Int, height h: Int) -> [Bool] {
        var outside = [Bool](repeating: false, count: mask.count)
        var queue: [Int] = []
        for i in mask.indices where !mask[i] {
            let x = i % w, y = i / w
            if x == 0 || y == 0 || x == w - 1 || y == h - 1 {
                outside[i] = true
                queue.append(i)
            }
        }
        var i = 0
        while i < queue.count {
            let p = queue[i]
            i += 1
            let x = p % w, y = p / w
            for (q, ok) in [(p - 1, x > 0), (p + 1, x < w - 1), (p - w, y > 0), (p + w, y < h - 1)] where ok && !mask[q] && !outside[q] {
                outside[q] = true
                queue.append(q)
            }
        }
        return outside.map { !$0 }
    }

    /// The value below which the share `q` of the values lies.
    static func quantile(_ values: [Float], _ q: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Float(sorted.count) * q))]
    }

    /// Otsu's threshold: splits the values into two groups that are as distinct as possible.
    static func otsu(_ values: [Float]) -> Float {
        var histogram = [Double](repeating: 0, count: 256)
        for v in values { histogram[min(255, max(0, Int(v)))] += 1 }
        let total = Double(values.count)
        let sumAll = histogram.enumerated().reduce(0.0) { $0 + Double($1.offset) * $1.element }
        var weightBelow = 0.0, sumBelow = 0.0, best = -1.0, threshold = 0
        for t in 0..<256 {
            weightBelow += histogram[t]
            guard weightBelow > 0 else { continue }
            let weightAbove = total - weightBelow
            if weightAbove <= 0 { break }
            sumBelow += Double(t) * histogram[t]
            let meanBelow = sumBelow / weightBelow, meanAbove = (sumAll - sumBelow) / weightAbove
            let between = weightBelow * weightAbove * (meanBelow - meanAbove) * (meanBelow - meanAbove)
            if between > best { best = between; threshold = t }
        }
        return Float(threshold)
    }
}

/// Chooses which of Vision's foreground instances is the cartridge (SCAN-05). Vision often takes
/// the biggest thing in the photo, such as the table, an ammunition box or the sheet of paper,
/// as the subject; a cartridge lies inside the frame and covers only a small part of it.
enum SubjectPicker {
    struct Instance: Equatable {
        let label: Int
        var count = 0
        var bounds = ColorSegmenter.Box(x0: Int.max, y0: Int.max, x1: Int.min, y1: Int.min)
    }

    /// Largest share of the photo a cartridge may cover.
    static let maxShare = 0.25

    /// Pixel count and bounds of each instance in a label map (0 is background).
    static func instances(labels: [Int], width w: Int) -> [Instance] {
        var byLabel: [Int: Instance] = [:]
        for (i, label) in labels.enumerated() where label > 0 {
            var s = byLabel[label] ?? Instance(label: label)
            let x = i % w, y = i / w
            s.count += 1
            s.bounds.x0 = min(s.bounds.x0, x); s.bounds.x1 = max(s.bounds.x1, x)
            s.bounds.y0 = min(s.bounds.y0, y); s.bounds.y1 = max(s.bounds.y1, y)
            byLabel[label] = s
        }
        return byLabel.values.sorted { $0.label < $1.label }
    }

    /// Smallest size, relative to the largest, at which a second object counts as another
    /// cartridge rather than a knot in the wood, a speck or a reflection.
    static let sameSizeShare = 0.35

    /// The largest instance that lies inside the frame and isn't too big, nil if none does.
    static func pick(_ instances: [Instance], width w: Int, height h: Int) -> Int? {
        candidates(instances, width: w, height: h).max { $0.count < $1.count }?.label
    }

    /// How many instances could each be a cartridge: inside the frame, not too big, and at least
    /// `sameSizeShare` the size of the largest of them.
    static func objectCount(_ instances: [Instance], width w: Int, height h: Int) -> Int {
        similar(candidates(instances, width: w, height: h).map(\.count))
    }

    /// How many of the sizes are at least `sameSizeShare` of the largest.
    static func similar(_ sizes: [Int]) -> Int {
        guard let largest = sizes.max(), largest > 0 else { return 0 }
        return sizes.filter { Double($0) >= sameSizeShare * Double(largest) }.count
    }

    private static func candidates(_ instances: [Instance], width w: Int, height h: Int) -> [Instance] {
        instances.filter { s in
            let b = s.bounds
            let inside = b.x0 > 0 && b.y0 > 0 && b.x1 < w - 1 && b.y1 < h - 1
            return inside && Double(s.count) <= maxShare * Double(w * h)
        }
    }
}
