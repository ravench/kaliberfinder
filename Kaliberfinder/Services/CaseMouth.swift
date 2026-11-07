import CoreGraphics
import Foundation

/// Where the case ends and the bullet begins, from the photo's colours (SHAPE-07): a copper, lead or
/// plated bullet meets the brass case at the mouth. The silhouette hardly narrows there (a 9 mm
/// bullet is 9.0 mm wide in a 9.65 mm mouth), but the colour changes from one side to the other.
enum CaseMouth {
    /// Pixels sampled across the axis at each step along it, spread over the middle half of the width
    /// (the edges show the table).
    static let across = 9
    static let band = 0.5
    /// A sampled pixel counts when it is neither dark nor a glare: red, green and blue together above
    /// `darkUpTo`, none of them from `glareFrom` on.
    static let darkUpTo: Float = 90
    static let glareFrom: Float = 250
    /// The colours just in front of and just behind the mouth are compared over this much of the
    /// length each.
    static let window = 0.05
    /// How much the colour (green and blue, each relative to red) changes at least at the mouth, and
    /// between the whole bullet and the case behind the mouth. Copper meeting brass changes it by
    /// 0.1 to 0.3 in Raven's photos; the colour along one case changes less.
    static let minStep = 0.08
    static let minChange = 0.1
    /// Steps next to the sharpest that change at least this share as much belong to the same edge.
    static let plateau = 0.9
    /// How far behind the mouth the case is compared with the bullet: the head's rim and groove are
    /// farther back.
    static let caseReach = 0.3
    /// The mouth lies at least this far from the tip, and no farther than this on a straight case.
    static let nearestTip = 0.08
    static let farthestStraight = 0.65

    /// Where on the axis to look for the mouth, as fractions of the length from the tip: from where the
    /// bullet is nearly as wide as the case in front of the shoulder (the neck, or the body of a straight
    /// case) to the end of a clear neck, or `farthestStraight`. `tipEnd`: the bullet behind its narrow tip.
    static func searched(widths w: [Double], neck: NeckShape?) -> (range: ClosedRange<Double>, tipEnd: Double)? {
        let bins = Double(w.count)
        let width = neck?.width ?? 1
        guard let first = w.firstIndex(where: { $0 >= 0.85 * width }) else { return nil }
        let tipEnd = Double(w.firstIndex { $0 >= 0.5 * width } ?? 0) / bins
        let from = max(nearestTip, Double(first) / bins)
        let to = neck.map { $0.isClear ? Double($0.slices.upperBound + 1) / bins : farthestStraight } ?? farthestStraight
        guard from < to else { return nil }
        return (from...to, tipEnd)
    }

    /// The mouth as a fraction of the silhouette's length from the tip, nil when the colours show none.
    /// `widths` are the silhouette's slices (tip first, relative to the body) and `neck` its neck;
    /// `point(f, half)` is the photo pixel `f` of the length from the tip and `half` body widths off the
    /// axis; `length` is the silhouette's length in pixels.
    static func find(in photo: RGBImage, widths w: [Double], neck: NeckShape?, length: Double,
                     point: (Double, Double) -> CGPoint) -> Double? {
        guard !w.isEmpty, let area = searched(widths: w, neck: neck) else { return nil }
        // One step per pixel of the length, and at least three in each window.
        let n = max(Int(3 / window) + 1, Int(length))
        let f = (0..<n).map { (Double($0) + 0.5) / Double(n) }
        let colours = f.map { Self.colour(in: photo, at: $0, half: w[min(w.count - 1, Int($0 * Double(w.count)))] / 2, point: point) }
        // The median colour of the steps from `a` up to `b` (the steps with `a <= f[i] < b`), nil with fewer than three.
        func median(_ a: Double, _ b: Double) -> (Double, Double)? {
            let lo = max(0, Int((a * Double(n) - 0.5).rounded(.up))), hi = min(n, Int((b * Double(n) - 0.5).rounded(.up)))
            guard lo < hi else { return nil }
            let inside = colours[lo..<hi].compactMap { $0 }
            guard inside.count >= 3 else { return nil }
            func mid(_ v: [Double]) -> Double { v.sorted()[v.count / 2] }
            return (mid(inside.map(\.0)), mid(inside.map(\.1)))
        }
        func distance(_ a: (Double, Double), _ b: (Double, Double)) -> Double { hypot(a.0 - b.0, a.1 - b.1) }
        // The sharpest change of colour in the range. The medians change as much anywhere within half a
        // window of a sharp edge: the mouth is the middle of the steps that change nearly as much.
        let steps = f.filter { area.range.contains($0) }.compactMap { (x: Double) -> (at: Double, step: Double)? in
            guard let front = median(x - window, x), let back = median(x, x + window) else { return nil }
            return (x, distance(front, back))
        }
        guard let top = steps.indices.max(by: { steps[$0].step < steps[$1].step }) else { return nil }
        let step = steps[top].step
        var first = top, last = top
        while first > 0 && steps[first - 1].step >= plateau * step { first -= 1 }
        while last + 1 < steps.count && steps[last + 1].step >= plateau * step { last += 1 }
        let mouth = (steps[first].at + steps[last].at) / 2
        // Copper on one side, brass on the other, all along: not a change along one material.
        guard step >= minStep, let bullet = median(area.tipEnd, mouth),
              let brass = median(mouth, mouth + caseReach), distance(bullet, brass) >= minChange else { return nil }
        return mouth
    }

    /// Green and blue relative to red at `f` of the length, the median over the middle of the width
    /// (`half` body widths each side of the axis); nil when too few pixels there count.
    private static func colour(in photo: RGBImage, at f: Double, half: Double, point: (Double, Double) -> CGPoint) -> (Double, Double)? {
        var green: [Double] = [], blue: [Double] = []
        for j in 0..<across {
            let p = point(f, (2 * Double(j) / Double(across - 1) - 1) * band * half)
            let x = Int(p.x.rounded(.down)), y = Int(p.y.rounded(.down))
            guard x >= 0, y >= 0, x < photo.width, y < photo.height else { continue }
            let i = (y * photo.width + x) * 3
            let r = photo.pixels[i], g = photo.pixels[i + 1], b = photo.pixels[i + 2]
            guard r + g + b > darkUpTo, max(r, g, b) < glareFrom else { continue }
            green.append(Double(g / max(r, 1)))
            blue.append(Double(b / max(r, 1)))
        }
        guard green.count >= across / 2 else { return nil }
        return (green.sorted()[green.count / 2], blue.sorted()[blue.count / 2])
    }
}
