import XCTest
@testable import Kaliberfinder

/// The country list of a training series: every present-day country, searchable (Raven 2026-11-09).
final class CountriesTests: XCTestCase {
    private let german = Countries.all(locale: Locale(identifier: "de_CH"))

    func testEveryPresentDayCountryWithItsFlag() {
        let codes = Set(german.map(\.code))
        for code in ["CH", "DE", "AT", "LI", "FR", "IT", "US", "GB", "UA", "ZA", "JP", "BR"] {
            XCTAssertTrue(codes.contains(code), code)
        }
        // Continents, the unknown region, unions and former states are no countries.
        for code in ["001", "150", "ZZ", "EU", "UN", "SU", "CS"] {
            XCTAssertFalse(codes.contains(code), code)
        }
        XCTAssertGreaterThan(german.count, 190)
        let switzerland = try? XCTUnwrap(german.first { $0.code == "CH" })
        XCTAssertEqual(switzerland?.name, "Schweiz")
        XCTAssertEqual(switzerland?.flag, "🇨🇭")
        XCTAssertEqual(german.map(\.name), german.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending }, "by name")
        XCTAssertEqual(Countries.title(of: "CH", locale: Locale(identifier: "de_CH")), "🇨🇭 Schweiz")
        XCTAssertEqual(Countries.title(of: "QQ", locale: Locale(identifier: "de_CH")), "🇶🇶 QQ", "an unknown code stays readable")
    }

    func testSearchByNameOrCode() {
        XCTAssertEqual(Countries.matching("", in: german).count, german.count)
        let schw = Countries.matching("schw", in: german).map(\.code)
        XCTAssertTrue(schw.contains("CH") && schw.contains("SE"), "\(schw)")
        XCTAssertFalse(schw.contains("DE"))
        XCTAssertTrue(Countries.matching("li", in: german).map(\.code).contains("LI"), "by code")
        XCTAssertEqual(Countries.matching("Österreich", in: german).map(\.code), ["AT"])
    }
}
