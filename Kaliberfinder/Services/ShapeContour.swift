import CoreGraphics
import Foundation

/// The measured silhouette's outline, drawn over the photo in green (SHAPE-07): the detected bullet
/// as a typical nose curve (`NoseCurve`), the neck and the body taper as straight lines, joined into
/// one outline. A hidden switch colours each edge by the detection it comes from.
struct ShapeContour: Equatable {
    /// What found an edge of the outline.
    enum Part: Equatable {
        /// The tip, case mouth or head: the ends of the measured silhouette.
        case end
        /// What lies in front of the case: a typical nose curve fitted to it (`NoseCurve`).
        case bullet
        /// The neck and shoulder (`NeckShape`).
        case neck
        /// The body's taper, a straight line fitted to its slices.
        case body
    }

    /// Hidden developer switch in the settings: colour each edge by its `Part` instead of all green.
    static let partColoursKey = "outlinePartColours"

    /// The outline's corners, in order.
    var points: [CGPoint]
    /// Where each edge comes from: edge `i` runs from `points[i]` to the next (the last back to the first).
    var parts: [Part]
    /// The nose curve drawn for the bullet; nil without one (an empty case).
    var nose: NoseCurve?
    /// The outline to draw when the photo shows an empty case (`withoutBullet`); nil when it is this one.
    var empty: Outline?

    /// Corners and the parts of the edges between them, as `points` and `parts`.
    struct Outline: Equatable {
        var points: [CGPoint]
        var parts: [Part]
    }

    /// One corner on one side of the outline: the fraction of the length from the tip, the half width
    /// relative to the body, and the edge to the next corner.
    typealias Corner = (f: Double, half: Double, part: Part)

    /// Every point passed through `transform`, e.g. from pixels to fractions of the photo.
    func map(_ transform: (CGPoint) -> CGPoint) -> ShapeContour {
        ShapeContour(points: points.map(transform), parts: parts, nose: nose,
                     empty: empty.map { Outline(points: $0.points.map(transform), parts: $0.parts) })
    }

    /// The outline of an empty case: no bullet in front of it. Its neck, or its body, runs on to the
    /// mouth, cut flat there.
    func withoutBullet() -> ShapeContour {
        empty.map { ShapeContour(points: $0.points, parts: $0.parts) } ?? self
    }

