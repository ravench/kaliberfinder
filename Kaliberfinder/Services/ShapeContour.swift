import CoreGraphics
import Foundation

/// The measured silhouette's outline, drawn over the photo in green (SHAPE-07): it follows the case,
/// its neck and shoulder, and the bullet when there is one.
enum ShapeContour {
    /// A closed polygon around the silhouette `points` (pixels, `pixelSize` apart) inside `box`, the
    /// rotated box `ShapeMatcher.orientedBox` gives for them: each side's edge, slice by slice along
    /// the length. Nil without a box.
    static func polygon(_ points: [Point], pixelSize: Double, box: [Point]) -> [CGPoint]? {
        guard box.count == 4, !points.isEmpty else { return nil }
        let c0 = box[0]
        let length = hypot(box[1].x - c0.x, box[1].y - c0.y), across = hypot(box[3].x - c0.x, box[3].y - c0.y)
        guard length > 0, across > 0 else { return nil }
        let ax = (box[1].x - c0.x) / length, ay = (box[1].y - c0.y) / length
        let nx = (box[3].x - c0.x) / across, ny = (box[3].y - c0.y) / across
        // Slices about 1.5 points thick, so each one holds points across its whole width.
        let slices = max(2, min(120, Int(length / (1.5 * max(pixelSize, 1e-9)))))
        var low = [Double](repeating: .infinity, count: slices), high = [Double](repeating: -.infinity, count: slices)
        let h = pixelSize / 2
        for p in points {
            let u = (p.x - c0.x) * ax + (p.y - c0.y) * ay, v = (p.x - c0.x) * nx + (p.y - c0.y) * ny
            let i = max(0, min(slices - 1, Int(u / length * Double(slices))))
            low[i] = min(low[i], v - h); high[i] = max(high[i], v + h)
        }
        let filled = (0..<slices).filter { high[$0] >= low[$0] }
        guard filled.count >= 2 else { return nil }
        // A slice sticking out of both neighbours is noise (a speck of shadow): the median of three.
        func median(_ edge: [Double], _ k: Int) -> Double {
            guard k > 0, k < filled.count - 1 else { return edge[filled[k]] }
            return [edge[filled[k - 1]], edge[filled[k]], edge[filled[k + 1]]].sorted()[1]
        }
        func point(_ u: Double, _ v: Double) -> CGPoint {
            CGPoint(x: c0.x + u * ax + v * nx, y: c0.y + u * ay + v * ny)
        }
        // Slice centres; the first and last edge run on to the box's ends, so base and mouth are flat.
        let us = filled.indices.map { k -> Double in
            k == 0 ? Double(filled[k]) / Double(slices) * length
                : k == filled.count - 1 ? Double(filled[k] + 1) / Double(slices) * length
                : (Double(filled[k]) + 0.5) / Double(slices) * length
        }
        let top = filled.indices.map { point(us[$0], median(high, $0)) }
        let bottom = filled.indices.reversed().map { point(us[$0], median(low, $0)) }
        return top + bottom
    }
}
