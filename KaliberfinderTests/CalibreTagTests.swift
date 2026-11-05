import XCTest
@testable import Kaliberfinder

final class CalibreTagTests: XCTestCase {
    private func cartridge(_ id: String) throws -> Cartridge {
        try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id)
    }

    func testTagsComeFromTheCatalogue() throws {
        XCTAssertEqual(CalibreTag.of(try cartridge("11x59 mm R Gras")), [.rare, .obsolete])
        XCTAssertEqual(CalibreTag.of(try cartridge("7.5x53.5 mm Swiss (GP 1890)")), [.obsolete])
        XCTAssertEqual(CalibreTag.of(try cartridge(".450 No. 2 Nitro Express")), [.rare])
        XCTAssertEqual(CalibreTag.of(try cartridge("9x19 mm")), [])
    }

    func testCountries() throws {
        let gp11 = try XCTUnwrap(try cartridge("7.5x55 mm Swiss (GP 11)").country)
        XCTAssertEqual(gp11.code, "CH")
        XCTAssertEqual(gp11.flag, "🇨🇭")
        XCTAssertEqual(try cartridge("9x19 mm").country?.code, Cartridge.Country.worldwide)
        XCTAssertNil(try cartridge(".308 Norma Magnum").country)
    }

    func testEveryCountryHasAFlagToShow() {
        for c in CartridgeCatalog.all {
            guard let country = c.country else { continue }
            XCTAssertTrue(country.flag != nil || DrawnFlag.codes.contains(country.code),
                          "\(c.name): \(country.code) has neither an emoji nor a drawn flag")
        }
    }

    func testFormerStatesAreDrawn() throws {
        let mosin = try XCTUnwrap(try cartridge("7.62x54 mm R").country)
        XCTAssertEqual(mosin.code, "RUE")
        XCTAssertNil(mosin.flag)
        XCTAssertTrue(DrawnFlag.codes.contains(mosin.code))
    }
}
