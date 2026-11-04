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
/// 2. Cut out: around that cluster, pixels whose colour (not brightness, so shadows don't count;
///    in a second pass a little brightness too, for brass on wood) differs from the background
///    form patches; holes from reflections are filled. Of the patches from a few crops and
///    thresholds, the one that looks most like a cartridge is taken (see `OutlineScore`).
enum ColorSegmenter {
    /// Long side of the copy used to locate the cartridge.
    static let locateSide = 800
    /// Share of the most contrasting pixels kept when locating.
    static let locateQuantile: Float = 0.99

    struct Box: Equatable {
        var x0: Int, y0: Int, x1: Int, y1: Int
    }

    /// Pixels of the cartridge (x, y in image pixels), nil if nothing stands out.
    static func segment(_ image: RGBImage) -> [Point]? {
        best(image)?.points
    }

    /// Crops around the located cluster, as factors of the first padding.
    static let paddings: [Double] = [1, 2, 4]
    /// Thresholds tried, as factors of Otsu's threshold on the colour distance.
    static let thresholdFactors: [Float] = [0.8, 1, 1.3]
    /// Weight of brightness next to colour in the second cut-out (brass on wood differs more in
    /// brightness than in colour).
    static let brightnessWeight: Float = 0.3
    /// Largest patches per cut-out that are scored.
    static let patchesPerCut = 6

    /// The patch that looks most like a cartridge (see `OutlineScore`) among the cut-outs of a few
    /// crops around the located cluster, with colour alone and with brightness, at a few thresholds;
    /// made symmetric about its axis (see `ShapeMatcher.mirrorTrimmed`).
    static func best(_ image: RGBImage, edges: GradientImage? = nil) -> (points: [Point], score: OutlineScore)? {
        guard let box = locate(image) else { return nil }
        let edges = edges ?? GradientImage(image)
        let longSide = Double(max(image.width, image.height))
        let pad = max(Double(max(box.x1 - box.x0, box.y1 - box.y0)) * 0.6, longSide / 16)
        var chosen: (mask: [Bool], box: Box, score: OutlineScore, value: Double)?
        for factor in paddings {
            let p = Int(pad * factor)
            let crop = Box(x0: max(0, box.x0 - p), y0: max(0, box.y0 - p),
                           x1: min(image.width, box.x1 + p), y1: min(image.height, box.y1 + p))
            for candidate in candidates(image, crop, edges: edges) {
                let value = candidate.score.value * (isBrass(image, candidate.mask, candidate.box) ? 1 : notBrassWeight)
                if value > (chosen?.value ?? 0) { chosen = (candidate.mask, candidate.box, candidate.score, value) }
            }
        }
        guard let found = chosen else { return nil }
        return (ShapeMatcher.mirrorTrimmed(points(found.mask, found.box)), found.score)
    }

    /// A patch that isn't brass-coloured counts this much of its score: a grey stone or tool next
    /// to the cases has as clean an outline as a case (shelf photo, 2026-11-04), but most cases are
    /// brass. A nickel case still wins over anything with a less cartridge-like outline.
    static let notBrassWeight = 0.5

    /// The image pixels of a patch's mask (`box`: where the mask lies in the image).
    static func points(_ mask: [Bool], _ box: Box) -> [Point] {
        let w = box.x1 - box.x0
        return mask.indices.filter { mask[$0] }.map { Point(x: Double(box.x0 + $0 % w), y: Double(box.y0 + $0 / w)) }
    }

    /// Whether a patch is, on average, brass-coloured (see `PhotoAnalyzer.isBrass`).
    static func isBrass(_ image: RGBImage, _ mask: [Bool], _ box: Box) -> Bool {
        PhotoAnalyzer.isBrass(image, points: points(mask, box))
    }

    // MARK: - Locate

    /// Where the cartridge is, in image pixels.
    static func locate(_ image: RGBImage) -> Box? {
        guard let found = clusters(image), let best = found.main else { return nil }
        let w = found.width, f = found.factor
        let b = bounds(found.clusters[best], width: w)
        return Box(x0: b.x0 * f, y0: b.y0 * f, x1: min(image.width, (b.x1 + 1) * f), y1: min(image.height, (b.y1 + 1) * f))
    }

