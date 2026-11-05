import CoreGraphics
import Foundation

/// The detected neck and the body's taper, as lines to draw over the photo (SHAPE-07): each side
/// of the neck and shoulder, and each edge of the body from the shoulder (or the case mouth) to the head.
struct ShapeLines: Equatable {
    /// Two polylines, one per side: from the neck's front along the neck and down the shoulder to the body.
    var neck: [[CGPoint]] = []
    /// Two straight lines along the body's edges, fitted to its slices: the taper.
    var taper: [[CGPoint]] = []

    var isEmpty: Bool { neck.isEmpty && taper.isEmpty }

    /// Every point passed through `transform`, e.g. from pixels to fractions of the photo.
    func map(_ transform: (CGPoint) -> CGPoint) -> ShapeLines {
        ShapeLines(neck: neck.map { $0.map(transform) }, taper: taper.map { $0.map(transform) })
    }

    /// The lines for the silhouette `points` (pixels, `pixelSize` apart) whose measurement is `shape`,
    /// inside `box`, the rotated box `ShapeMatcher.orientedBox` gives for them. Nil for an end view.
    init?(points: [Point], pixelSize: Double, shape: ShapeMeasurement, box: [Point]) {
        let bins = ShapeMatcher.bins
        guard box.count == 4, shape.widths.count == bins, !shape.isEndView else { return nil }
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

        let bodyEnd = bins - 1 - bins * 15 / 100
        var front = bodyEnd
        while front > 0 && w[front - 1] >= NeckShape.bodyFrom { front -= 1 }
        if let neck = found?.0 {
            front = min(bodyEnd, neck.shoulderSlice + 1)
            let start = Double(neck.slices.lowerBound) / Double(bins), end = Double(neck.slices.upperBound + 1) / Double(bins)
            self.neck = [-1.0, 1].map { side in
                [point(start, side * neck.width / 2), point(end, side * neck.width / 2), point(at(front), side * w[front] / 2)]
            }
        }
        guard bodyEnd > front else { return }
        // Straight line through the body's widths (least squares), drawn on both sides.
        let xs = (front...bodyEnd).map(at), ys = (front...bodyEnd).map { w[$0] }
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        let slope = sxx > 0 ? zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / sxx : 0
        func width(_ x: Double) -> Double { my + slope * (x - mx) }
        let a = xs[0], b = xs[xs.count - 1]
        taper = [-1.0, 1].map { side in [point(a, side * width(a) / 2), point(b, side * width(b) / 2)] }
    }

    init(neck: [[CGPoint]] = [], taper: [[CGPoint]] = []) {
        self.neck = neck
        self.taper = taper
    }
}
