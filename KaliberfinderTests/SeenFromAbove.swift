@testable import Kaliberfinder
import Foundation

/// A calibre lying on a table as a camera straight above sees it (`EndRise`): the silhouette's pixels,
/// `pixelSize` apart, with the camera `distance` mm above the table, over the middle of the cartridge,
/// at a focal length of `focal` pixels. Every point of the top surface is projected from its own height:
/// the axis lies half a body diameter up, the ends' top edges higher.
enum SeenFromAbove {
    static func silhouette(of c: Cartridge, part: ShapePart = .cartridge, distance: Double, focal: Double,
                           step: Double = 0.1) -> (points: [Point], pixelSize: Double) {
        let g = OutlineGeometry(c.outline, includeBullet: part == .cartridge)
        let height = c.outline.height, top = part == .emptyCase ? height - c.dimensions.caseLength : 0
        let axisHeight = c.dimensions.base / 2, middle = (top + height) / 2
        var points: [Point] = []
        var a = top + step / 2
        while a < height {
            let radius = g.width(at: a) / 2
            var l = -radius + step / 2
            while l < radius {
                let z = distance - axisHeight - (radius * radius - l * l).squareRoot()
                points.append(Point(x: focal * (a - middle) / z, y: focal * l / z))
                l += step
            }
            a += step
        }
        return (points, step * focal / (distance - axisHeight))
    }
}
