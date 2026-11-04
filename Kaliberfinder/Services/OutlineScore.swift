import Foundation

/// How much a cut-out looks like a cartridge seen from the side (SCAN-05): mirror-symmetric about
/// its long axis, solid, elongated, and bounded by sharp edges in the photo. A shadow lies on one
/// side only, a patch of wood grain or fabric has soft or ragged edges, and a piece of the
/// cartridge (only the bullet, only the tarnished half) is small, so the whole cartridge scores
/// highest among the patches a cut-out finds.
struct OutlineScore: Equatable {
    /// Long side over the body width, as `ShapeMatcher` measures it.
    let aspect: Double
    /// 1 when every slice is centred on the axis, 0 when it is off by half the body width.
    let symmetry: Double
    /// Pixels over length × body width (about 0.8 for a cartridge, capped at 1).
    let solidity: Double
    /// Mean brightness gradient along the outline over the mean in the whole crop.
    let edgeStrength: Double
    /// Pixels in the patch, in full-resolution pixels.
    let size: Double

    /// Elongations a cartridge or case seen from the side can have (end views are not cut out).
    static let aspects = 1.6...8.0
    /// Fewest full-resolution pixels a patch may have.
    static let minPixels = 80

    var value: Double {
        pow(symmetry, 4) * solidity * solidity * log(1 + edgeStrength) * size.squareRoot()
    }

    /// Scores a silhouette given as pixel positions on a grid of `step` pixels (as Vision's mask is
    /// sampled), against the gradient of the whole photo.
    static func score(points: [Point], step: Int, edges: GradientImage) -> OutlineScore? {
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        // One empty cell all round, so the outline is found at the edge of the box too.
        let x0 = Int(minX) / step - 1, y0 = Int(minY) / step - 1
        let w = Int(maxX) / step - x0 + 2, h = Int(maxY) / step - y0 + 2
        var mask = [Bool](repeating: false, count: w * h)
        for p in points { mask[(Int(p.y) / step - y0) * w + Int(p.x) / step - x0] = true }
        return score(mask: mask, width: w, height: h, step: step, origin: (x0 * step, y0 * step), edges: edges)
    }

    /// Scores a mask of `width` × `height` cells, `step` pixels apart, cell (0, 0) at pixel
    /// `origin` of the photo whose brightness gradient is `edges`.
    /// Nil when the patch is too small or not elongated like a cartridge.
    static func score(mask: [Bool], width w: Int, height h: Int, step: Int = 1,
                      origin: (x: Int, y: Int) = (0, 0), edges: GradientImage) -> OutlineScore? {
        var points: [Point] = []
        for i in mask.indices where mask[i] { points.append(Point(x: Double(i % w), y: Double(i / w))) }
        guard points.count * step * step >= minPixels, points.count >= 20 else { return nil }
        let n = Double(points.count)
        let mx = points.reduce(0) { $0 + $1.x } / n, my = points.reduce(0) { $0 + $1.y } / n
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in points {
            let dx = p.x - mx, dy = p.y - my
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        let angle = 0.5 * atan2(2 * sxy, sxx - syy)
        let ux = cos(angle), uy = sin(angle)
        let u = points.map { ($0.x - mx) * ux + ($0.y - my) * uy }
        let v = points.map { -($0.x - mx) * uy + ($0.y - my) * ux }
        guard let lo = u.min(), let hi = u.max(), hi > lo else { return nil }
        let length = hi - lo + 1, bins = ShapeMatcher.bins
        var minV = [Double](repeating: .infinity, count: bins), maxV = [Double](repeating: -.infinity, count: bins)
        for (pu, pv) in zip(u, v) {
            let i = min(bins - 1, Int((pu - lo) / length * Double(bins)))
            minV[i] = min(minV[i], pv); maxV[i] = max(maxV[i], pv)
        }
        let filled = (0..<bins).filter { maxV[$0] >= minV[$0] }
        let widths = (0..<bins).map { maxV[$0] >= minV[$0] ? maxV[$0] - minV[$0] + 1 : 0 }
        let body = widths.sorted(by: >)[bins / 5]
        guard body * Double(step) >= 4, aspects.contains(length / body) else { return nil }
        let offsets = filled.map { abs(maxV[$0] + minV[$0]) / 2 }.sorted()
        let symmetry = 1 - min(1, offsets[offsets.count / 2] / (body / 2))
        let solidity = min(1, n / (length * body))
        // Outline: mask cells with a 4-neighbour outside the mask.
        var sum = 0.0, outlineCells = 0
        for i in mask.indices where mask[i] {
            let x = i % w, y = i / w
            let inside = x > 0 && y > 0 && x < w - 1 && y < h - 1 && mask[i - 1] && mask[i + 1] && mask[i - w] && mask[i + w]
            guard !inside else { continue }
            let px = origin.x + x * step, py = origin.y + y * step
            sum += Double(edges.value(x: px, y: py)); outlineCells += 1
        }
        guard outlineCells > 0 else { return nil }
        let x0 = origin.x, y0 = origin.y, x1 = origin.x + w * step, y1 = origin.y + h * step
        let edgeStrength = (sum / Double(outlineCells)) / (Double(edges.mean(x0: x0, y0: y0, x1: x1, y1: y1)) + 1e-3)
        return OutlineScore(aspect: length / body, symmetry: symmetry, solidity: solidity,
                            edgeStrength: edgeStrength, size: n * Double(step * step))
    }
}

/// Brightness gradient magnitude (Sobel) of an image, with a summed-area table for fast means.
struct GradientImage {
    let width: Int
    let height: Int
    let values: [Float]
    private let integral: [Double]

    init(_ image: RGBImage) {
        let w = image.width, h = image.height
        var gray = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) { gray[i] = (image.pixels[i * 3] + image.pixels[i * 3 + 1] + image.pixels[i * 3 + 2]) / 3 }
        func g(_ x: Int, _ y: Int) -> Float { gray[min(h - 1, max(0, y)) * w + min(w - 1, max(0, x))] }
        var values = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let gx = (g(x + 1, y - 1) + 2 * g(x + 1, y) + g(x + 1, y + 1)) - (g(x - 1, y - 1) + 2 * g(x - 1, y) + g(x - 1, y + 1))
                let gy = (g(x - 1, y + 1) + 2 * g(x, y + 1) + g(x + 1, y + 1)) - (g(x - 1, y - 1) + 2 * g(x, y - 1) + g(x + 1, y - 1))
                values[y * w + x] = (gx * gx + gy * gy).squareRoot()
            }
        }
        var integral = [Double](repeating: 0, count: (w + 1) * (h + 1))
        for y in 0..<h {
            var row = 0.0
            for x in 0..<w {
                row += Double(values[y * w + x])
                integral[(y + 1) * (w + 1) + x + 1] = integral[y * (w + 1) + x + 1] + row
            }
        }
        self.width = w
        self.height = h
        self.values = values
        self.integral = integral
    }

    func value(x: Int, y: Int) -> Float {
        values[min(height - 1, max(0, y)) * width + min(width - 1, max(0, x))]
    }

    /// Mean over the pixels x0..<x1, y0..<y1 (clipped to the image).
    func mean(x0: Int, y0: Int, x1: Int, y1: Int) -> Float {
        let a = max(0, min(width, x0)), b = max(0, min(height, y0)), c = max(0, min(width, x1)), d = max(0, min(height, y1))
        guard c > a, d > b else { return 0 }
        let s = width + 1
        let sum = integral[d * s + c] - integral[b * s + c] - integral[d * s + a] + integral[b * s + a]
        return Float(sum / Double((c - a) * (d - b)))
    }
}
