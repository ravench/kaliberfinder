import CoreGraphics
import XCTest
@testable import Kaliberfinder

/// The neck and taper lines drawn over the photo (SHAPE-07).
final class ShapeLinesTests: XCTestCase {
    private let ppm = 6.0

    private func cartridge(_ id: String) throws -> Cartridge {
        try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id)
    }

    /// Pixel position of outline point (x, y) in mm, turned by `angle`, as in the other shape tests.
    private func pixel(_ x: Double, _ y: Double, angle: Double) -> CGPoint {
        CGPoint(x: ppm * (x * cos(angle) - y * sin(angle)) + 500, y: ppm * (x * sin(angle) + y * cos(angle)) + 500)
    }

    /// The lines for a photo of the cartridge (or its case) lying on its side, plus where its front
    /// (tip or case mouth) and its base are in the picture.
    private func lines(_ c: Cartridge, part: ShapePart, angle: Double = 0.7) throws -> (lines: ShapeLines, front: CGPoint, base: CGPoint) {
        let step = 0.15
        let caseOnly = part == .emptyCase
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
        let shape = try XCTUnwrap(ShapeMatcher.measure(points, pixelSize: ppm * step), c.id)
        let box = try XCTUnwrap(ShapeMatcher.orientedBox(points, pixelSize: ppm * step))
        let found = try XCTUnwrap(ShapeLines(points: points, pixelSize: ppm * step, shape: shape, box: box), c.id)
        let mid = c.outline.width / 2
        return (found, pixel(mid, top, angle: angle), pixel(mid, c.outline.height, angle: angle))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }

    func testNeckAndTaperOfAnEmptyGP11Case() throws {
        let gp11 = try cartridge("7.5x55 mm Swiss (GP 11)")
        let d = gp11.dimensions
        // Lying either way round, the neck is drawn at the case mouth and the taper runs to the head.
        for angle in [0.7, 0.7 + .pi, 2.0] {
            let (lines, mouth, head) = try lines(gp11, part: .emptyCase, angle: angle)
            XCTAssertEqual(lines.neck.count, 2)
            XCTAssertEqual(lines.taper.count, 2)
            let neck = lines.neck[0], other = lines.neck[1]
            XCTAssertEqual(neck.count, 3)
            XCTAssertLessThan(distance(neck[0], mouth), distance(neck[0], head), "angle \(angle)")
            XCTAssertLessThan(distance(lines.taper[0][1], head), distance(lines.taper[0][1], mouth), "angle \(angle)")
            // The two sides lie a neck diameter apart at the mouth, and a body diameter apart at the head.
            XCTAssertEqual(distance(neck[0], other[0]) / ppm, d.neck, accuracy: 0.12 * d.neck, "angle \(angle)")
            XCTAssertEqual(distance(lines.taper[0][1], lines.taper[1][1]) / ppm, d.base, accuracy: 0.08 * d.base, "angle \(angle)")
            // The neck runs from the mouth to the shoulder: about as long as the catalogue neck.
            let shoulderTop = try XCTUnwrap(ShapeMatcher.caseCatalogue[gp11.id]?.neck).length * d.base
            XCTAssertEqual(distance(neck[0], neck[1]) / ppm, shoulderTop, accuracy: 2, "angle \(angle)")
        }
    }

    func testStraightCartridgeHasOnlyTheTaper() throws {
        let nine = try cartridge("9x19 mm")
        let (lines, _, head) = try lines(nine, part: .cartridge)
        XCTAssertTrue(lines.neck.isEmpty)
        XCTAssertEqual(lines.taper.count, 2)
        XCTAssertEqual(distance(lines.taper[0][1], lines.taper[1][1]) / ppm, nine.dimensions.base, accuracy: 1)
        XCTAssertLessThan(distance(lines.taper[0][1], head), 2 * ppm * nine.dimensions.base)
    }

    func testLoadedBottleneckIsShownAsBottleneck() throws {
        let gp11 = try cartridge("7.5x55 mm Swiss (GP 11)")
        let (lines, tip, head) = try lines(gp11, part: .cartridge)
        XCTAssertEqual(lines.neck.count, 2)
        XCTAssertLessThan(distance(lines.neck[0][0], tip), distance(lines.neck[0][0], head))
        let analysis = PhotoAnalysis(shape: ShapeMatcher.catalogue[gp11.id], lines: lines)
        let notes = MatchesView.notes(for: analysis, mode: .cartridge)
        XCTAssertTrue(notes[0].contains("Flaschenhals".loc), notes[0])
        XCTAssertEqual(notes[1], "Orange: Hals und Schulter, hellblau: Verjüngung des Körpers.".loc)
        // Without lines (built by hand) there is no legend.
        XCTAssertEqual(MatchesView.notes(for: PhotoAnalysis(shape: ShapeMatcher.catalogue[gp11.id]), mode: .cartridge).count, 1)
    }

    func testLinesFollowTheCutOut() {
        let lines = ShapeLines(neck: [[CGPoint(x: 0.5, y: 0.5)]], taper: [[CGPoint(x: 1, y: 0)]])
        let moved = lines.map { CGPoint(x: 0.1 + $0.x * 0.5, y: 0.2 + $0.y * 0.5) }
        XCTAssertEqual(moved.neck, [[CGPoint(x: 0.35, y: 0.45)]])
        XCTAssertEqual(moved.taper, [[CGPoint(x: 0.6, y: 0.2)]])
        XCTAssertTrue(ShapeLines().isEmpty)
        XCTAssertNil(ShapeLines(points: [], pixelSize: 1, shape: ShapeMeasurement(aspect: 1, profile: [1]), box: []))
    }
}
