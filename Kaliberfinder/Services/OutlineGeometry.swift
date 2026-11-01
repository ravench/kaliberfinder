import Foundation

/// A point in millimetres or pixels. Plain Doubles keep the geometry free of CGFloat conversions.
struct Point: Hashable {
    var x: Double
    var y: Double
}

/// Polygons of a cartridge outline (millimetres) and simple measurements on them.
/// The generated outlines only use the SVG commands M, L and Z.
struct OutlineGeometry {
    let polygons: [[Point]]
    let width: Double
    let height: Double

    init(_ outline: Cartridge.Outline) {
        polygons = [outline.case, outline.head, outline.bullet].compactMap { $0 }.flatMap(Self.parse)
        width = outline.width
        height = outline.height
    }

    /// Parses "M x y L x y … Z" path data into closed polygons.
    static func parse(_ d: String) -> [[Point]] {
        var result: [[Point]] = []
        var current: [Point] = []
        var numbers: [Double] = []
        func flushPoint() {
            if numbers.count == 2 { current.append(Point(x: numbers[0], y: numbers[1])) }
            numbers = []
        }
        var token = ""
        func flushToken() {
            if let n = Double(token) { numbers.append(n); if numbers.count == 2 { flushPoint() } }
            token = ""
        }
        for ch in d {
            switch ch {
            case "M":
                flushToken()
                if current.count > 1 { result.append(current) }
                current = []
            case "L":
                flushToken()
            case "Z", "z":
                flushToken()
                if current.count > 1 { result.append(current) }
                current = []
            case " ", ",":
                flushToken()
            default:
                token.append(ch)
            }
        }
        flushToken()
        if current.count > 1 { result.append(current) }
        return result
    }

    /// Horizontal extent of the outline at height `y` (0 where the outline is empty).
    func width(at y: Double) -> Double {
        var minX = Double.infinity, maxX = -Double.infinity
        for poly in polygons {
            for i in poly.indices {
                let a = poly[i], b = poly[(i + 1) % poly.count]
                let lo = min(a.y, b.y), hi = max(a.y, b.y)
                guard y >= lo, y <= hi else { continue }
                if a.y == b.y {
                    minX = min(minX, a.x, b.x); maxX = max(maxX, a.x, b.x)
                } else {
                    let x = a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x)
                    minX = min(minX, x); maxX = max(maxX, x)
                }
            }
        }
        return maxX > minX ? maxX - minX : 0
    }

    /// Whether `p` lies inside any of the polygons (even-odd rule per polygon).
    func contains(_ p: Point) -> Bool {
        polygons.contains { poly in
            var inside = false
            var j = poly.count - 1
            for i in poly.indices {
                let a = poly[i], b = poly[j]
                if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                    inside.toggle()
                }
                j = i
            }
            return inside
        }
    }
}
