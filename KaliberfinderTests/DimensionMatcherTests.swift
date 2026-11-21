import XCTest
@testable import Kaliberfinder

final class DimensionMatcherTests: XCTestCase {
    private func rank(_ measured: MeasuredDimensions, cartridges: [Cartridge] = Fixture.current, limit: Int = 15) -> [DimensionMatch] {
        DimensionMatcher.rank(measured, cartridges: cartridges, limit: limit)
    }

    func testFindsNineMillimetreFromCalliperValues() {  // on Fixture.catalogue, like every rank here
        let m = MeasuredDimensions(overallLength: 29.7, caseLength: 19.15, rim: 9.96, bullet: nil)
        let matches = rank(m)
        XCTAssertEqual(matches.first?.cartridge.id, "9x19 mm")
        XCTAssertEqual(matches.first?.fit, .good)
        XCTAssertEqual(matches.first?.maxDeviation ?? 1, 0, accuracy: 0.001)
        // 9x21 has a 2 mm longer case, so it comes later and doesn't fit exactly.
        let nineByTwentyOne = matches.first { $0.cartridge.id == "9x21 mm IMI" }
        XCTAssertNotEqual(nineByTwentyOne?.fit, .good)
    }

    /// A fired hull has opened to the length in its name (review 2026-11-10): typed as the case length it is its gauge.
    func testAFiredHullFitsItsGaugeByCaseLength() {
        for (length, gauge) in [(70.0, "12/70"), (76.0, "12/76"), (89.0, "12/89")] {
            let matches = rank(MeasuredDimensions(caseLength: length, rim: 22.3))
            XCTAssertEqual(matches.first?.cartridge.id, gauge, "\(length)")
            XCTAssertEqual(matches.first?.fit, .good, "\(length)")
        }
    }

    /// A fired hull measured as the length of what one holds, typed as Gesamtlänge (review 2026-11-10): its gauge fits too.
    func testAFiredHullFitsItsGaugeByOverallLength() {
        let hull = rank(MeasuredDimensions(overallLength: 70, rim: 22.3))
        XCTAssertEqual(Set(hull.prefix(2).map(\.cartridge.id)), ["12/70", "12/76"], "an opened 12/70 or a loaded 12/76")
        XCTAssertTrue(hull.prefix(2).allSatisfy { $0.fit == .good })
        let loaded = rank(MeasuredDimensions(overallLength: 64, rim: 22.3))
        XCTAssertEqual(loaded.first?.cartridge.id, "12/70")
        XCTAssertEqual(loaded.first?.fit, .good)
        let long = rank(MeasuredDimensions(overallLength: 76, rim: 22.3))
        XCTAssertEqual(long.first?.cartridge.id, "12/76")
        XCTAssertFalse(long.contains { $0.cartridge.id == "12/70" }, "too long for a 12/70, so not listed")
    }

    /// A rebated rim is narrower than the base; the typed rim is scored against the rim (review 2026-11-10).
    func testRebatedRimFitsItsCalibre() {
        // Its rim is the .44 Magnum's, so both fit exactly (the base, 13.8, would put it 0.7 mm off).
        let matches = rank(MeasuredDimensions(overallLength: 40.9, caseLength: 32.6, rim: 13.1))
        XCTAssertEqual(Set(matches.prefix(2).map(\.cartridge.id)), [".44 Magnum", ".50 Action Express"])
        XCTAssertEqual(matches.first { $0.cartridge.id == ".50 Action Express" }?.fit, .good)
    }

    /// A shotshell's length depends on its crimp: Raven's folded-crimp 12/70 shells measure 57.8 mm
    /// and his Remington 65.5 mm against the catalogue's 64.0 mm; all are 12/70.
    func testShotshellsOfEveryCrimpFitTheirGauge() throws {
        for length in [57.8, 58.2, 65.5] {
            let matches = rank(MeasuredDimensions(overallLength: length, rim: 22.3))
            let twelve = try XCTUnwrap(matches.first { $0.cartridge.id == "12/70" }, "\(length)")
            XCTAssertEqual(twelve.fit, .good, "\(length)")
            XCTAssertEqual(matches.first?.cartridge.dimensions.rim, 22.3, "a 12-gauge shell first at \(length)")
        }
        for length in [57.8, 65.5] {
            XCTAssertEqual(rank(MeasuredDimensions(overallLength: length, rim: 22.3)).first?.cartridge.id, "12/70",
                           "\(length) mm: 12/70 before 12/76")
            XCTAssertEqual(rank(MeasuredDimensions(caseLength: length, rim: 22.3)).first?.cartridge.id, "12/70",
                           "\(length) mm as the case length")
        }
        let magnum = rank(MeasuredDimensions(overallLength: 57.8, rim: 22.3)).first { $0.cartridge.id == "12/89" }
        XCTAssertNotEqual(magnum?.fit, .good)
    }