    /// A closed polygon around the silhouette `points` (pixels, `pixelSize` apart) whose measurement
    /// is `shape`, inside `box`, the rotated box `ShapeMatcher.orientedBox` gives for them. From the
    /// tip (or case mouth): the bullet's nose curve, the neck and shoulder, the body's taper (a straight
    /// line fitted to its slices) down to the head, and back up the other side. Nil for an end view.
    static func polygon(_ points: [Point], pixelSize: Double, shape: ShapeMeasurement, box: [Point]) -> ShapeContour? {
        let bins = ShapeMatcher.bins
        guard box.count == 4, shape.widths.count == bins, !shape.isEndView, !points.isEmpty else { return nil }
        let c0 = box[0]
        let length = hypot(box[1].x - c0.x, box[1].y - c0.y), across = hypot(box[3].x - c0.x, box[3].y - c0.y)
        guard length > 0, across > 0 else { return nil }
        let ax = (box[1].x - c0.x) / length, ay = (box[1].y - c0.y) / length
        let nx = (box[3].x - c0.x) / across, ny = (box[3].y - c0.y) / across
        // Slice widths from the box's first end, to tell which end the measurement put first (the tip).
        var low = [Double](repeating: .infinity, count: bins), high = [Double](repeating: -.infinity, count: bins)
        for p in points {
            let u = (p.x - c0.x) * ax + (p.y - c0.y) * ay, v = (p.x - c0.x) * nx + (p.y - c0.y) * ny
            let i = max(0, min(bins - 1, Int(u / length * Double(bins))))
            low[i] = min(low[i], v); high[i] = max(high[i], v)
        }
        let raw = (0..<bins).map { high[$0] >= low[$0] ? high[$0] - low[$0] : 0 }
        let k = max(1, bins * 15 / 100)
        let tipAtFarEnd = raw.prefix(k).reduce(0, +) > raw.suffix(k).reduce(0, +)
        // An empty case may lie with its mouth at the other end.
        let found = shape.neck.map { ($0, false) } ?? shape.reversed().neck.map { ($0, true) }
        let w = found?.1 == true ? Array(shape.widths.reversed()) : shape.widths
        let flip = tipAtFarEnd != (found?.1 ?? false)
        let body = across / max(w.max() ?? 1, 1e-9)
        // A point `f` of the length from the tip (in the measurement's order), `half` body widths off the axis.
        func point(_ f: Double, _ half: Double) -> CGPoint {
            let u = (flip ? 1 - f : f) * length, v = across / 2 + half * body
            return CGPoint(x: c0.x + u * ax + v * nx, y: c0.y + u * ay + v * ny)
        }
        func at(_ slice: Int) -> Double { (Double(slice) + 0.5) / Double(bins) }

        let bodyEnd = bins - 1 - k
        var front = bodyEnd
        while front > 0 && w[front - 1] >= NeckShape.bodyFrom { front -= 1 }
        // One side, from the tip to the head.
        var side: [Corner] = []
        var caseFrom = front
        if let neck = found?.0 {
            front = min(bodyEnd, neck.shoulderSlice + 1)
            // A neck starting in the first slices is the mouth of an empty case: nothing in front of it.
            caseFrom = neck.slices.lowerBound <= 2 ? 0 : neck.slices.lowerBound
            let start = Double(caseFrom) / Double(bins), end = Double(neck.slices.upperBound + 1) / Double(bins)
            // The shoulder runs from the neck's end to where the body's line starts.
            side = [(start, neck.width / 2, .neck), (end, neck.width / 2, .neck)]
        }
        let hasBullet = caseFrom > 0
        // The body: a straight line through its widths (least squares), run on to the head.
        let from = max(front, 0), to = max(bodyEnd, from)
        let xs = (from...to).map(at), ys = (from...to).map { w[$0] }
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        let slope = sxx > 0 ? zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / sxx : 0
        func width(_ x: Double) -> Double { my + slope * (x - mx) }
        let bodyStart = found == nil && !hasBullet ? 0 : xs[0]
        side += [(bodyStart, width(bodyStart) / 2, .body), (1, width(1) / 2, .end)]
        let emptyCase = emptySide(side, widths: w, hasNeck: found != nil, front: front)
        // The bullet (or what lies in front of the case): a typical nose curve from its tip to the neck,
        // or on a straight case to the body, over whose first slices a round nose may still narrow.
        var bases = [(f: side[0].f, half: side[0].half)]
        if found == nil { bases = xs.prefix(NoseCurve.maxReach + 1).map { (f: $0, half: width($0) / 2) } }
        let nose = hasBullet ? NoseCurve.fitted(halfWidths: w.map { $0 / 2 }, bases: bases, body: { width($0) / 2 }) : nil
        if let nose {
            side[0].f = nose.length
            side[0].half = nose.base
            side.insert(contentsOf: nose.points().map { (f: $0.f, half: $0.half, part: Part.bullet) }, at: 0)
        }
        // Down one side, across the head, back up the other side and across the tip (or mouth).
        func outline(_ side: [Corner]) -> Outline {
            let edges = side.dropLast().map(\.part)
            return Outline(points: side.map { point($0.f, $0.half) } + side.reversed().map { point($0.f, -$0.half) },
                           parts: edges + [.end] + edges.reversed() + [.end])
        }
        let loaded = outline(side)
        return ShapeContour(points: loaded.points, parts: loaded.parts, nose: nose, empty: nose == nil ? nil : outline(emptyCase))
    }

