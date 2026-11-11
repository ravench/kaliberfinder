import XCTest
@testable import Kaliberfinder

/// The country list of a training series: every present-day country and the former states, searchable
/// (Raven 2026-11-09 and 2026-11-11).
final class CountriesTests: XCTestCase {
    private let german = Countries.list(locale: Locale(identifier: "de_CH"))

    func testEveryPresentDayCountryWithItsFlag() {
        let codes = Set(german.map(\.code))
        for code in ["CH", "DE", "AT", "LI", "FR", "IT", "US", "GB", "UA", "ZA", "JP", "BR"] {
            XCTAssertTrue(codes.contains(code), code)
        }
        // Continents, the unknown region and unions are no countries; the former states come from `former`.
        let presentDay = Set(Countries.all(locale: Locale(identifier: "de_CH")).map(\.code))
        for code in ["001", "150", "ZZ", "EU", "UN", "SU", "CS"] {
            XCTAssertFalse(presentDay.contains(code), code)
        }
        XCTAssertGreaterThan(german.count, 190)
        let switzerland = try? XCTUnwrap(german.first { $0.code == "CH" })
        XCTAssertEqual(switzerland?.name, "Schweiz")
        XCTAssertEqual(switzerland?.flag, "🇨🇭")
        XCTAssertEqual(switzerland?.title, "🇨🇭 Schweiz")
        XCTAssertEqual(german.map(\.name), german.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending }, "by name")
        XCTAssertEqual(Countries.title(of: "CH", locale: Locale(identifier: "de_CH")), "🇨🇭 Schweiz")
        XCTAssertEqual(Countries.title(of: "QQ", locale: Locale(identifier: "de_CH")), "🇶🇶 QQ", "an unknown code stays readable")
    }

    func testFormerStatesWithoutAFlag() throws {
        let soviet = try XCTUnwrap(german.first { $0.code == "SU" })
        XCTAssertEqual(soviet.title, "Sowjetunion".loc, "no flag emoji for a former state")
        XCTAssertEqual(Countries.title(of: "SU"), "Sowjetunion".loc)
        XCTAssertEqual(Set(Countries.former.map(\.code)), ["AH", "CS", "DD", "RUE", "SU", "YU"])
        // By code, as the name is in the app's language.
        XCTAssertTrue(Countries.matching("su", in: german).map(\.code).contains("SU"))
    }

    func testSearchByNameOrCode() {
        XCTAssertEqual(Countries.matching("", in: german).count, german.count)
        let schw = Countries.matching("schw", in: german).map(\.code)
        XCTAssertTrue(schw.contains("CH") && schw.contains("SE"), "\(schw)")
        XCTAssertFalse(schw.contains("DE"))
        XCTAssertTrue(Countries.matching("li", in: german).map(\.code).contains("LI"), "by code")
        // Österreich-Ungarn, a former state, comes after today's Austria. Its name follows the app's
        // language (the simulator runs in English), so it may not match at all.
        let austria = Countries.matching("Österreich", in: german).map(\.code)
        XCTAssertEqual(austria.first, "AT")
        XCTAssertEqual(Set(austria.dropFirst()).subtracting(["AH"]), [], "\(austria)")
    }
}