    func testOnlyShotshellsHaveALengthRange() throws {
        let shell = try XCTUnwrap(Fixture.cartridge("12/70"))
        XCTAssertEqual(shell.overallLengths.lowerBound, 64 * Cartridge.shellShortest, accuracy: 1e-9)
        XCTAssertEqual(shell.overallLengths.upperBound, 64 * Cartridge.shellLongest, accuracy: 1e-9)
        let nine = try XCTUnwrap(Fixture.cartridge("9x19 mm"))
        XCTAssertEqual(nine.overallLengths, 29.7...29.7)
        XCTAssertEqual(DimensionMatcher.outside(29, 29.7...29.7), 0.7, accuracy: 1e-9)
        XCTAssertEqual(DimensionMatcher.outside(60, 57.6...65.9), 0)
    }

    /// A typed belt diameter (tester, 2026-11-14): scored against the belt, or the rim where the data has no belt
    /// (calibre-data gives one only where it is wider than the rim) or the case has none.
    func testBeltDiameterFindsBeltedMagnums() throws {
        let weatherby = rank(MeasuredDimensions(caseLength: 73.9, belt: 15.33), cartridges: CartridgeCatalog.all)
        XCTAssertEqual(weatherby.first?.cartridge.id, ".378 Weatherby Magnum")
        XCTAssertEqual(weatherby.first?.fit, .good)
        let hh = rank(MeasuredDimensions(caseLength: 72.4, belt: 13.5), cartridges: CartridgeCatalog.all)
        XCTAssertTrue(hh.contains { $0.cartridge.id == ".375 H&H Magnum" && $0.fit == .good }, "its belt is as wide as its rim")
        XCTAssertFalse(MeasuredDimensions(belt: 13.5).isEmpty)
    }

    func testTwoValuesAreEnoughForGP11() {
        let matches = rank(MeasuredDimensions(overallLength: 77.5, rim: 12.6))
        XCTAssertEqual(matches.first?.cartridge.id, "7.5x55 mm Swiss (GP 11)")
    }

    func testShorterCaseTellsGP1890FromGP11() {
        // calibre-data #106: the GP 1890 as the army's 1892 drawing has it.
        let matches = rank(MeasuredDimensions(overallLength: 77.2, caseLength: 53.5, rim: 12.5), cartridges: Fixture.catalogue)
        XCTAssertEqual(matches.first?.cartridge.id, "7.5x53.5 mm Swiss (Patrone Modell 1890)")
        XCTAssertEqual(matches.first?.fit, .good)
        let gp11 = matches.first { $0.cartridge.id == "7.5x55 mm Swiss (GP 11)" }
        XCTAssertNotEqual(gp11?.fit, .good, "GP 11's case is 1 mm longer")
        let cadet = matches.first { $0.cartridge.id == "7.5 mm Kadettenpatrone" }
        XCTAssertNotEqual(cadet?.fit, .good, "the Kadettenpatrone's case is 1 mm longer")
    }

    func testGP1890IsOnlyFoundWithObsoleteCalibresSwitchedOn() {
        let gp1890 = MeasuredDimensions(overallLength: 77.2, caseLength: 53.5, rim: 12.5)
        let without = rank(gp1890)
        XCTAssertFalse(without.contains { $0.cartridge.id == "7.5x53.5 mm Swiss (Patrone Modell 1890)" })
        let with = rank(gp1890, cartridges: CartridgeCatalog.matchable(includeObsolete: true, in: Fixture.catalogue))
        XCTAssertEqual(with.first?.cartridge.id, "7.5x53.5 mm Swiss (Patrone Modell 1890)")
    }

    func testIdenticalCalibresTie() {
        let matches = rank(MeasuredDimensions(overallLength: 71.1, caseLength: 51.2, rim: 11.9))
        XCTAssertEqual(Set(matches.prefix(2).map(\.cartridge.id)), [".308 Winchester", "7.62x51 mm NATO"])
    }

    /// Every value exactly 0.15 mm off (9.16 against 9.01 leaves 4e-16 mm in floating point): «Passt genau».
    func testDifferencesOfExactlyTheToleranceFitExactly() throws {
        let c = try Fixture.cartridge("9x19 mm")
        let matches = rank(MeasuredDimensions(overallLength: 29.85, caseLength: 19.3, rim: 9.81, bullet: 9.16), cartridges: [c])
        let match = try XCTUnwrap(matches.first)
        XCTAssertEqual(match.maxDeviation, 0)
        XCTAssertEqual(MeasureView.detail(for: match), MeasureView.detail(for: DimensionMatch(cartridge: c, maxDeviation: 0, meanDeviation: 0)))
        XCTAssertEqual(DimensionMatcher.deviation(9.17, from: [9.01...9.01]), 0.01, accuracy: 1e-9)
        // The same noise at the fit and list limits: exactly 1 mm beyond is rough, not poor; 1.5 mm is still listed.
        let rough = try XCTUnwrap(rank(MeasuredDimensions(bullet: 10.16), cartridges: [c]).first)
        XCTAssertEqual(rough.maxDeviation, 1)
        XCTAssertEqual(rough.fit, .rough)
        XCTAssertEqual(rank(MeasuredDimensions(bullet: 10.66), cartridges: [c]).first?.maxDeviation, 1.5)
        // Exactly 0.5 mm behind the best is listed: 0.18 + 0.5 is just below 0.68 in floating point.
        let behind = rank(MeasuredDimensions(bullet: 9.84), cartridges: [try Fixture.cartridge("10 mm Auto"), c])
        XCTAssertEqual(behind.map(\.cartridge.id), ["10 mm Auto", "9x19 mm"])
        XCTAssertEqual(behind.map(\.maxDeviation), [0.18, 0.68])
        // Equal means, the smaller largest deviation first: (0.1 + 0.2) / 2 came out above (0.3 + 0) / 2.
        let tie = rank(MeasuredDimensions(caseLength: 23.05, rim: 9.75),
                       cartridges: [try Fixture.cartridge(".38 Super"), try Fixture.cartridge(".32 S&W Long")])
        XCTAssertEqual(tie.map(\.cartridge.id), [".32 S&W Long", ".38 Super"])
    }