    /// One side of the outline of an empty case, mouth first, from `side`, the side behind the bullet:
    /// the neck, or the body, runs on to the mouth. Where `NeckShape` finds no neck in the widths `w`
    /// (tip first, the body from slice `front` on), at least three slices in front of the body about as
    /// narrow as the narrowest are the neck, if that is narrow enough for one: a neck whose widths vary
    /// too much for `NeckShape` (Raven's 6 mm BR, 2026-11-07) is still drawn. The first slice is left
    /// out, as there: it is often only partly filled.
    static func emptySide(_ side: [Corner], widths w: [Double], hasNeck: Bool, front: Int) -> [Corner] {
        if !hasNeck, front > 1 {
            // The second narrowest: one slice cut short by noise does not set the neck's width.
            let ahead = w[1..<front].sorted(), narrow = ahead[min(1, ahead.count - 1)]
            let slices = (1..<front).filter { w[$0] <= narrow + 2 * NeckShape.straightWithin }
            let run = slices.map { w[$0] }.sorted()
            if run.count >= 3, run[run.count / 2] <= NeckShape.neckUpTo, let last = slices.last {
                let half = run[run.count / 2] / 2, end = Double(last + 1) / Double(w.count)
                let neck: [Corner] = [(0, half, .neck), (end, half, .neck)]
                return neck + side
            }
        }
        var side = side
        side[0].f = 0
        return side
    }
}

/// A bullet's nose drawn as a typical curve, not traced slice by slice: the round or pointed curve
/// the catalogue draws its bullets with (calibre-data `outline.py`, `bullet_profile`), cut flat at
/// the tip for a flat nose, and fitted to the bullet's slice widths, which matching compares with
/// those of the catalogue's drawings.
struct NoseCurve: Equatable {
    /// The catalogue's two nose curves: half width relative to the bullet, from where the nose leaves
    /// the bullet's full width (0) to a sharp tip (1). A flat nose is a round one cut flat.
    enum Kind: CaseIterable {
        case round
        case pointed

        func width(_ t: Double) -> Double {
            switch self {
            case .round: max(0, 1 - t * t).squareRoot()
            case .pointed: pow(max(0, 1 - pow(t, 1.7)), 0.8)
            }
        }
    }

    let kind: Kind
    /// How far along the curve the tip is cut flat: 1 runs out to a point, less leaves a flat tip.
    let cut: Double
    /// From the tip to where the nose meets the neck or body, as a fraction of the silhouette's length.
    let length: Double
    /// Half width there, relative to the body.
    let base: Double

    /// The tips the fit tries, from blunt (a flat nose) to a point.
    static let cuts = (0...6).map { 0.7 + Double($0) * 0.05 }
    /// How many of the body's first slices a nose may reach back over on a straight case.
    static let maxReach = 8
    /// Edges along each side of the nose.
    static let segments = 10

    /// Half width (relative to the body) at `f`, a fraction of the silhouette's length from the tip.
    func half(at f: Double) -> Double {
        base * kind.width(length > 0 ? cut * (1 - min(f, length) / length) : cut)
    }

    /// The corners along one side, from the tip toward the base (not the base itself, the next part's
    /// first corner): closer together at the tip, where the curve bends most.
    func points() -> [(f: Double, half: Double)] {
        (0..<Self.segments).map { j in
            let f = length * pow(Double(j) / Double(Self.segments), 2)
            return (f, half(at: f))
        }
    }

    /// The curve that fits the bullet's slices best (least squares). `halfWidths` are the slices' half
    /// widths, tip first, relative to the body; `bases` where the nose may end (fraction of the length,
    /// half width), and `body` the half width behind the nose, so every base is judged on the same slices.
    /// A slice's width is its widest point: its back edge, on a nose that narrows to the tip.
    static func fitted(halfWidths h: [Double], bases: [(f: Double, half: Double)], body: (Double) -> Double) -> NoseCurve? {
        let upTo = bases.map(\.f).max() ?? 0
        let curves: [NoseCurve] = bases.flatMap { b in
            Kind.allCases.flatMap { kind in cuts.map { NoseCurve(kind: kind, cut: $0, length: b.f, base: b.half) } }
        }
        return curves.map { ($0, $0.error(halfWidths: h, upTo: upTo, body: body)) }.min { $0.1 < $1.1 }?.0
    }

    /// Sum of squared differences to the slices in front of `upTo`: this curve, and `body` behind it.
    private func error(halfWidths h: [Double], upTo: Double, body: (Double) -> Double) -> Double {
        let bins = Double(h.count)
        var sum = 0.0
        for i in h.indices where (Double(i) + 0.5) / bins < upTo {
            let centre = (Double(i) + 0.5) / bins
            let model = centre < length ? half(at: min(Double(i + 1) / bins, length)) : body(centre)
            sum += (model - h[i]) * (model - h[i])
        }
        return sum
    }
}
