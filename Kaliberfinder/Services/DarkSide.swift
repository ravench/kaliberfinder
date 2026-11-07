import Foundation

/// Gives back the dark side of a cartridge that Vision's silhouette leaves out.
///
/// A brass case reflects the room around it. Along the side that faces something dark (the
/// photographer, a dark wall, the night outside) it is nearly black, and Vision's foreground mask
/// often stops in the middle of that black strip: the silhouette comes out 10 to 25 % too narrow,
/// and a 9 mm Luger is matched as a .32 S&W Long (training shots 9x19-mm-20261106-223004, light
/// oak at night; LiDAR shows them 29–30 mm long but only 7.7–8.5 mm wide).
///
/// Neither the photo alone nor the silhouette alone can say where the metal ends: at its rim the case
/// mirrors the table next to it, so the black strip fades into the table or into the cartridge's
/// shadow without an edge. Two things together tell a cut side from a true one:
///
/// - **The photo:** the silhouette's edge on that side doesn't lie on an edge in the photo. Just
///   outside it the photo is as dark as just inside (no step from metal to table), and darker than
///   the table further out. Where Vision found the real edge, the metal is brighter than the shadow
///   beside it, or the table is as bright right next to the edge as further out.
/// - **The shape:** a bullet's tip lies on the cartridge's axis. Measured from the tip, the cut side
///   reaches clearly less far from the axis than the other side.
///
/// A cartridge is round, so the cut side is then given back as the other side's mirror image about
/// the axis through the tip, and no further than where the photo turns back to the table. Only for
/// cartridges with a bullet tip: an empty case or a wadcutter has no point on its axis, and is left
/// as Vision found it.
enum DarkSide {
    /// Slices along the cartridge for the edges (fewer for small silhouettes: at least one point step each).
    static let slices = 120
    /// The tip end is pointed: its last slices are at most this share of the body's width.
    static let tipWidthUpTo = 0.5
    /// The body at least this many point steps across. The axis through the tip is found to about half
    /// a step and the mirror image doubles that: on smaller silhouettes it would be off by more than 3 %.
    static let stepsAcross = 30.0
    /// The case's body, as shares of the length from the head: past the rim and extractor groove, and
    /// short of the case mouth of every cartridge (a 9 mm Luger's case is 64 % of its length, a .223's
    /// body up to the shoulder 64 %).
    static let bodyFrom = 0.08, bodyTo = 0.45
    /// The points near the tip that give the axis: this share of the length.
    static let tipShare = 0.02
    /// How much nearer to the axis one side must end than the other ((lit − cut) / (lit + cut)) to
    /// count as cut. Whole silhouettes mostly stay within 0.05 of the tip's axis; the photo tells the rest.
    static let asymmetryFrom = 0.07
    /// The photo just outside the edge, against just inside (log of the ratio of brightnesses): below
    /// this there is no step from brighter metal to darker shadow or table at the edge.
    static let stepBelow = 0.1
    /// Beyond the edge, the photo counts as table from this share of the table's brightness further out
    /// on: the black strip and the cartridge's shadow stay below it.
    static let tableShare = 0.5
    /// Where the table "further out" is, in body widths beyond the edge.
    static let tableFrom = 0.3, tableTo = 0.45

    /// The silhouette (`points`, every `step` pixels of `photo`) with its cut dark side given back,
    /// or nil when no side looks cut (see the type's description).
    static func restored(_ points: [Point], step: Int, photo: RGBImage) -> [Point]? {
        guard var frame = Frame(points, step: step) else { return nil }
        // The lit side's edge narrows with the case's taper, the cut one only by its share of the half
        // width: weighted so that the taper cancels out, the edges' slope is the axis's.
        let side = frame.shorterSide, share = frame.reach(side: side) / frame.reach(side: -side)
        let (cutSlope, litSlope) = side > 0 ? (frame.slopeHigh, frame.slopeLow) : (frame.slopeLow, frame.slopeHigh)
        if share > 0, share < 1,
           let turned = Frame(points, step: step, centre: frame.origin, angle: frame.angle + atan((cutSlope + share * litSlope) / (1 + share))) {
            frame = turned
        }
        let cut = frame.shorterSide
        let lit = frame.reach(side: -cut), short = frame.reach(side: cut)
        guard frame.tipWidth <= tipWidthUpTo, frame.bodyWidth >= stepsAcross * Double(step),
              lit > 0, (lit - short) / (lit + short) >= asymmetryFrom,
              let tableStart = tableStart(frame, side: cut, photo: photo) else { return nil }
        // The lit side's mirror image about the axis, added on the cut side up to where the table begins.
        let pixel = Double(step)
        var all = Set(points)
        for (u, v) in zip(frame.u, frame.v) where (v - frame.axis) * cut < 0 {
            let mirrored = 2 * frame.axis - v
            guard (mirrored - tableStart) * cut <= 0 else { continue }
            let p = frame.point(u: u, v: mirrored)
            all.insert(Point(x: (p.x / pixel).rounded() * pixel, y: (p.y / pixel).rounded() * pixel))
        }
        return all.count > points.count ? Array(all) : nil
    }