    func testSmallDifferencesAreWithinTolerance() {
        let matches = rank(MeasuredDimensions(overallLength: 25.5, rim: 6.85))
        XCTAssertEqual(matches.first?.cartridge.id, ".22 LR")
        XCTAssertEqual(matches.first?.fit, .good)
    }

    func testRoughAndPoorFits() throws {
        let c = try XCTUnwrap(Fixture.cartridge("9x19 mm"))
        XCTAssertEqual(DimensionMatch(cartridge: c, maxDeviation: 0.6, meanDeviation: 0.3).fit, .rough)
        XCTAssertEqual(DimensionMatch(cartridge: c, maxDeviation: 2, meanDeviation: 1).fit, .poor)
    }

    func testEmptyMeasurementGivesNothing() {
        XCTAssertTrue(MeasuredDimensions().isEmpty)
        XCTAssertTrue(rank(MeasuredDimensions()).isEmpty)
    }

    func testLimit() {
        XCTAssertEqual(rank(MeasuredDimensions(bullet: 9), cartridges: CartridgeCatalog.all).count, 15)
        XCTAssertEqual(rank(MeasuredDimensions(overallLength: 30), limit: 3).count, 3)
    }

    /// As after a photo (tester, 2026-11-17): nothing far behind the best, nothing far off; the list used to
    /// stay full of poor fits.
    func testFarOffCalibresAreNotListed() {
        // 30 mm: the 29.7 and 29.8 mm rounds, not the 10 mm Auto (32 mm) and nothing shorter than 29.
        let near = rank(MeasuredDimensions(overallLength: 30))
        XCTAssertTrue(near.count >= 3 && near.count < 15, "\(near.map(\.id))")
        XCTAssertTrue(near.allSatisfy { $0.maxDeviation <= DimensionMatcher.maxBehindBest })
        // 33.6 mm: the .22 WMR (34.3) leads; the .32 S&W Long (32.5) is within half a millimetre behind it,
        // the 10 mm Auto (32.0) is not, though within 1.5 mm of the measurement.
        let behind = rank(MeasuredDimensions(overallLength: 33.6))
        XCTAssertEqual(behind.first?.cartridge.id, ".22 WMR")
        XCTAssertTrue(behind.contains { $0.cartridge.id == ".32 S&W Long" }, "\(behind.map(\.id))")
        XCTAssertFalse(behind.contains { $0.cartridge.id == "10 mm Auto" })
        // A 9 mm bullet: no 7.9 mm one (the .32 S&W Long) in the list any more.
        let nine = rank(MeasuredDimensions(bullet: 9), cartridges: CartridgeCatalog.all)
        XCTAssertTrue(nine.allSatisfy { abs($0.cartridge.dimensions.bullet - 9) <= 0.65 }, "\(nine.map(\.id))")
    }

    func testDetailText() throws {
        let c = try XCTUnwrap(Fixture.cartridge("9x19 mm"))
        let exact = MeasureView.detail(for: DimensionMatch(cartridge: c, maxDeviation: 0, meanDeviation: 0))
        let off = MeasureView.detail(for: DimensionMatch(cartridge: c, maxDeviation: 1.5, meanDeviation: 1))
        XCTAssertFalse(exact.isEmpty)
        XCTAssertNotEqual(exact, off)
        XCTAssertTrue(off.contains("mm"))
        // A good fit beyond the tolerance is not «genau»: a bullet 0.38 mm wider (0.23 past the 0.15 mm tolerance)
        // says so, with the whole difference (review 2026-11-18).
        let near = DimensionMatch(cartridge: c, maxDeviation: 0.23, meanDeviation: 0.1)
        XCTAssertEqual(near.fit, .good)
        XCTAssertNotEqual(MeasureView.detail(for: near), exact)
        XCTAssertTrue(MeasureView.detail(for: near).contains(LengthUnit.metric.format(0.38)), MeasureView.detail(for: near))
    }
}
