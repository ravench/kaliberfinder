import Foundation

/// The silhouette of a cartridge lying on its side, reduced to numbers that don't
/// depend on distance or rotation: length / body width, and the width at a few
/// points along the length (tip first), relative to the body width.
struct ShapeMeasurement: Equatable {
    let aspect: Double
    let profile: [Double]
    /// Width of every slice relative to the body, tip (or case mouth) first. Empty when
    /// built by hand from a profile only.
    var widths: [Double] = []

    /// Seen from the base or the tip (a disc): the shape says nothing about the calibre.
    var isEndView: Bool { aspect < 1.4 }

    /// Rim and neck, if the slice widths are known.
    var features: ShapeFeatures? { widths.count == ShapeMatcher.bins ? ShapeFeatures(widths: widths) : nil }

    /// The same silhouette turned end for end: an empty case may lie either way round,
    /// since its mouth isn't always the narrower end.
    func reversed() -> ShapeMeasurement {
        guard widths.count == ShapeMatcher.bins else { return self }
        return ShapeMatcher.measurement(aspect: aspect, relativeWidths: widths.reversed())
    }

    /// An empty case turned so that its mouth comes first: the base is the end with the wider
    /// rim (or extractor groove edge), since a case mouth is never wider than the body.
    func mouthFirst() -> ShapeMeasurement {
        guard widths.count == ShapeMatcher.bins else { return self }
        let front = max(widths[0], widths[1])
        let back = max(widths[widths.count - 1], widths[widths.count - 2])
        return front > back + 0.02 ? reversed() : self
    }
}

/// Details of the silhouette that tell calibres apart beyond the overall shape (SHAPE-05).
struct ShapeFeatures: Equatable {
    /// Width at the base end relative to the body: about 1 for rimless cases, 1.1 to 1.25 for rimmed ones.
    let rim: Double
    /// Width at the other end (median of the first three slices) relative to the body. For an empty
    /// case it is the neck: below about 0.9 the case has a bottleneck.
    let mouth: Double
    /// The end is cut square (first slice about as wide as the next two), like a case mouth;
    /// a bullet tip narrows instead.
    let isFlatEnd: Bool

    static let rimmedFrom = 1.08
    static let neckBelow = 0.9
    static let flatFrom = 0.85

    init(widths w: [Double]) {
        rim = max(w[w.count - 1], w[w.count - 2])
        mouth = Array(w.prefix(3)).sorted()[1]
        isFlatEnd = w[0] / max(w[1], w[2], 1e-9) >= Self.flatFrom
    }

    var isRimmed: Bool { rim >= Self.rimmedFrom }
    var hasNeck: Bool { mouth < Self.neckBelow }
}

/// What the photo shows: a loaded cartridge or an empty case. Only the case can be compared
/// with a case, since the bullet makes up a large part of a cartridge's length.
enum ShapePart: Equatable {
    case cartridge
    case emptyCase
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

    /// The rectangle along the principal axis that just holds the points (the silhouette as
    /// measured, at any angle): its four corners in the points' units, nil for fewer than 50 points.
    static func orientedBox(_ points: [Point], pixelSize: Double = 1) -> [Point]? {
        guard points.count >= 50 else { return nil }
        let n = Double(points.count)
        let mx = points.reduce(0) { $0 + $1.x } / n
        let my = points.reduce(0) { $0 + $1.y } / n
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for p in points {
            let dx = p.x - mx, dy = p.y - my
            sxx += dx * dx; syy += dy * dy; sxy += dx * dy
        }
        let angle = 0.5 * atan2(2 * sxy, sxx - syy)
        let ux = cos(angle), uy = sin(angle)
        var u0 = Double.infinity, u1 = -Double.infinity, v0 = Double.infinity, v1 = -Double.infinity
        for p in points {
            let dx = p.x - mx, dy = p.y - my
            let u = dx * ux + dy * uy, v = -dx * uy + dy * ux
            u0 = min(u0, u); u1 = max(u1, u); v0 = min(v0, v); v1 = max(v1, v)
        }
        // Each point stands for a pixel (or a `pixelSize` square): the box covers them whole.
        let h = pixelSize / 2
        u0 -= h; u1 += h; v0 -= h; v1 += h
        return [(u0, v0), (u1, v0), (u1, v1), (u0, v1)].map { u, v in
            Point(x: mx + u * ux - v * uy, y: my + u * uy + v * ux)
        }
    }

