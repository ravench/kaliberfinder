import XCTest
@testable import Kaliberfinder

final class CalibreTagTests: XCTestCase {
    // The group tags follow the live lookalike groups (`CartridgeCatalog.sizeGroup`), so the live catalogue.
    private func cartridge(_ id: String) throws -> Cartridge { try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id) }

    func testTagsComeFromTheCatalogue() throws {
        XCTAssertEqual(CalibreTag.of(try cartridge("11x59 mm R Gras")), [.rare, .obsolete])
        XCTAssertEqual(CalibreTag.of(try cartridge("7.5x53.5 mm Swiss (GP 1890)")), [.obsolete])
        XCTAssertEqual(CalibreTag.of(try cartridge(".450 No. 2 Nitro Express")), [.rare])
        XCTAssertEqual(CalibreTag.of(try cartridge("7.5x55 mm Swiss (GP 11)")), [])
        // Members of a one-size lookalike group carry the group tag; a group told apart by a measurement
        // (the rimmed 7x57 R) does not (Raven, PR 188: «for a group, where cases have the same size»).
        XCTAssertEqual(CalibreTag.of(try cartridge("9x19 mm")), [.group])
        XCTAssertEqual(CalibreTag.of(try cartridge("7x57 mm R")), [])
        XCTAssertTrue(try XCTUnwrap(CartridgeCatalog.lookalikeGroup(of: try cartridge("9x19 mm"))).sameSize)
        XCTAssertTrue(try XCTUnwrap(CartridgeCatalog.lookalikeGroup(of: try cartridge(".32 S&W Long Wadcutter"))).sameSize, "seating")
        XCTAssertTrue(try XCTUnwrap(CartridgeCatalog.lookalikeGroup(of: try cartridge("10.4x38 mm R Vetterli"))).sameSize, "ignition")
        XCTAssertFalse(try XCTUnwrap(CartridgeCatalog.lookalikeGroup(of: try cartridge("7x57 mm R"))).sameSize, "rim")
        XCTAssertFalse(try XCTUnwrap(CartridgeCatalog.lookalikeGroup(of: try cartridge("7x64 mm"))).sameSize, "rim and length")
        XCTAssertFalse(try XCTUnwrap(CartridgeCatalog.lookalikeGroup(of: try cartridge("6x47 mm SM"))).sameSize, "bore")
        XCTAssertNil(CartridgeCatalog.sizeGroup(of: try cartridge("7x57 mm R")))
        XCTAssertEqual(CalibreTag.group.title, "Gruppe")
        // The group's name as a tag on another member; the parent gets the short «Gruppe» in the trailing slot.
        XCTAssertNil(CartridgeRow.groupName(for: try cartridge(".223 Remington"), linksToGroup: true))
        XCTAssertEqual(CartridgeRow.groupName(for: try cartridge("5.6 mm GP 90"), linksToGroup: true), ".223 Remington")
        XCTAssertNil(CartridgeRow.groupName(for: try cartridge("5.6 mm GP 90"), linksToGroup: false))
        XCTAssertNil(CartridgeRow.groupName(for: try cartridge("7x57 mm R"), linksToGroup: true))
        // The tag only on a row that opens the group page, not on the members inside it (Raven, PR 188 review).
        XCTAssertEqual(CartridgeRow.tags(for: try cartridge("9x19 mm"), linksToGroup: true), [.group])
        XCTAssertEqual(CartridgeRow.tags(for: try cartridge("9x19 mm"), linksToGroup: false), [])
        XCTAssertEqual(CartridgeRow.tags(for: try cartridge("11x59 mm R Gras"), linksToGroup: false), [.rare, .obsolete])
        XCTAssertNil(CalibreTag.group.explanation, "the detail page names the group instead")
    }

    func testRowMarksAreTheGlobeThenEachCountryOnce() throws {
        // Raven 2026-11-07: the globe sits left of the flag
        let luger = try cartridge("9x19 mm"), germany = try XCTUnwrap(luger.country)
        XCTAssertEqual(OriginMarks.marks(of: [luger]), [.worldwide, .country(germany)])
        let remington = try cartridge(".223 Remington"), usa = try XCTUnwrap(remington.country)
        let nato = try cartridge("5.56x45 mm NATO"), alliance = try XCTUnwrap(nato.country)  // worldwide, NATO
        XCTAssertEqual(OriginMarks.marks(of: [remington, nato]), [.worldwide, .country(usa), .country(alliance)])
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
}
