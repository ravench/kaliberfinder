import Foundation

/// The silhouette of a cartridge lying on its side, reduced to numbers that don't
/// depend on distance or rotation: length / body width, and the width at a few
/// points along the length (tip first), relative to the body width.
struct ShapeMeasurement: Equatable {
    let aspect: Double
    let profile: [Double]

    /// Seen from the base or the tip (a disc): the shape says nothing about the calibre.
    var isEndView: Bool { aspect < 1.4 }
}

enum ShapeMatcher {
    /// Number of slices along the cartridge.
    static let bins = 40
    /// Where the profile is sampled, as fractions of the length from the tip.
    static let fractions: [Double] = [0.05, 0.15, 0.25, 0.35, 0.5, 0.65, 0.8, 0.95]
    /// Profile values are capped, so a stray pixel can't dominate.
    static let maxRelativeWidth = 1.3

    /// Measures a silhouette given as the pixel positions inside it (any scale, any rotation).
    /// `pixelSize` is the spacing of the points; it's added to every extent, since the
    /// outermost pixel centres lie half a pixel inside the edge on each side.
    static func measure(_ points: [Point], pixelSize: Double = 1) -> ShapeMeasurement? {
        measureWithLength(points, pixelSize: pixelSize)?.shape
    }

    /// Like `measure`, plus the silhouette's length in the points' units (pixels), for sizing with depth.
    static func measureWithLength(_ points: [Point], pixelSize: Double = 1) -> (shape: ShapeMeasurement, length: Double)? {
        guard points.count >= 50 else { return nil }
        let n = Double(points.count)
        let mx = points.reduce(0) { $0 + $1.x } / n
        let my = points.reduce(0) { $0 + $1.y } / n
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in points {
            let dx = p.x - mx, dy = p.y - my
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        // Principal axis of the point cloud = the cartridge's long axis.
        let angle = 0.5 * atan2(2 * sxy, sxx - syy)
        let ux = cos(angle), uy = sin(angle)
        var u = [Double](), v = [Double]()
        u.reserveCapacity(points.count); v.reserveCapacity(points.count)
        for p in points {
            let dx = p.x - mx, dy = p.y - my
            u.append(dx * ux + dy * uy)
            v.append(-dx * uy + dy * ux)
        }
        guard let lo = u.min(), let hi = u.max(), hi > lo else { return nil }
        let length = hi - lo
        var minV = [Double](repeating: .infinity, count: bins)
        var maxV = [Double](repeating: -.infinity, count: bins)
        for (pu, pv) in zip(u, v) {
            let i = min(bins - 1, Int((pu - lo) / length * Double(bins)))
            minV[i] = min(minV[i], pv); maxV[i] = max(maxV[i], pv)
        }
        let widths = (0..<bins).map { maxV[$0] >= minV[$0] ? maxV[$0] - minV[$0] + pixelSize : 0 }
        guard let shape = signature(widths: widths, length: length + pixelSize) else { return nil }
        return (shape, length + pixelSize)
    }

    /// The shape a catalogue cartridge would have, measured the same way as a photo.
    static func expected(for cartridge: Cartridge) -> ShapeMeasurement? {
        let g = OutlineGeometry(cartridge.outline)
        let h = cartridge.outline.height
        let widths = (0..<bins).map { i in
            (0...4).map { t in g.width(at: (Double(i) + Double(t) / 4) / Double(bins) * h) }.max() ?? 0
        }
        return signature(widths: widths, length: h, tipFirst: true)
    }

    /// Turns slice widths into a measurement. The body width is the width most of the
    /// cartridge has (80th percentile), so a thin rim or belt doesn't count.
    /// Unless `tipFirst`, the narrower end is taken to be the tip.
    static func signature(widths: [Double], length: Double, tipFirst: Bool = false) -> ShapeMeasurement? {
        guard widths.count == bins else { return nil }
        let body = widths.sorted(by: >)[bins / 5]
        guard body > 0 else { return nil }
        var w = widths
        let k = max(1, bins * 15 / 100)
        if !tipFirst && w.prefix(k).reduce(0, +) > w.suffix(k).reduce(0, +) { w.reverse() }
        let profile = fractions.map { f in min(maxRelativeWidth, w[min(bins - 1, Int(f * Double(bins)))] / body) }
        return ShapeMeasurement(aspect: length / body, profile: profile)
    }

    /// How different two shapes are: 0 is identical. Length/width ratio counts most.
    static func distance(_ a: ShapeMeasurement, _ b: ShapeMeasurement) -> Double {
        guard a.aspect > 0, b.aspect > 0, a.profile.count == b.profile.count, !a.profile.isEmpty else { return .infinity }
        let aspect = abs(log(a.aspect / b.aspect))
        let profile = zip(a.profile, b.profile).map { abs($0 - $1) }.reduce(0, +) / Double(a.profile.count)
        return 3 * aspect + 2 * profile
    }

    /// Expected shapes of all catalogue cartridges, computed once.
    static let catalogue: [String: ShapeMeasurement] = {
        var result: [String: ShapeMeasurement] = [:]
        for c in CartridgeCatalog.all { result[c.id] = expected(for: c) }
        return result
    }()
}