    /// How many cartridges compete for the measurement: the one `locate` picks, plus clusters
    /// that look like cartridges and make it unclear which one is meant (see `Blob.competes`);
    /// 0 if nothing stands out.
    static func objectCount(_ image: RGBImage) -> Int {
        competitors(image).count
    }

    /// Where the competing cartridges are, in image pixels, the one `locate` picks first.
    static func competitors(_ image: RGBImage) -> [Box] {
        guard let found = clusters(image), let main = found.main else { return [] }
        let f = found.factor
        return Blob.competitors(of: main, in: found.blobs, width: found.width, height: found.height).map { i in
            let b = bounds(found.clusters[i], width: found.width)
            return Box(x0: b.x0 * f, y0: b.y0 * f, x1: min(image.width, (b.x1 + 1) * f), y1: min(image.height, (b.y1 + 1) * f))
        }
    }

    /// Clusters of pixels that stand out by colour and don't touch the frame, in a copy of the
    /// photo scaled down by `factor` to `width` × `height`; `main` is the one nearest the centre,
    /// weighted by size.
    struct Clusters {
        let clusters: [[Int]]
        let blobs: [Blob]
        let width: Int, height: Int, factor: Int
        var main: Int? {
            let scores = blobs.map { $0.centreScore(width: width, height: height) }
            return scores.indices.max { scores[$0] < scores[$1] }
        }
    }

    /// The clusters with their size, elongation and colour.
    private static func clusters(_ image: RGBImage) -> Clusters? {
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
        let blobs = candidates.map { cluster -> Blob in
            var blob = Blob()
            var colour = [Float](repeating: 0, count: 3), strongCount: Float = 0
            for p in cluster {
                blob.add(x: p % w, y: p / w)
                guard contrast[p] > threshold else { continue }
                for c in 0..<3 { colour[c] += small.pixels[p * 3 + c] }
                strongCount += 1
            }
            if strongCount > 0 { blob.colour = colour.map { $0 / strongCount } }
            return blob
        }
        return Clusters(clusters: candidates, blobs: blobs, width: w, height: h, factor: f)
    }

    // MARK: - Cut out

    /// Patches inside `crop` whose colour (and, in a second pass, brightness) differs from the
    /// crop's edge, at a few thresholds, holes filled, each with its score; patches touching the
    /// crop's edge and patches that don't look like a cartridge are left out.
    static func candidates(_ image: RGBImage, _ crop: Box, edges: GradientImage) -> [(mask: [Bool], box: Box, score: OutlineScore)] {
        let w = crop.x1 - crop.x0, h = crop.y1 - crop.y0
        guard w > 6, h > 6 else { return [] }
        var cropped = [Float](repeating: 0, count: w * h * 3)
        for y in 0..<h {
            let src = ((crop.y0 + y) * image.width + crop.x0) * 3
            for i in 0..<(w * 3) { cropped[y * w * 3 + i] = image.pixels[src + i] }
        }
        let colours = chroma(RGBImage(width: w, height: h, pixels: cropped)).pixels
        var result: [(mask: [Bool], box: Box, score: OutlineScore)] = []
        let cropEdgeMean = edges.mean(x0: crop.x0, y0: crop.y0, x1: crop.x1, y1: crop.y1)
        for weight in [0, brightnessWeight] {
            let distance = distanceFromEdge(colours: colours, original: cropped, brightness: weight, width: w, height: h)
            let otsuThreshold = otsu(distance)
            for factor in thresholdFactors {
                let threshold = otsuThreshold * factor
                let mask = opened(distance.map { $0 > threshold }, width: w, height: h)
                let patches = components(mask, width: w, height: h)
                    .filter { $0.count >= OutlineScore.minPixels && !touchesBorder($0, width: w, height: h) }
                    .sorted { $0.count > $1.count }
                for patch in patches.prefix(patchesPerCut) {
                    // Within the patch's bounds plus one pixel, so filling holes stays cheap.
                    let b = bounds(patch, width: w)
                    let bx = b.x0 - 1, by = b.y0 - 1, bw = b.x1 - b.x0 + 3, bh = b.y1 - b.y0 + 3
                    var m = [Bool](repeating: false, count: bw * bh)
                    for p in patch { m[(p / w - by) * bw + p % w - bx] = true }
                    m = fillHoles(m, width: bw, height: bh)
                    let box = Box(x0: crop.x0 + bx, y0: crop.y0 + by, x1: crop.x0 + bx + bw, y1: crop.y0 + by + bh)
                    if let score = OutlineScore.score(mask: m, width: bw, height: bh, origin: (box.x0, box.y0),
                                                      edges: edges, edgeMean: cropEdgeMean) {
                        result.append((m, box, score))
                    }
                }
            }
        }
        return result
    }

