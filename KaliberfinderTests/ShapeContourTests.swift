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
    /// narrows), and no corner lies more than 1 mm off its edge (the straight lines are fitted,
    /// and the neck's width runs on over a slimmer bullet).
    private func check(_ id: String, caseOnly: Bool, angle: Double) throws -> (polygon: ShapeContour, boxArea: Double, silhouetteArea: Double) {
        let c = try cartridge(id)
        let (points, _, _) = silhouette(c, caseOnly: caseOnly, angle: angle)
        let pixelSize = ppm * step
        let box = try XCTUnwrap(ShapeMatcher.orientedBox(points, pixelSize: pixelSize))
        let shape = try XCTUnwrap(ShapeMatcher.measure(points, pixelSize: pixelSize), id)
        let polygon = try XCTUnwrap(ShapeContour.polygon(points, pixelSize: pixelSize, shape: shape, box: box), id)
        XCTAssertEqual(polygon.parts.count, polygon.points.count, id)
        let silhouetteArea = Double(points.count) * pixelSize * pixelSize
        XCTAssertEqual(area(polygon.points), silhouetteArea, accuracy: 0.1 * silhouetteArea, "\(id) angle \(angle)")
        for corner in polygon.points {
            let nearest = points.map { hypot($0.x - corner.x, $0.y - corner.y) }.min() ?? .infinity
            XCTAssertLessThan(nearest / ppm, 1, "\(id) angle \(angle)")
        }
        let boxArea = hypot(box[1].x - box[0].x, box[1].y - box[0].y) * hypot(box[3].x - box[0].x, box[3].y - box[0].y)
        return (polygon, boxArea, silhouetteArea)
    }

    func testOutlineFollowsTheNeckOfAnEmptyGP11Case() throws {
        for angle in [0.7, 0.7 + .pi, 2.0] {
            let (polygon, boxArea, silhouetteArea) = try check("7.5x55 mm Swiss (GP 11)", caseOnly: true, angle: angle)
            // The neck and shoulder are cut out of the box.
            XCTAssertLessThan(silhouetteArea, 0.95 * boxArea, "angle \(angle)")
            // Straight lines only: mouth, neck end, shoulder, head on each side; each edge from its detection.
            XCTAssertEqual(polygon.parts, [.neck, .neck, .body, .end, .body, .neck, .neck, .end], "angle \(angle)")
        }
    }

    func testOutlineFollowsTheBulletOfALoadedRound() throws {
        let (polygon, boxArea, silhouetteArea) = try check("7.5x55 mm Swiss (GP 11)", caseOnly: false, angle: 0.7)
        XCTAssertLessThan(silhouetteArea, 0.9 * boxArea)
        // The pointed bullet: the outline comes close to the tip.
        let gp11 = try cartridge("7.5x55 mm Swiss (GP 11)")
        let tip = pixel(gp11.outline.width / 2, 0, angle: 0.7)
        let nearest = polygon.points.map { hypot($0.x - tip.x, $0.y - tip.y) }.min() ?? .infinity
        XCTAssertLessThan(nearest / ppm, 1.5)
        // The bullet's edges start each side, from the tip, and the tip is an end.
        XCTAssertEqual(polygon.parts.first, .bullet)
        XCTAssertEqual(polygon.parts.last, .end)
        XCTAssertTrue(polygon.parts.contains(.neck))
    }

    func testStraightCartridge() throws {
        let (polygon, _, _) = try check("9x19 mm", caseOnly: false, angle: 2.0)
        XCTAssertFalse(polygon.parts.contains(.neck))
        XCTAssertTrue(polygon.parts.contains(.body))
    }

    func testNoOutlineWithoutABoxOrForAnEndView() throws {
        let shape = try XCTUnwrap(ShapeMatcher.catalogue["9x19 mm"])
        let square = [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 0, y: 1)]
        XCTAssertNil(ShapeContour.polygon([Point(x: 1, y: 1)], pixelSize: 1, shape: shape, box: []))
        XCTAssertNil(ShapeContour.polygon([], pixelSize: 1, shape: shape, box: square))
        // Seen end on: round, so no outline even with a full set of widths.
        let endView = ShapeMatcher.measurement(aspect: 1, relativeWidths: Array(repeating: 1, count: ShapeMatcher.bins))
        XCTAssertTrue(endView.isEndView)
        XCTAssertNil(ShapeContour.polygon([Point(x: 1, y: 1)], pixelSize: 1, shape: endView, box: square))
    }

    func testPartsKeepTheirEdgesWhenMoved() {
        let contour = ShapeContour(points: [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 0)], parts: [.body, .end])
        let moved = contour.map { CGPoint(x: 0.1 + $0.x * 0.5, y: 0.2 + $0.y * 0.5) }
        XCTAssertEqual(moved.points, [CGPoint(x: 0.35, y: 0.45), CGPoint(x: 0.6, y: 0.2)])
        XCTAssertEqual(moved.parts, [.body, .end])
        // Coloured drawing: each part's edges only, the last edge back to the first corner.
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 5)]
        XCTAssertEqual(CandidatePhotoView.path(edges: [2], of: corners).boundingRect, CGRect(x: 0, y: 0, width: 10, height: 5))
        XCTAssertTrue(CandidatePhotoView.path(edges: [], of: corners).isEmpty)
        XCTAssertEqual(Set(CandidatePhotoView.coloured.map(\.part)).count, 4)
    }

    func testNoColourLegendUnderThePhoto() throws {
        let gp11 = try cartridge("7.5x55 mm Swiss (GP 11)")
        let notes = MatchesView.notes(for: PhotoAnalysis(shape: ShapeMatcher.catalogue[gp11.id], contour: ShapeContour(points: [.zero], parts: [.end])), mode: .cartridge)
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].contains("Flaschenhals".loc), notes[0])
    }
}