    /// Where the table begins beyond the silhouette's edge on `side` (`v`, median over the body slices),
    /// or nil when that edge lies on an edge in the photo rather than inside a dark area.
    static func tableStart(_ frame: Frame, side: Double, photo: RGBImage) -> Double? {
        var steps: [Double] = [], darks: [Double] = [], starts: [Double] = []
        let farFrom = Int(tableFrom * frame.bodyWidth), farTo = max(farFrom, Int(tableTo * frame.bodyWidth))
        for i in frame.body {
            let u = frame.centre(slice: i), edge = side > 0 ? frame.high[i] : frame.low[i]
            let at = { (offset: Int) -> Double? in photo.brightness(at: frame.point(u: u, v: edge + side * Double(offset))) }
            let inside = (2...5).compactMap { at(-$0) }, outside = (1...4).compactMap { at($0) }
            let table = median((farFrom...farTo).compactMap { at($0) })
            guard !inside.isEmpty, !outside.isEmpty, table > 0 else { continue }
            // (0.02 keeps black from counting as infinitely darker.)
            steps.append(log((mean(inside) + 0.02) / (mean(outside) + 0.02)))
            darks.append(mean(outside) / table)
            var offset = 1
            while Double(offset) < 0.4 * frame.bodyWidth, let b = at(offset), b < tableShare * table { offset += 1 }
            starts.append(edge + side * Double(offset))
        }
        guard !steps.isEmpty, median(steps) < stepBelow, median(darks) < tableShare else { return nil }
        return median(starts)
    }

    /// The silhouette in coordinates along the cartridge's axis (`u`, towards the tip) and across it
    /// (`v`), with the slice edges, the body slices and the axis through the tip.
    struct Frame {
        let mx: Double, my: Double, ux: Double, uy: Double
        let u: [Double], v: [Double]
        let lo: Double, length: Double, count: Int
        let low: [Double], high: [Double]
        let body: [Int]
        let bodyWidth: Double
        /// The tip end's width (its last slices) as a share of the body width.
        let tipWidth: Double
        /// `v` of the axis: the middle of the points near the tip.
        let axis: Double
        /// Slopes of the body's edges against `u`.
        let slopeHigh: Double, slopeLow: Double

        var origin: (x: Double, y: Double) { (mx, my) }
        var angle: Double { atan2(uy, ux) }
        /// The side (+1 high, −1 low) whose edge lies nearer to the axis.
        var shorterSide: Double { reach(side: 1) < reach(side: -1) ? 1 : -1 }

        /// The frame along the silhouette's principal axis, then turned to lie along its body's edges: when
        /// one side is cut, the principal axis leans towards the other.
        init?(_ points: [Point], step: Int) {
            guard points.count >= 50 else { return nil }
            let n = Double(points.count)
            let mx = points.reduce(0) { $0 + $1.x } / n, my = points.reduce(0) { $0 + $1.y } / n
            var sxx = 0.0, syy = 0.0, sxy = 0.0
            for p in points {
                let dx = p.x - mx, dy = p.y - my
                sxx += dx * dx; syy += dy * dy; sxy += dx * dy
            }
            guard let principal = Frame(points, step: step, centre: (mx, my), angle: 0.5 * atan2(2 * sxy, sxx - syy)) else { return nil }
            self = Frame(points, step: step, centre: (mx, my), angle: principal.angle + atan((principal.slopeHigh + principal.slopeLow) / 2)) ?? principal
        }