    /// Distance of each pixel's colour (plus `brightness` × its brightness) from the median along
    /// the crop's edge, i.e. from the background.
    static func distanceFromEdge(colours: [Float], original: [Float], brightness: Float, width w: Int, height h: Int) -> [Float] {
        let channels = brightness > 0 ? 4 : 3
        var features = [Float](repeating: 0, count: w * h * channels)
        for i in 0..<(w * h) {
            for c in 0..<3 { features[i * channels + c] = colours[i * 3 + c] }
            if channels == 4 { features[i * 4 + 3] = brightness * (original[i * 3] + original[i * 3 + 1] + original[i * 3 + 2]) / 3 }
        }
        var ring = [[Float]](repeating: [], count: channels)
        for y in 0..<h {
            for x in 0..<w where y < 3 || y >= h - 3 || x < 3 || x >= w - 3 {
                for c in 0..<channels { ring[c].append(features[(y * w + x) * channels + c]) }
            }
        }
        let background = ring.map { quantile($0, 0.5) }
        var distance = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            var sum: Float = 0
            for c in 0..<channels {
                let d = features[i * channels + c] - background[c]
                sum += d * d
            }
            distance[i] = sum.squareRoot()
        }
        return distance
    }

    /// Erosion then dilation with a plus-shaped 3 × 3 element: removes one-pixel threads and specks
    /// that join the cartridge to the grain around it.
    static func opened(_ mask: [Bool], width w: Int, height h: Int) -> [Bool] {
        // Erosion (`all`) or dilation; pixels outside the image count as background.
        func morph(_ m: [Bool], all: Bool) -> [Bool] {
            var out = m
            for i in m.indices {
                let x = i % w, y = i / w
                let l = x > 0 && m[i - 1], r = x < w - 1 && m[i + 1], u = y > 0 && m[i - w], d = y < h - 1 && m[i + w]
                out[i] = all ? (m[i] && l && r && u && d) : (m[i] || l || r || u || d)
            }
            return out
        }
        return morph(morph(mask, all: true), all: false)
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
                if x > 0, mask[p - 1], !label[p - 1] { label[p - 1] = true; patch.append(p - 1) }
                if x < w - 1, mask[p + 1], !label[p + 1] { label[p + 1] = true; patch.append(p + 1) }
                if y > 0, mask[p - w], !label[p - w] { label[p - w] = true; patch.append(p - w) }
                if y < h - 1, mask[p + w], !label[p + w] { label[p + w] = true; patch.append(p + w) }
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
        /// Vision labels that make up this object: more than one when parts were joined.
        var labels: IndexSet
        var blob = Blob()
        var count: Int { blob.count }
        var bounds = ColorSegmenter.Box(x0: Int.max, y0: Int.max, x1: Int.min, y1: Int.min)

        init(label: Int) {
            self.label = label
            labels = [label]
        }

        mutating func join(_ other: Instance) {
            labels.formUnion(other.labels)
            blob.join(other.blob)
            bounds = ColorSegmenter.Box(x0: min(bounds.x0, other.bounds.x0), y0: min(bounds.y0, other.bounds.y0),
                                        x1: max(bounds.x1, other.bounds.x1), y1: max(bounds.y1, other.bounds.y1))
        }
    }

    /// Largest share of the photo a cartridge may cover.
    static let maxShare = 0.25

    /// Pixel count and bounds of each instance in a label map (0 is background).
    static func instances(labels: [Int], width w: Int) -> [Instance] {
        var byLabel: [Int: Instance] = [:]
        for (i, label) in labels.enumerated() where label > 0 {
            var s = byLabel[label] ?? Instance(label: label)
            let x = i % w, y = i / w
            s.blob.add(x: x, y: y)
            s.bounds.x0 = min(s.bounds.x0, x); s.bounds.x1 = max(s.bounds.x1, x)
            s.bounds.y0 = min(s.bounds.y0, y); s.bounds.y1 = max(s.bounds.y1, y)
            byLabel[label] = s
        }
        return byLabel.values.sorted { $0.label < $1.label }
    }

    /// A smaller piece touching a bigger one is part of it, not another cartridge: Vision can cut
    /// a fired blank's star crimp off its case. Pieces up to this share of the bigger one are joined.
    static let partShare = 0.5

    /// The instances with pieces of one object joined: an instance inside the frame that touches
    /// a bigger one (4-neighbours in the label map) and has at most `partShare` of its pixels.
    static func joiningParts(_ instances: [Instance], labels: [Int], width w: Int, height h: Int) -> [Instance] {
        let inFrame = Set(candidates(instances, width: w, height: h).map(\.label))
        let byLabel = Dictionary(uniqueKeysWithValues: instances.map { ($0.label, $0) })
        var touching = Set<[Int]>()
        for i in labels.indices where labels[i] > 0 && inFrame.contains(labels[i]) {
            let x = i % w
            for j in [x < w - 1 ? i + 1 : -1, i + w < labels.count ? i + w : -1] where j >= 0 {
                let a = labels[i], b = labels[j]
                if b > 0, b != a, inFrame.contains(b) { touching.insert([min(a, b), max(a, b)]) }
            }
        }
        // Union-find: each piece goes to the bigger instance it touches.
        var root = Dictionary(uniqueKeysWithValues: instances.map { ($0.label, $0.label) })
        func find(_ l: Int) -> Int { root[l] == l ? l : find(root[l] ?? l) }
        for pair in touching.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            guard let a = byLabel[pair[0]], let b = byLabel[pair[1]] else { continue }
            let (small, big) = a.count <= b.count ? (a, b) : (b, a)
            guard Double(small.count) <= partShare * Double(big.count) else { continue }
            let rs = find(small.label), rb = find(big.label)
            if rs != rb { root[rs] = rb }
        }
        var joined: [Int: Instance] = [:]
        for s in instances where find(s.label) == s.label { joined[s.label] = s }
        for s in instances where find(s.label) != s.label { joined[find(s.label)]?.join(s) }
        return joined.values.sorted { $0.label < $1.label }
    }

    /// The largest instance that lies inside the frame and isn't too big, nil if none does.
    static func pick(_ instances: [Instance], width w: Int, height h: Int) -> Int? {
        pickInstance(instances, width: w, height: h)?.label
    }

    /// Like `pick`, with all the labels the picked object is made of.
    static func pickInstance(_ instances: [Instance], width w: Int, height h: Int) -> Instance? {
        candidates(instances, width: w, height: h).max { $0.count < $1.count }
    }

    /// How many cartridges compete for the measurement: the one `pick` takes, plus instances
    /// inside the frame that look like cartridges and make it unclear which one is meant
    /// (see `Blob.competes`).
    static func objectCount(_ instances: [Instance], width w: Int, height h: Int) -> Int {
        competitors(instances, width: w, height: h).count
    }

    /// The competing instances, the one `pick` takes first.
    static func competitors(_ instances: [Instance], width w: Int, height h: Int) -> [Instance] {
        let found = candidates(instances, width: w, height: h)
        let blobs = found.map(\.blob)
        guard let main = blobs.indices.max(by: { blobs[$0].count < blobs[$1].count }) else { return [] }
        return Blob.competitors(of: main, in: blobs, width: w, height: h).map { found[$0] }
    }

    private static func candidates(_ instances: [Instance], width w: Int, height h: Int) -> [Instance] {
        instances.filter { s in
            let b = s.bounds
            let inside = b.x0 > 0 && b.y0 > 0 && b.x1 < w - 1 && b.y1 < h - 1
            return inside && Double(s.count) <= maxShare * Double(w * h)
        }
    }
}

