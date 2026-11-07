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
        // Raven 2026-11-07: worldwide rounds keep the state that introduced them and get the globe as well
        let luger = try cartridge("9x19 mm")
        XCTAssertEqual(luger.country?.code, "DE")
        XCTAssertTrue(luger.worldwide)
        XCTAssertFalse(try cartridge("7.62x39 mm").worldwide)
        XCTAssertEqual(try cartridge(".338 Lapua Magnum").country?.code, "FI")
        let gauge = try cartridge("12/70")
        XCTAssertNil(gauge.country)  // a gauge, not a cartridge
        XCTAssertTrue(gauge.worldwide)
    }

    func testRowMarksAreTheGlobeThenEachCountryOnce() throws {
        // Raven 2026-11-07: the globe sits left of the flag
        let luger = try cartridge("9x19 mm"), germany = try XCTUnwrap(luger.country)
        XCTAssertEqual(OriginMarks.marks(of: [luger]), [.worldwide, .country(germany)])
        let remington = try cartridge(".223 Remington"), usa = try XCTUnwrap(remington.country)
        let nato = try cartridge("5.56x45 mm NATO")  // no agreed origin yet, worldwide
        XCTAssertEqual(OriginMarks.marks(of: [remington, nato]), [.worldwide, .country(usa)])
        XCTAssertEqual(OriginMarks.marks(of: [remington, remington]), [.worldwide, .country(usa)])
        XCTAssertEqual(OriginMarks.marks(of: [try cartridge("12/70")]), [.worldwide])
        let ak = try cartridge("7.62x39 mm"), su = try XCTUnwrap(ak.country)
        XCTAssertEqual(OriginMarks.marks(of: [ak]), [.country(su)])
        XCTAssertEqual(OriginMarks.marks(of: [ak, remington]), [.worldwide, .country(su), .country(usa)])
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