        init?(_ points: [Point], step: Int, centre: (x: Double, y: Double), angle: Double) {
            let pixel = Double(step)
            let (mx, my) = centre
            var ux = cos(angle), uy = sin(angle)
            var u = points.map { ($0.x - mx) * ux + ($0.y - my) * uy }
            var v = points.map { -($0.x - mx) * uy + ($0.y - my) * ux }
            guard let lo0 = u.min(), let hi0 = u.max(), hi0 > lo0 else { return nil }
            let count = min(DarkSide.slices, Int((hi0 - lo0) / pixel))
            guard count >= 24 else { return nil }
            var (low, high) = Frame.edges(u: u, v: v, slices: (lo0, hi0 - lo0 + pixel, count), pixel: pixel)
            var widths = zip(low, high).map { $1 - $0 }
            // The tip at the high end of `u` (turned round if the narrow end was at the low end).
            let eighth = max(1, count / 8)
            if mean(widths.prefix(eighth).filter { $0 > 0 }) < mean(widths.suffix(eighth).filter { $0 > 0 }) {
                ux = -ux; uy = -uy
                u = u.map { -$0 }; v = v.map { -$0 }
                (low, high) = Frame.edges(u: u, v: v, slices: (-hi0, hi0 - lo0 + pixel, count), pixel: pixel)
                widths = zip(low, high).map { $1 - $0 }
            }
            let lo = u.min() ?? 0, length = (u.max() ?? 0) - lo + pixel
            // Slice 0 is at the head, the tip at the high end.
            let body = (0..<count).filter {
                let share = (Double($0) + 0.5) / Double(count)
                return share >= DarkSide.bodyFrom && share <= DarkSide.bodyTo && widths[$0] > 0
            }
            guard body.count >= 5 else { return nil }
            let centres = body.map { lo + (Double($0) + 0.5) / Double(count) * length }
            let tipEnd = lo + length - pixel, tipZone = max(pixel, DarkSide.tipShare * length)
            let nearTip = zip(u, v).filter { $0.0 >= tipEnd - tipZone }.map(\.1)
            guard !nearTip.isEmpty else { return nil }
            self.mx = mx; self.my = my; self.ux = ux; self.uy = uy
            self.u = u; self.v = v
            self.lo = lo; self.length = length; self.count = count
            self.low = low; self.high = high
            self.body = body
            bodyWidth = median(body.map { widths[$0] })
            tipWidth = mean(widths.suffix(4).dropLast().filter { $0 > 0 }) / bodyWidth
            axis = mean(nearTip)
            slopeHigh = Frame.slope(centres, body.map { high[$0] }); slopeLow = Frame.slope(centres, body.map { low[$0] })
        }

        /// How far the body's edge on `side` (+1 high, −1 low) lies from the axis (median over the body slices).
        func reach(side: Double) -> Double {
            median(body.map { side > 0 ? high[$0] - axis : axis - low[$0] })
        }

        func centre(slice i: Int) -> Double { lo + (Double(i) + 0.5) / Double(count) * length }

        /// The photo point at `u` along and `v` across the axis.
        func point(u: Double, v: Double) -> Point {
            Point(x: mx + u * ux - v * uy, y: my + u * uy + v * ux)
        }

        /// The lowest and highest `v` in each of `count` slices along `u` from `lo` (pixel edges, not centres).
        static func edges(u: [Double], v: [Double], slices: (lo: Double, length: Double, count: Int), pixel: Double) -> (low: [Double], high: [Double]) {
            let (lo, length, count) = slices
            var low = [Double](repeating: .infinity, count: count), high = [Double](repeating: -.infinity, count: count)
            for (pu, pv) in zip(u, v) {
                let i = max(0, min(count - 1, Int((pu - lo) / length * Double(count))))
                low[i] = min(low[i], pv - pixel / 2); high[i] = max(high[i], pv + pixel / 2)
            }
            for i in 0..<count where high[i] < low[i] { low[i] = 0; high[i] = 0 }
            return (low, high)
        }

        static func slope(_ x: [Double], _ y: [Double]) -> Double {
            let mx = mean(x), my = mean(y)
            let sxx = x.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
            let sxy = zip(x, y).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
            return sxx > 0 ? sxy / sxx : 0
        }
    }
}

private func mean<S: Sequence>(_ values: S) -> Double where S.Element == Double {
    var sum = 0.0, n = 0.0
    for x in values { sum += x; n += 1 }
    return n > 0 ? sum / n : 0
}

private func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
}

extension RGBImage {
    /// The mean of red, green and blue (0…1) of the pixel at `p`; nil outside the image.
    func brightness(at p: Point) -> Double? {
        let x = Int(p.x.rounded()), y = Int(p.y.rounded())
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let i = (y * width + x) * 3
        return Double(pixels[i] + pixels[i + 1] + pixels[i + 2]) / (3 * 255)
    }
}