    /// The shape a catalogue cartridge would have, measured the same way as a photo: the whole
    /// cartridge, or only its empty case (nil for balls, Minié bullets and pellets).
    static func expected(for cartridge: Cartridge, part: ShapePart = .cartridge) -> ShapeMeasurement? {
        let caseOnly = part == .emptyCase
        guard !caseOnly || cartridge.hasCase else { return nil }
        let g = OutlineGeometry(cartridge.outline, includeBullet: !caseOnly)
        let h = cartridge.outline.height
        let top = caseOnly ? h - cartridge.dimensions.caseLength : 0
        let length = h - top
        // Explicit types and steps: Xcode 26 can't type-check this as one expression in time.
        let widths: [Double] = (0..<bins).map { (i: Int) -> Double in
            var widest = 0.0
            for t in 0...4 {
                let position: Double = top + (Double(i) + Double(t) / 4) / Double(bins) * length
                widest = max(widest, g.width(at: position))
            }
            return widest
        }
        return signature(widths: widths, length: length, tipFirst: true)
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
        return measurement(aspect: length / body, relativeWidths: w.map { min(maxRelativeWidth, $0 / body) })
    }

    /// A measurement from slice widths that are already relative to the body.
    static func measurement(aspect: Double, relativeWidths w: [Double]) -> ShapeMeasurement {
        let profile = fractions.map { f in w[min(bins - 1, Int(f * Double(bins)))] }
        return ShapeMeasurement(aspect: aspect, profile: profile, widths: w)
    }

    /// How different two shapes are: 0 is identical. Length/width ratio counts most.
    static func distance(_ a: ShapeMeasurement, _ b: ShapeMeasurement) -> Double {
        guard a.aspect > 0, b.aspect > 0, a.profile.count == b.profile.count, !a.profile.isEmpty else { return .infinity }
        let aspect = abs(log(a.aspect / b.aspect))
        let profile = zip(a.profile, b.profile).map { abs($0 - $1) }.reduce(0, +) / Double(a.profile.count)
        return 3 * aspect + 2 * profile
    }

    /// How far the rim (relative to the body) may differ: rimmed and rimless cases differ by 0.1 to 0.25.
    static let rimTolerance = 0.1
    /// How far an empty case's neck (relative to the body) may differ.
    static let neckTolerance = 0.15

    /// Whether the photo's rim, and for an empty case its neck, can belong to the expected shape.
    /// Shapes without slice widths (built by hand) always fit.
    static func featuresFit(_ photo: ShapeMeasurement, _ expected: ShapeMeasurement, part: ShapePart) -> Bool {
        guard let a = photo.features, let b = expected.features else { return true }
        if abs(a.rim - b.rim) > rimTolerance { return false }
        if part == .emptyCase, abs(a.mouth - b.mouth) > neckTolerance { return false }
        return true
    }

    /// Added to a loaded cartridge's distance when its rim doesn't fit. On a loaded cartridge the
    /// rim is only a hint: a shadow or the edge of the base can look like a rim in the photo.
    static let rimPenalty = 0.1

    /// Distance to an expected shape. For an empty case, nil when rim or neck rule the calibre out,
    /// and the case is tried both ways round; for a cartridge a misfitting rim only adds `rimPenalty`.
    static func distance(_ photo: ShapeMeasurement, to expected: ShapeMeasurement, part: ShapePart) -> Double? {
        if part == .cartridge {
            let rimFits = featuresFit(photo, expected, part: .cartridge)
            return distance(photo, expected) + (rimFits ? 0 : rimPenalty)
        }
        return [photo, photo.reversed()]
            .filter { featuresFit($0, expected, part: part) }
            .map { distance($0, expected) }
            .min()
    }

    /// Expected shapes of all catalogue cartridges, computed once.
    static let catalogue: [String: ShapeMeasurement] = {
        var result: [String: ShapeMeasurement] = [:]
        for c in CartridgeCatalog.all { result[c.id] = expected(for: c) }
        return result
    }()

    /// Expected shapes of the empty cases (calibres that have a case), computed once.
    static let caseCatalogue: [String: ShapeMeasurement] = {
        var result: [String: ShapeMeasurement] = [:]
        for c in CartridgeCatalog.all { result[c.id] = expected(for: c, part: .emptyCase) }
        return result
    }()
}
