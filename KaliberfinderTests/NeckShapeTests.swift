import UIKit
import XCTest
@testable import Kaliberfinder

/// The neck of bottleneck cases in the silhouette and in matching (SHAPE-06).
final class NeckShapeTests: XCTestCase {
    private func cartridge(_ id: String) throws -> Cartridge {
        try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id)
    }

    /// Pixels inside a cartridge (or only its case) lying on its side, as in `EmptyCaseTests`.
    private func photo(_ c: Cartridge, part: ShapePart, angle: Double = 0.7, pixelsPerMM: Double = 6,
                       step: Double = 0.15) throws -> ShapeMeasurement {
        let caseOnly = part == .emptyCase
        let g = OutlineGeometry(c.outline, includeBullet: !caseOnly)
        let top = caseOnly ? c.outline.height - c.dimensions.caseLength : 0
        var points: [Point] = []
        var y = top + step / 2
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
        return try XCTUnwrap(ShapeMatcher.measure(points, pixelSize: pixelsPerMM * step), c.id)
    }

    // MARK: - Finding the neck

    func testBottleneckCasesShowTheirNeck() throws {
        for id in ["7.5x55 mm Swiss (GP 11)", ".308 Winchester", ".223 Remington", "6.5 mm Creedmoor"] {
            let c = try cartridge(id)
            let expected = c.dimensions.neck / c.dimensions.base
            for part in [ShapePart.cartridge, .emptyCase] {
                let neck = try XCTUnwrap(ShapeMatcher.expected(for: c, part: part)?.neck, "\(id) \(part)")
                XCTAssertTrue(neck.isClear, "\(id) \(part)")
                XCTAssertEqual(neck.width, expected, accuracy: 0.05, "\(id) \(part)")
                XCTAssertGreaterThan(neck.slices.count, 1)
                XCTAssertGreaterThanOrEqual(neck.shoulderSlice, neck.slices.upperBound)
            }
            // The photo of the case finds the same neck as the outline.
            let measured = try XCTUnwrap(photo(c, part: .emptyCase).mouthFirst().neck, id)
            let outline = try XCTUnwrap(ShapeMatcher.caseCatalogue[id]?.neck, id)
            XCTAssertEqual(measured.width, outline.width, accuracy: 0.05, id)
            XCTAssertEqual(measured.length, outline.length, accuracy: 0.25, id)
        }
    }

    func testStraightCasesShowNoNeck() throws {
        for id in ["9x19 mm", ".45 ACP", ".38 Special", ".30 Carbine", ".450 Bushmaster", ".460 S&W Magnum"] {
            let c = try cartridge(id)
            XCTAssertNil(ShapeMatcher.expected(for: c)?.neck, id)
            XCTAssertNil(ShapeMatcher.expected(for: c, part: .emptyCase)?.neck, id)
            XCTAssertNil(try photo(c, part: .cartridge).neck, id)
        }
    }

    func testNeckLengthAndWidthComeFromTheSlices() throws {
        // Tip first: a neck 0.6 wide over `n` slices, a two-slice shoulder, the body, a rimless head.
        func widths(neck n: Int) -> [Double] {
            Array(repeating: 0.6, count: n) + [0.7, 0.85] + Array(repeating: 1.0, count: 38 - n - 4) + [0.82, 1.0, 1.0, 1.0]
        }
        let short = try XCTUnwrap(NeckShape(widths: widths(neck: 4), aspect: 4))
        let long = try XCTUnwrap(NeckShape(widths: widths(neck: 8), aspect: 4))
        XCTAssertEqual(short.width, 0.6, accuracy: 1e-9)
        XCTAssertEqual(short.length, 0.4, accuracy: 1e-9)
        XCTAssertEqual(long.length, 0.8, accuracy: 1e-9)
        XCTAssertEqual(long.slices, 0...7)
        XCTAssertEqual(long.shoulderSlice, 9)
        let a = ShapeMatcher.measurement(aspect: 4, relativeWidths: widths(neck: 4))
        let b = ShapeMatcher.measurement(aspect: 4, relativeWidths: widths(neck: 8))
        XCTAssertEqual(NeckShape.distance(photo: a, expected: b, neckRatio: 0.6), NeckShape.lengthWeight * 0.4, accuracy: 1e-9)
        // Too wide for a neck: the bullet of a straight case.
        XCTAssertNil(NeckShape(widths: Array(repeating: 0.88, count: 6) + Array(repeating: 1.0, count: 34), aspect: 3))
    }

    // MARK: - Matching

    func testNeckedCaseTakenForACartridgeListsNoStraightCalibres() throws {
        // Raven 2026-11-05: an empty GP 11 case with the picker on «Patrone» listed .30 Carbine,
        // .450 Bushmaster and .460 S&W Magnum first, all without a neck.
        let shape = try photo(cartridge("7.5x55 mm Swiss (GP 11)"), part: .emptyCase)
        let matches = Matcher.rank(shape: shape, mode: .cartridge,
                                   cartridges: CartridgeCatalog.matchable(includeObsolete: true), limit: .max)
        let wide = matches.filter { $0.cartridge.dimensions.neck / $0.cartridge.dimensions.base > 0.85 }
        XCTAssertTrue(wide.isEmpty, wide.map(\.cartridge.id).joined(separator: ", "))
    }

    func testNeckedCartridgeListsNoStraightCalibres() throws {
        for id in ["7.5x55 mm Swiss (GP 11)", ".223 Remington", "7.62x39 mm"] {
            let matches = Matcher.rank(shape: try photo(cartridge(id), part: .cartridge),
                                       cartridges: CartridgeCatalog.matchable(includeObsolete: true), limit: .max)
            XCTAssertEqual(matches.first?.cartridge.dimensions.shoulder != nil, true, id)
            let straight = matches.filter { $0.cartridge.dimensions.shoulder == nil }
            XCTAssertTrue(straight.isEmpty, "\(id): \(straight.map(\.cartridge.id))")
        }
    }

    func testNeckAddsToTheDistance() throws {
        let gp11 = try cartridge("7.5x55 mm Swiss (GP 11)")
        let shape = try photo(gp11, part: .emptyCase)
        let own = try XCTUnwrap(ShapeMatcher.caseCatalogue[gp11.id])
        let ratio = gp11.dimensions.neck / gp11.dimensions.base
        let without = try XCTUnwrap(ShapeMatcher.distance(shape, to: own, part: .emptyCase))
        let with = try XCTUnwrap(ShapeMatcher.distance(shape, to: own, part: .emptyCase, neckRatio: ratio))
        XCTAssertEqual(with, without, accuracy: 0.05)
        // A straight case compared as a cartridge gets the full penalty.
        let carbine = try cartridge(".30 Carbine")
        let straight = try XCTUnwrap(ShapeMatcher.catalogue[carbine.id])
        XCTAssertEqual(NeckShape.distance(photo: shape, expected: straight,
                                          neckRatio: carbine.dimensions.neck / carbine.dimensions.base),
                       NeckShape.widerPenalty)
        // A calibre with a clear neck, photographed without one.
        let nine = try photo(cartridge("9x19 mm"), part: .cartridge)
        XCTAssertEqual(NeckShape.distance(photo: nine, expected: own, neckRatio: ratio), NeckShape.missingPenalty)
        // Shapes built by hand have no slice widths and no neck.
        XCTAssertNil(ShapeMeasurement(aspect: 3, profile: ShapeMatcher.fractions.map { _ in 1 }).neck)
    }

    // MARK: - Raven's photos

    /// The nine empty GP 11 cases of `PhotoSetTests`, through the photo analysis (the colour cut-out on
    /// the simulator): the neck must be found in most of them, with about the catalogue's width.
    func testRealGP11CasePhotosShowTheNeck() async throws {
        let ratio = 8.5 / 12.6
        var found = 0, lines: [String] = []
        for i in 1...9 {
            let name = String(format: "set-gp11-case-%02d", i)
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "jpg"), name)
            let image = try XCTUnwrap(UIImage(contentsOfFile: url.path), name)
            let analysis = await PhotoAnalyzer.analyze(image)
            let shape = try XCTUnwrap(analysis.shape, name)
            let neck = shape.mouthFirst().neck
            if let neck, abs(neck.width - ratio) < 0.08 { found += 1 }
            lines.append(String(format: "NECK %@ aspect %.2f neck %@ widths %@", name, shape.aspect,
                                neck.map { String(format: "%.2f x %.2f", $0.width, $0.length) } ?? "-",
                                shape.widths.map { String(format: "%.2f", $0) }.joined(separator: " ")))
        }
        print(lines.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(found, 7, lines.joined(separator: "\n"))
    }
}
