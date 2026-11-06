import CoreGraphics
import XCTest
@testable import Kaliberfinder

/// The green outline drawn over the photo follows the cartridge's shape (SHAPE-07): straight lines
/// along the bullet, neck and body from what was detected, joined into one.
final class ShapeContourTests: XCTestCase {
    private let ppm = 6.0
    private let step = 0.15

    private func cartridge(_ id: String) throws -> Cartridge {
        try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id)
    }

    /// Pixel position of outline point (x, y) in mm, turned by `angle`, as in the other shape tests.
    private func pixel(_ x: Double, _ y: Double, angle: Double) -> CGPoint {
        CGPoint(x: ppm * (x * cos(angle) - y * sin(angle)) + 500, y: ppm * (x * sin(angle) + y * cos(angle)) + 500)
    }

    /// The silhouette points of the cartridge (or its case) lying on its side, and its outline geometry.
    private func silhouette(_ c: Cartridge, caseOnly: Bool, angle: Double) -> (points: [Point], geometry: OutlineGeometry, top: Double) {
        let g = OutlineGeometry(c.outline, includeBullet: !caseOnly)
        let top = caseOnly ? c.outline.height - c.dimensions.caseLength : 0
        var points: [Point] = []
        var y = top + step / 2
        while y < c.outline.height {
            var x = step / 2
            while x < c.outline.width {
                if g.contains(Point(x: x, y: y)) {
                    let p = pixel(x, y, angle: angle)
                    points.append(Point(x: p.x, y: p.y))
                }
                x += step
            }
            y += step
        }
        return (points, g, top)
    }

    /// Area of a closed polygon (shoelace).
    private func area(_ p: [CGPoint]) -> Double {
        abs(p.indices.reduce(0.0) { s, i in let a = p[i], b = p[(i + 1) % p.count]; return s + a.x * b.y - b.x * a.y }) / 2
    }

    /// The polygon for a cartridge, checked against the silhouette: it covers about the silhouette's
    /// area (straight lines cut a round bullet nose a little; far less than its box when the shape
    /// narrows), and no corner lies far off its edge
    /// (a pointed tip's corner sits up to half a slice ahead of the last silhouette point).
    private func check(_ id: String, caseOnly: Bool, angle: Double) throws -> (polygon: [CGPoint], boxArea: Double, silhouetteArea: Double) {
        let c = try cartridge(id)
        let (points, _, _) = silhouette(c, caseOnly: caseOnly, angle: angle)
        let pixelSize = ppm * step
        let box = try XCTUnwrap(ShapeMatcher.orientedBox(points, pixelSize: pixelSize))
        let shape = try XCTUnwrap(ShapeMatcher.measure(points, pixelSize: pixelSize), id)
        let polygon = try XCTUnwrap(ShapeContour.polygon(points, pixelSize: pixelSize, shape: shape, box: box), id)
        let silhouetteArea = Double(points.count) * pixelSize * pixelSize
        XCTAssertEqual(area(polygon), silhouetteArea, accuracy: 0.1 * silhouetteArea, "\(id) angle \(angle)")
        for corner in polygon {
            let nearest = points.map { hypot($0.x - corner.x, $0.y - corner.y) }.min() ?? .infinity
            XCTAssertLessThan(nearest, 5 * pixelSize, "\(id) angle \(angle)")
        }
        let boxArea = hypot(box[1].x - box[0].x, box[1].y - box[0].y) * hypot(box[3].x - box[0].x, box[3].y - box[0].y)
        return (polygon, boxArea, silhouetteArea)
    }

    func testOutlineFollowsTheNeckOfAnEmptyGP11Case() throws {
        for angle in [0.7, 0.7 + .pi, 2.0] {
            let (polygon, boxArea, silhouetteArea) = try check("7.5x55 mm Swiss (GP 11)", caseOnly: true, angle: angle)
            // The neck and shoulder are cut out of the box.
            XCTAssertLessThan(silhouetteArea, 0.95 * boxArea, "angle \(angle)")
            // Straight lines only: mouth, neck end, shoulder, head on each side.
            XCTAssertEqual(polygon.count, 8, "angle \(angle)")
        }
    }

    func testOutlineFollowsTheBulletOfALoadedRound() throws {
        let (polygon, boxArea, silhouetteArea) = try check("7.5x55 mm Swiss (GP 11)", caseOnly: false, angle: 0.7)
        XCTAssertLessThan(silhouetteArea, 0.9 * boxArea)
        // The pointed bullet: the outline comes close to the tip.
        let gp11 = try cartridge("7.5x55 mm Swiss (GP 11)")
        let tip = pixel(gp11.outline.width / 2, 0, angle: 0.7)
        let nearest = polygon.map { hypot($0.x - tip.x, $0.y - tip.y) }.min() ?? .infinity
        XCTAssertLessThan(nearest / ppm, 1.5)
    }

    func testStraightCartridge() throws {
        _ = try check("9x19 mm", caseOnly: false, angle: 2.0)
    }

    func testNoOutlineWithoutABoxOrForAnEndView() throws {
        let shape = try XCTUnwrap(ShapeMatcher.catalogue["9x19 mm"])
        let square = [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 0, y: 1)]
        XCTAssertNil(ShapeContour.polygon([Point(x: 1, y: 1)], pixelSize: 1, shape: shape, box: []))
        XCTAssertNil(ShapeContour.polygon([], pixelSize: 1, shape: shape, box: square))
        XCTAssertNil(ShapeContour.polygon([Point(x: 1, y: 1)], pixelSize: 1, shape: ShapeMeasurement(aspect: 1, profile: [1]), box: square))
    }

    func testNoColourLegendUnderThePhoto() throws {
        let gp11 = try cartridge("7.5x55 mm Swiss (GP 11)")
        let notes = MatchesView.notes(for: PhotoAnalysis(shape: ShapeMatcher.catalogue[gp11.id], contour: [.zero]), mode: .cartridge)
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].contains("Flaschenhals".loc), notes[0])
    }
}
