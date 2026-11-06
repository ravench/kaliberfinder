import CoreGraphics
import Foundation

/// The measured silhouette's outline, drawn over the photo in green (SHAPE-07): the detected bullet,
/// neck and body taper as straight lines, joined into one outline.
enum ShapeContour {
    /// A closed polygon around the silhouette `points` (pixels, `pixelSize` apart) whose measurement
    /// is `shape`, inside `box`, the rotated box `ShapeMatcher.orientedBox` gives for them. From the
    /// tip (or case mouth): a straight line along the bullet, the neck and shoulder, the body's taper (a
    /// straight line fitted to its slices) down to the head, and back up the other side. Nil for an end view.
    static func polygon(_ points: [Point], pixelSize: Double, shape: ShapeMeasurement, box: [Point]) -> [CGPoint]? {
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
        // One side, from the tip to the head, as (fraction of the length, half width) pairs.
        var side: [(Double, Double)] = []
        var caseFrom = front
        if let neck = found?.0 {
            front = min(bodyEnd, neck.shoulderSlice + 1)
            // A neck starting in the first slices is the mouth of an empty case: nothing in front of it.
            caseFrom = neck.slices.lowerBound <= 2 ? 0 : neck.slices.lowerBound
            let start = Double(caseFrom) / Double(bins), end = Double(neck.slices.upperBound + 1) / Double(bins)
            // The shoulder runs from the neck's end to where the body's line starts.
            side = [(start, neck.width / 2), (end, neck.width / 2)]
        }
        // The bullet (or what lies in front of the case): a straight line from its tip to the case.
        let hasBullet = caseFrom > 0
        if hasBullet { side = [(0, w[0] / 2)] + side }
        // The body: a straight line through its widths (least squares), run on to the head.
        let from = max(front, 0), to = max(bodyEnd, from)
        let xs = (from...to).map(at), ys = (from...to).map { w[$0] }
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        let slope = sxx > 0 ? zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / sxx : 0
        func width(_ x: Double) -> Double { my + slope * (x - mx) }
        let bodyStart = found == nil && !hasBullet ? 0 : xs[0]
        side += [(bodyStart, width(bodyStart) / 2), (1, width(1) / 2)]
        return side.map { point($0.0, $0.1) } + side.reversed().map { point($0.0, -$0.1) }
    }
}
