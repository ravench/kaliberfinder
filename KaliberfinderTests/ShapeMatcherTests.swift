import XCTest
@testable import Kaliberfinder

final class ShapeMatcherTests: XCTestCase {
    /// Pixels inside a cartridge's outline, as a photo of it lying on its side would give:
    /// rotated by `angle`, `pixelsPerMM` pixels per millimetre, sampled every `step` mm.
    private func measure(_ c: Cartridge, angle: Double, pixelsPerMM: Double, step: Double = 0.3) -> ShapeMeasurement? {
        ShapeMatcher.measure(silhouette(c, angle: angle, pixelsPerMM: pixelsPerMM, step: step), pixelSize: pixelsPerMM * step)
    }

    private func silhouette(_ c: Cartridge, angle: Double, pixelsPerMM: Double, step: Double) -> [Point] {
        let g = OutlineGeometry(c.outline)
        var points: [Point] = []
        var y = step / 2
        while y < c.outline.height {
            var x = step / 2
            while x < c.outline.width {
                if g.contains(Point(x: x, y: y)) {
                    points.append(Point(x: pixelsPerMM * (x * cos(angle) - y * sin(angle)) + 500,
                                        y: pixelsPerMM * (x * sin(angle) + y * cos(angle)) + 300))
                }
                x += step
            }
            y += step
        }
        return points
    }

    private func rank(of c: Cartridge, angle: Double, pixelsPerMM: Double) throws -> Int {
        try XCTUnwrap(rankIfListed(of: c, angle: angle, pixelsPerMM: pixelsPerMM), c.name)
    }

    /// Nil when the calibre is not listed at all, e.g. the .22 BB Cap, which is nearly as wide as long.
    private func rankIfListed(of c: Cartridge, angle: Double, pixelsPerMM: Double) throws -> Int? {
        let m = try XCTUnwrap(measure(c, angle: angle, pixelsPerMM: pixelsPerMM), c.name)
        let ranked = Matcher.rank(shape: m, cartridges: CartridgeCatalog.all, limit: .max)
        return ranked.firstIndex { $0.cartridge.id == c.id }
    }

    func testCommonCalibresAreAmongTheFirstFive() throws {
        let ids = ["9x19 mm", ".308 Winchester", "7.5x55 mm Swiss (GP 11)", "5.6 mm GP 90", ".22 LR",
                   ".45 ACP", ".38 Special", ".357 Magnum", "12/70", ".50 BMG"]
        for (i, id) in ids.enumerated() {
            let c = try XCTUnwrap(CartridgeCatalog.cartridge(id: id))
            let r = try rank(of: c, angle: 0.4 + Double(i) * 0.55, pixelsPerMM: 4 + Double(i))
            XCTAssertLessThan(r, 5, "\(id) ranked \(r + 1)")
        }
    }

    func testMostOfTheCatalogueIsAmongTheFirstFive() throws {
        let ranks = try CartridgeCatalog.all.enumerated().map { i, c in
            try rankIfListed(of: c, angle: Double(i % 7) * 0.45, pixelsPerMM: 5 + Double(i % 4))
        }
        let found = ranks.filter { ($0 ?? .max) < 5 }.count
        XCTAssertGreaterThanOrEqual(Double(found) / Double(CartridgeCatalog.all.count), 0.95)
    }

    func testMeasurementDoesNotDependOnRotationOrScale() throws {
        let c = try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5x55 mm Swiss (GP 11)"))
        let a = try XCTUnwrap(measure(c, angle: 0, pixelsPerMM: 4))
        let b = try XCTUnwrap(measure(c, angle: 2.5, pixelsPerMM: 9))
        XCTAssertEqual(a.aspect, b.aspect, accuracy: 0.25)
        XCTAssertLessThan(ShapeMatcher.distance(a, b), 0.2)
    }

    func testMeasurementMatchesExpectedShape() throws {
        let c = try XCTUnwrap(CartridgeCatalog.cartridge(id: "9x19 mm"))
        let measured = try XCTUnwrap(measure(c, angle: 1, pixelsPerMM: 6))
        let expected = try XCTUnwrap(ShapeMatcher.expected(for: c))
        XCTAssertEqual(expected.aspect, 29.7 / 9.96, accuracy: 0.1)
        XCTAssertLessThan(ShapeMatcher.distance(measured, expected), 0.1)
        // Tip first: narrow at the start, full width at the base.
        XCTAssertLessThan(measured.profile[0], 0.8)
        XCTAssertGreaterThan(measured.profile[ShapeMatcher.fractions.count - 1], 0.9)
    }

    func testDiscIsAnEndView() throws {
        var disc: [Point] = []
        for x in -50...50 {
            for y in -50...50 where x * x + y * y <= 2500 { disc.append(Point(x: Double(x), y: Double(y))) }
        }
        let m = try XCTUnwrap(ShapeMatcher.measure(disc))
        XCTAssertTrue(m.isEndView)
        XCTAssertFalse(try XCTUnwrap(ShapeMatcher.expected(for: XCTUnwrap(CartridgeCatalog.cartridge(id: "9x19 mm")))).isEndView)
    }

    func testTooFewPointsGiveNoMeasurement() {
        XCTAssertNil(ShapeMatcher.measure([]))
        XCTAssertNil(ShapeMatcher.measure(Array(repeating: Point(x: 1, y: 1), count: 100)))
    }

    func testSignatureTurnsTipFirst() throws {
        var widths = [Double](repeating: 10, count: ShapeMatcher.bins)
        widths[0] = 2
        widths[1] = 4
        let forward = try XCTUnwrap(ShapeMatcher.signature(widths: widths, length: 30))
        let backward = try XCTUnwrap(ShapeMatcher.signature(widths: widths.reversed(), length: 30))
        XCTAssertEqual(forward, backward)
        XCTAssertEqual(forward.aspect, 3, accuracy: 0.001)
        XCTAssertNil(ShapeMatcher.signature(widths: [1, 2], length: 3))
    }

    func testDistance() {
        let a = ShapeMeasurement(aspect: 3, profile: [0.5, 1])
        XCTAssertEqual(ShapeMatcher.distance(a, a), 0)
        XCTAssertGreaterThan(ShapeMatcher.distance(a, ShapeMeasurement(aspect: 6, profile: [0.5, 1])), 2)
        XCTAssertEqual(ShapeMatcher.distance(a, ShapeMeasurement(aspect: 3, profile: [1])), .infinity)
    }

    func testEveryCatalogueCartridgeHasAShape() {
        XCTAssertEqual(ShapeMatcher.catalogue.count, CartridgeCatalog.all.count)
    }
}