/// A patch of pixels summed up by size, position, elongation and colour, to tell a second
/// cartridge from a table edge, a chair leg, a knot in the wood or a speck.
///
/// Another object only matters when it looks like a cartridge *and* gets in the way: it is about
/// as prominent as the cartridge picked for measuring, so it is unclear which one is meant. A
/// cartridge off in a corner, or anything that doesn't look like one, is ignored and the picked
/// cartridge is measured.
struct Blob: Equatable {
    private(set) var count = 0
    private var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0
    /// Mean colour (chroma) of the patch; nil when unknown, as for Vision instances.
    var colour: [Float]?

    /// Size range, relative to the cartridge, of another object that counts as a cartridge too
    /// (wide enough for a 9 mm next to a GP 11).
    static let sizeRange = (1.0 / 3)...3.0
    /// Largest factor by which its elongation may differ from the cartridge's.
    static let maxAspectFactor = 2.5
    /// Smallest prominence (size, weighted down away from the centre), relative to the picked
    /// cartridge, at which another cartridge makes the choice unclear.
    static let competingShare = 0.4
    /// Largest distance between the two mean colours (chroma, 0…255 per channel).
    static let maxColourDistance: Float = 40

    /// Adds another patch's pixels (its colour is kept only if this one has none).
    mutating func join(_ other: Blob) {
        count += other.count
        sx += other.sx; sy += other.sy
        sxx += other.sxx; syy += other.syy; sxy += other.sxy
        if colour == nil { colour = other.colour }
    }

