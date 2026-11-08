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

    /// A shotshell's length depends on its crimp: Raven's folded-crimp 12/70 shells measure 57.8 mm
    /// and his Remington 65.5 mm against the catalogue's 64.0 mm; all are 12/70.
    func testShotshellsOfEveryCrimpFitTheirGauge() throws {
        for length in [57.8, 58.2, 65.5] {
            let matches = DimensionMatcher.rank(MeasuredDimensions(overallLength: length, rim: 22.3))
            let twelve = try XCTUnwrap(matches.first { $0.cartridge.id == "12/70" }, "\(length)")
            XCTAssertEqual(twelve.fit, .good, "\(length)")
            XCTAssertEqual(matches.first?.cartridge.dimensions.rim, 22.3, "a 12-gauge shell first at \(length)")
        }
        for length in [57.8, 65.5] {
            XCTAssertEqual(DimensionMatcher.rank(MeasuredDimensions(overallLength: length, rim: 22.3)).first?.cartridge.id, "12/70",
                           "\(length) mm: 12/70 before 12/76")
        }
        let magnum = DimensionMatcher.rank(MeasuredDimensions(overallLength: 57.8, rim: 22.3)).first { $0.cartridge.id == "12/89" }
        XCTAssertNotEqual(magnum?.fit, .good)
    }

    func testOnlyShotshellsHaveALengthRange() throws {
        let shell = try XCTUnwrap(CartridgeCatalog.cartridge(id: "12/70"))
        XCTAssertEqual(shell.overallLengths.lowerBound, 64 * Cartridge.shellShortest, accuracy: 1e-9)
        XCTAssertEqual(shell.overallLengths.upperBound, 64 * Cartridge.shellLongest, accuracy: 1e-9)
        let nine = try XCTUnwrap(CartridgeCatalog.cartridge(id: "9x19 mm"))
        XCTAssertEqual(nine.overallLengths, 29.7...29.7)
        XCTAssertEqual(DimensionMatcher.outside(29, 29.7...29.7), 0.7, accuracy: 1e-9)
        XCTAssertEqual(DimensionMatcher.outside(60, 57.6...65.9), 0)
    }

    func testTwoValuesAreEnoughForGP11() {
        let matches = DimensionMatcher.rank(MeasuredDimensions(overallLength: 77.5, rim: 12.6))
        XCTAssertEqual(matches.first?.cartridge.id, "7.5x55 mm Swiss (GP 11)")
    }

    func testShorterCaseTellsGP1890FromGP11() {
        let matches = DimensionMatcher.rank(MeasuredDimensions(overallLength: 77.0, caseLength: 53.5, rim: 12.5),
                                            cartridges: CartridgeCatalog.all)
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
        XCTAssertEqual(DimensionMatcher.rank(MeasuredDimensions(overallLength: 30)).count, 15)
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
