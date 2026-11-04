import XCTest
@testable import Kaliberfinder

final class DimensionMatcherTests: XCTestCase {
    func testFindsNineMillimetreFromCalliperValues() {
        let m = MeasuredDimensions(overallLength: 29.7, caseLength: 19.15, rim: 9.96, bullet: nil)
        let matches = DimensionMatcher.rank(m)
        XCTAssertEqual(matches.first?.cartridge.id, "9x19 mm")
        XCTAssertEqual(matches.first?.fit, .good)
        XCTAssertEqual(matches.first?.maxDeviation ?? 1, 0, accuracy: 0.001)
        // 9x21 has a 2 mm longer case, so it comes later and doesn't fit exactly.
        let nineByTwentyOne = matches.first { $0.cartridge.id == "9x21 mm IMI" }
        XCTAssertNotEqual(nineByTwentyOne?.fit, .good)
    }

    func testTwoValuesAreEnoughForGP11() {
        let matches = DimensionMatcher.rank(MeasuredDimensions(overallLength: 77.5, rim: 12.6))
        XCTAssertEqual(matches.first?.cartridge.id, "7.5x55 mm Swiss (GP 11)")
    }

    func testShorterCaseTellsGP1890FromGP11() {
        let matches = DimensionMatcher.rank(MeasuredDimensions(overallLength: 77.0, caseLength: 53.5, rim: 12.5))
        XCTAssertEqual(matches.first?.cartridge.id, "7.5x53.5 mm Swiss (GP 1890)")
        XCTAssertEqual(matches.first?.fit, .good)
        let gp11 = matches.first { $0.cartridge.id == "7.5x55 mm Swiss (GP 11)" }
        XCTAssertNotEqual(gp11?.fit, .good, "GP 11's case is 2 mm longer")
    }

    func testGP1890IsOnlyFoundWithObsoleteCalibresSwitchedOn() {
        let gp1890 = MeasuredDimensions(overallLength: 77.0, caseLength: 53.5, rim: 12.5)
        let without = DimensionMatcher.rank(gp1890, cartridges: CartridgeCatalog.matchable(includeObsolete: false))
        XCTAssertFalse(without.contains { $0.cartridge.id == "7.5x53.5 mm Swiss (GP 1890)" })
        let with = DimensionMatcher.rank(gp1890, cartridges: CartridgeCatalog.matchable(includeObsolete: true))
        XCTAssertEqual(with.first?.cartridge.id, "7.5x53.5 mm Swiss (GP 1890)")
    }

    func testIdenticalCalibresTie() {
        let matches = DimensionMatcher.rank(MeasuredDimensions(overallLength: 71.1, caseLength: 51.2, rim: 11.9))
        XCTAssertEqual(Set(matches.prefix(2).map(\.cartridge.id)), [".308 Winchester", "7.62x51 mm NATO"])
    }

    func testSmallDifferencesAreWithinTolerance() {
        let matches = DimensionMatcher.rank(MeasuredDimensions(overallLength: 25.5, rim: 6.85))
        XCTAssertEqual(matches.first?.cartridge.id, ".22 LR")
        XCTAssertEqual(matches.first?.fit, .good)
    }

    func testRoughAndPoorFits() throws {
        let c = try XCTUnwrap(CartridgeCatalog.cartridge(id: "9x19 mm"))
        XCTAssertEqual(DimensionMatch(cartridge: c, maxDeviation: 0.6, meanDeviation: 0.3).fit, .rough)
        XCTAssertEqual(DimensionMatch(cartridge: c, maxDeviation: 2, meanDeviation: 1).fit, .poor)
    }

    func testEmptyMeasurementGivesNothing() {
        XCTAssertTrue(MeasuredDimensions().isEmpty)
        XCTAssertTrue(DimensionMatcher.rank(MeasuredDimensions()).isEmpty)
    }

    func testLimit() {
        XCTAssertEqual(DimensionMatcher.rank(MeasuredDimensions(overallLength: 30)).count, 10)
        XCTAssertEqual(DimensionMatcher.rank(MeasuredDimensions(overallLength: 30), limit: 3).count, 3)
    }

    func testParsesBothDecimalSeparators() {
        XCTAssertEqual(DimensionMatcher.number("29,7"), 29.7)
        XCTAssertEqual(DimensionMatcher.number(" 29.7 "), 29.7)
        XCTAssertEqual(DimensionMatcher.number("12"), 12)
        XCTAssertNil(DimensionMatcher.number(""))
        XCTAssertNil(DimensionMatcher.number("abc"))
        XCTAssertNil(DimensionMatcher.number("-3"))
        XCTAssertNil(DimensionMatcher.number("0"))
    }

    func testDetailText() throws {
        let c = try XCTUnwrap(CartridgeCatalog.cartridge(id: "9x19 mm"))
        let exact = MeasureView.detail(for: DimensionMatch(cartridge: c, maxDeviation: 0, meanDeviation: 0))
        let off = MeasureView.detail(for: DimensionMatch(cartridge: c, maxDeviation: 1.5, meanDeviation: 1))
        XCTAssertFalse(exact.isEmpty)
        XCTAssertNotEqual(exact, off)
        XCTAssertTrue(off.contains("mm"))
    }
}