    mutating func add(x: Int, y: Int) {
        let px = Double(x), py = Double(y)
        count += 1
        sx += px; sy += py
        sxx += px * px; syy += py * py; sxy += px * py
    }

    /// Size, weighted down the further the patch is from the centre of a `width` × `height` image:
    /// how likely it is the subject of the photo.
    func centreScore(width w: Int, height h: Int) -> Double {
        guard count >= 1, w > 0, h > 0 else { return 0 }
        let n = Double(count)
        let dx = (sx / n - Double(w) / 2) / (Double(w) / 2)
        let dy = (sy / n - Double(h) / 2) / (Double(h) / 2)
        let off = min(1, (dx * dx + dy * dy).squareRoot() / 2.0.squareRoot())
        return n * (1 - off) * (1 - off)
    }

    /// Long axis over short axis of the patch (principal axes of its pixels), at least 1.
    var aspect: Double {
        guard count > 1 else { return 1 }
        let n = Double(count), mx = sx / n, my = sy / n
        let a = sxx / n - mx * mx, c = syy / n - my * my, b = sxy / n - mx * my
        let root = ((a - c) * (a - c) / 4 + b * b).squareRoot()
        // A one-pixel-wide line still has a variance of 1/12 across.
        let major = (a + c) / 2 + root, minor = max((a + c) / 2 - root, 1.0 / 12)
        return max(1, (major / minor).squareRoot())
    }

    /// Whether `other` could be another cartridge next to this one: similar size, elongation and,
    /// when both are known, colour. Errs towards no: a false alarm blocks the result entirely.
    func resembles(_ other: Blob) -> Bool {
        guard count >= 1, Self.sizeRange.contains(Double(other.count) / Double(count)) else { return false }
        guard max(aspect, other.aspect) / min(aspect, other.aspect) <= Self.maxAspectFactor else { return false }
        if let a = colour, let b = other.colour {
            let distance = zip(a, b).reduce(Float(0)) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }.squareRoot()
            return distance <= Self.maxColourDistance
        }
        return true
    }

    /// Whether `other` looks like a cartridge too and is prominent enough in a `width` × `height`
    /// image that it is unclear which of the two should be measured.
    func competes(_ other: Blob, width w: Int, height h: Int) -> Bool {
        resembles(other) && other.centreScore(width: w, height: h) >= Self.competingShare * centreScore(width: w, height: h)
    }

    /// The cartridge at `main` plus every other blob that competes with it.
    static func count(competingWith main: Int, in blobs: [Blob], width w: Int, height h: Int) -> Int {
        competitors(of: main, in: blobs, width: w, height: h).count
    }

    /// Indices of the cartridge at `main` (first) and of every other blob that competes with it.
    static func competitors(of main: Int, in blobs: [Blob], width w: Int, height h: Int) -> [Int] {
        [main] + blobs.indices.filter { $0 != main && blobs[main].competes(blobs[$0], width: w, height: h) }
    }
}
