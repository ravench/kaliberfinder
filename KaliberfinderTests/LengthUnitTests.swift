import XCTest
@testable import Kaliberfinder

final class LengthUnitTests: XCTestCase {
    private let us = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    func testMetricIsTheDefault() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: LengthUnit.storageKey)
        defer { defaults.set(saved, forKey: LengthUnit.storageKey) }
        defaults.removeObject(forKey: LengthUnit.storageKey)
        XCTAssertEqual(LengthUnit.current, .metric)
        defaults.set("imperial", forKey: LengthUnit.storageKey)
        XCTAssertEqual(LengthUnit.current, .imperial)
    }

    func testConversion() {
        XCTAssertEqual(LengthUnit.imperial.value(fromMM: 25.4), 1, accuracy: 1e-12)
        XCTAssertEqual(LengthUnit.imperial.millimetres(2.8), 71.12, accuracy: 1e-9)
        XCTAssertEqual(LengthUnit.metric.value(fromMM: 29.69), 29.69)
        XCTAssertEqual(LengthUnit.metric.millimetres(29.69), 29.69)
    }

    func testFormatting() {
        XCTAssertEqual(LengthUnit.metric.format(29.69, locale: us), "29.69 mm")
        XCTAssertEqual(LengthUnit.metric.format(29.69, locale: german), "29,69 mm")
        XCTAssertEqual(LengthUnit.metric.format(12, locale: us), "12 mm")
        // Inches with three decimals, like US load data.
        XCTAssertEqual(LengthUnit.imperial.format(29.69, locale: us), "1.169 in")
        XCTAssertEqual(LengthUnit.imperial.format(7.82, locale: us), "0.308 in")
        XCTAssertEqual(LengthUnit.imperial.format(71.12, locale: us), "2.800 in")
        XCTAssertEqual(LengthUnit.imperial.format(7.82, locale: german), "0,308 in")
    }

    func testParsingInBothUnits() throws {
        XCTAssertEqual(try XCTUnwrap(LengthUnit.metric.parse("29,7")), 29.7, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(LengthUnit.imperial.parse("1.169")), 29.6926, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(LengthUnit.imperial.parse(" 0,308 ")), 7.8232, accuracy: 1e-9)
        XCTAssertNil(LengthUnit.imperial.parse(""))
        XCTAssertNil(LengthUnit.imperial.parse("abc"))
        XCTAssertNil(LengthUnit.imperial.parse("0"))
        XCTAssertNil(LengthUnit.imperial.parse("-1"))
        // 20 in is 508 mm, beyond any cartridge: ignored like 500+ mm in metric.
        XCTAssertNil(LengthUnit.imperial.parse("20"))
        XCTAssertNil(LengthUnit.metric.parse("500"))
    }

    func testSwitchingUnitsConvertsTypedText() {
        XCTAssertEqual(LengthUnit.convert("29,7", from: .metric, to: .imperial), "1.169")
        XCTAssertEqual(LengthUnit.convert("1.169", from: .imperial, to: .metric), "29.69")
        XCTAssertEqual(LengthUnit.convert("12", from: .metric, to: .metric), "12")
        XCTAssertEqual(LengthUnit.convert("", from: .metric, to: .imperial), "")
        XCTAssertEqual(LengthUnit.convert("abc", from: .imperial, to: .metric), "abc")
    }

    func testImperialEntryFindsTheSameCalibre() {
        let unit = LengthUnit.imperial
        let measured = MeasuredDimensions(overallLength: unit.parse("1.169"), rim: unit.parse("0.392"))
        XCTAssertEqual(DimensionMatcher.rank(measured).first?.cartridge.id, "9x19 mm")
        let gp11 = MeasuredDimensions(overallLength: unit.parse("3.051"), rim: unit.parse("0.496"))
        XCTAssertEqual(DimensionMatcher.rank(gp11).first?.cartridge.id, "7.5x55 mm Swiss (GP 11)")
    }

    func testDeviationIsShownInTheChosenUnit() throws {
        let c = try XCTUnwrap(CartridgeCatalog.cartridge(id: "9x19 mm"))
        let off = MeasureView.detail(for: DimensionMatch(cartridge: c, maxDeviation: 1.5, meanDeviation: 1), unit: .imperial)
        XCTAssertTrue(off.hasSuffix(" in"), off)
        XCTAssertTrue(off.contains("059"), off)
    }

    func testMetricRulerTicks() {
        let ticks = LengthUnit.metric.rulerTicks(lengthMM: 30)
        XCTAssertEqual(ticks.count, 31)
        XCTAssertEqual(ticks[0], RulerTick(mm: 0, level: 4, label: "0"))
        XCTAssertEqual(ticks[1], RulerTick(mm: 1, level: 0, label: nil))
        XCTAssertEqual(ticks[5], RulerTick(mm: 5, level: 2, label: nil))
        XCTAssertEqual(ticks[10], RulerTick(mm: 10, level: 4, label: "1"))
        XCTAssertEqual(ticks.compactMap(\.label), ["0", "1", "2", "3"])
    }

    func testImperialRulerTicksEverySixteenth() throws {
        let ticks = LengthUnit.imperial.rulerTicks(lengthMM: 2 * 25.4)
        XCTAssertEqual(ticks.count, 33)
        XCTAssertEqual(ticks[1].mm, 25.4 / 16, accuracy: 1e-9)
        // 0, 1/16, 1/8, 3/16, 1/4, 5/16, 3/8, 7/16, 1/2
        XCTAssertEqual(ticks.prefix(9).map(\.level), [4, 0, 1, 0, 2, 0, 1, 0, 3])
        XCTAssertEqual(ticks.compactMap(\.label), ["0", "1", "2"])
        let last = try XCTUnwrap(ticks.last)
        XCTAssertEqual(last.mm, 50.8, accuracy: 1e-9)
        XCTAssertEqual(last.level, 4)
    }

    func testRulerLengthRoundsUpToWholeUnits() {
        XCTAssertEqual(LengthUnit.metric.rulerLength(tallestMM: 29.69), 40)
        XCTAssertEqual(LengthUnit.imperial.rulerLength(tallestMM: 29.69), 50.8, accuracy: 1e-9)
        XCTAssertEqual(LengthUnit.imperial.rulerLength(tallestMM: 77.5), 4 * 25.4, accuracy: 1e-9)
    }

    func testScaleText() {
        XCTAssertEqual(LengthUnit.metric.scaleText(pointsPerMM: 6.3, locale: us), "6.30 pt/mm")
        XCTAssertEqual(LengthUnit.metric.scaleText(pointsPerMM: 6.3, precise: true, locale: us), "6.300 pt/mm")
        XCTAssertEqual(LengthUnit.imperial.scaleText(pointsPerMM: 6.3, locale: us), "160.0 pt/in")
        XCTAssertEqual(LengthUnit.imperial.scaleText(pointsPerMM: 6.3, precise: true, locale: us), "160.02 pt/in")
    }

    func testUnitTitlesAreTranslated() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "en"))
        let en = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: String])
        for unit in LengthUnit.allCases {
            XCTAssertNotNil(en[unit.title], unit.title)
        }
        XCTAssertEqual(en["Imperial (Zoll)"], "Imperial (in)")
    }
}
