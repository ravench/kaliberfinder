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
        // Raven's GP 11 case on granite (colour cut-out; the photo is in the training data): the blurred shoulder
        // shows a flat step at 0.8, but the neck is the run at about 0.6 in front of it.
        let granite = "0.50 0.62 0.59 0.60 0.59 0.61 0.80 0.78 0.87 1.01 0.95 0.92 0.93 0.90 1.00 1.01 1.02 1.02 1.00 1.00 "
            + "0.97 1.01 0.94 0.99 1.00 0.94 1.00 0.97 1.01 0.99 0.98 0.96 0.96 0.94 0.94 0.95 0.92 0.95 0.92 0.75"
        let real = try XCTUnwrap(NeckShape(widths: granite.split(separator: " ").compactMap { Double($0) }, aspect: 3.9))
        XCTAssertEqual(real.width, 0.6, accuracy: 0.01)
        XCTAssertEqual(real.slices, 1...5)
        XCTAssertEqual(real.shoulderSlice, 8)
        // The same with a body slice a little under 0.9, as in the photo itself.
        var noisy = granite.split(separator: " ").compactMap { Double($0) }
        noisy[13] = 0.89
        XCTAssertEqual(NeckShape(widths: noisy, aspect: 3.9)?.slices, 1...5)
        // A round-nose bullet with a short flat on its curve is no neck.
        let roundNose = [0.2, 0.3, 0.4, 0.5, 0.6, 0.62, 0.75, 0.8, 0.84] + Array(repeating: 1.0, count: 31)
        XCTAssertNil(NeckShape(widths: roundNose, aspect: 3))
        // Too wide for a neck: the bullet of a straight case.
        XCTAssertNil(NeckShape(widths: Array(repeating: 0.88, count: 6) + Array(repeating: 1.0, count: 34), aspect: 3))
    }

    // MARK: - Matching

    func testNeckUpToTheMouthIsAnEmptyCase() {
        // Raven's set-gp11-case-02 (colour cut-out): the half-filled first slice hides the square
        // mouth, but the neck runs up to it. Raven 2026-11-05: «Erkannt: Patrone» for this case.
        let widths = "0.51 0.60 0.63 0.72 0.61 0.70 1.03 1.07 0.91 0.94 0.97 0.98 0.99 0.98 0.99 0.96 0.98 0.96 0.97 0.97 "
            + "0.97 0.98 0.97 0.98 0.99 1.01 1.00 1.02 0.99 1.00 1.03 1.01 1.04 0.99 1.01 0.99 0.98 0.90 0.86 0.86"
        let shape = ShapeMatcher.measurement(aspect: 4.47, relativeWidths: widths.split(separator: " ").compactMap { Double($0) })
        XCTAssertEqual(shape.features?.isFlatEnd, false)
        XCTAssertEqual(ScanMode.auto.part(for: shape), .emptyCase)
        // Loaded bottleneck rounds stay cartridges: the bullet narrows in front of the neck.
        for id in ["7.5x55 mm Swiss (GP 11)", ".223 Remington", "6.5 mm Creedmoor", "7.62x39 mm"] {
            XCTAssertEqual(ScanMode.auto.part(for: try XCTUnwrap(ShapeMatcher.catalogue[id])), .cartridge, id)
        }
    }

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
}
