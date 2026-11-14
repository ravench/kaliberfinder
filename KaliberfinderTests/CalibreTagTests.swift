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
        // Catalogue and search (Raven, 2026-11-12): every member, the namesake too, shows the group's name and opens itself.
        XCTAssertEqual(CartridgeRow.groupName(for: try cartridge(".223 Remington"), groupTag: .name), ".223 Remington")
        XCTAssertEqual(CartridgeRow.groupName(for: try cartridge("5.6 mm GP 90"), groupTag: .name), ".223 Remington")
        XCTAssertEqual(CartridgeRow.tags(for: try cartridge("9x19 mm"), groupTag: .name), [], "no «Gruppe» chip in the catalogue")
        // Results (Raven, 2026-11-13): the row is the group, whichever member leads: «Gruppe» alone, no name tag,
        // none of a member's «Selten» or «Veraltet»; a calibre without a one-size group keeps its own.
        XCTAssertEqual(CartridgeRow.shownGroup(for: try cartridge("5.6 mm GP 90"), groupTag: .group)?.id, ".223 Remington")
        XCTAssertNil(CartridgeRow.groupName(for: try cartridge("5.6 mm GP 90"), groupTag: .group))
        XCTAssertEqual(CartridgeRow.tags(for: try cartridge("9x19 mm"), groupTag: .group), [.group])
        XCTAssertEqual(CartridgeRow.tags(for: try cartridge("10.4x38 mm R Vetterli Centrefire"), groupTag: .group), [.group])
        XCTAssertNil(CartridgeRow.shownGroup(for: try cartridge("11x59 mm R Gras"), groupTag: .group))
        XCTAssertEqual(CartridgeRow.tags(for: try cartridge("11x59 mm R Gras"), groupTag: .group), [.rare, .obsolete])
        // Members inside the group page and rows that select show nothing of the group (Raven, PR 188 review).
        XCTAssertNil(CartridgeRow.groupName(for: try cartridge("5.6 mm GP 90"), groupTag: .none))
        XCTAssertNil(CartridgeRow.groupName(for: try cartridge("7x57 mm R"), groupTag: .name), "no one-size group")
        XCTAssertEqual(CartridgeRow.tags(for: try cartridge("9x19 mm"), groupTag: .none), [])
        XCTAssertEqual(CartridgeRow.tags(for: try cartridge("11x59 mm R Gras"), groupTag: .none), [.rare, .obsolete])
        XCTAssertNil(CalibreTag.group.explanation, "the detail page names the group instead")
    }

    /// A result row or 1:1 column that stands for a group carries the group's name, but never one of a calibre the
    /// switches leave out of matching: with them off the .38 Super came up as the obsolete «.38 ACP» and the 6 mm BR
    /// Norma as «6 mm BR Remington», each drawn as that parent (review 2026-11-13).
    func testAGroupIsNotShownAsAMemberTheSwitchesLeaveOut() throws {
        let off: (Cartridge) -> Bool = { $0.obsolete || $0.rare }, on: (Cartridge) -> Bool = { _ in false }
        let superAuto = try cartridge(".38 Super"), acp = try cartridge(".38 ACP")
        let group = try XCTUnwrap(CartridgeCatalog.sizeGroup(of: superAuto))
        XCTAssertEqual(group.name, ".38 ACP")
        XCTAssertEqual(group.shownName(drawing: superAuto, leftOut: off), ".38 Super")
        XCTAssertEqual(group.shownName(drawing: superAuto, leftOut: on), ".38 ACP", "the parent is searched for too: the group's name")
        XCTAssertEqual(group.shownName(drawing: acp, leftOut: off), ".38 ACP", "shown with «Einblenden», the parent leads and is drawn")
        let norma = try cartridge("6 mm BR Norma")
        XCTAssertEqual(try XCTUnwrap(CartridgeCatalog.sizeGroup(of: norma)).shownName(drawing: norma, leftOut: off), "6 mm BR Norma")
        // A family's name stays, whoever is drawn, and so does the name of a parent the search includes.
        let tokarev = try cartridge("7.62x25 mm Tokarev"), gp90 = try cartridge("5.6 mm GP 90")
        XCTAssertEqual(try XCTUnwrap(CartridgeCatalog.sizeGroup(of: tokarev)).shownName(drawing: tokarev, leftOut: off), "7.63x25 mm")
        XCTAssertEqual(try XCTUnwrap(CartridgeCatalog.sizeGroup(of: gp90)).shownName(drawing: gp90, leftOut: off), ".223 Remington")
        // The catalogue's tag names the group as the database does.
        XCTAssertEqual(CartridgeRow.groupName(for: tokarev, groupTag: .name), "7.63x25 mm")
        XCTAssertEqual(CartridgeRow.groupName(for: superAuto, groupTag: .name), ".38 ACP")

        // The switches as they stand, both off by default.
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CalibreTagTests"))
        defaults.removePersistentDomain(forName: "CalibreTagTests")
        defer { defaults.removePersistentDomain(forName: "CalibreTagTests") }
        XCTAssertTrue(CartridgeCatalog.isLeftOut(acp, defaults: defaults))
        XCTAssertFalse(CartridgeCatalog.isLeftOut(superAuto, defaults: defaults))
        defaults.set(true, forKey: CartridgeCatalog.includeObsoleteKey)
        XCTAssertTrue(CartridgeCatalog.isLeftOut(acp, defaults: defaults), "obsolete and rare")
        defaults.set(true, forKey: CartridgeCatalog.includeRareKey)
        XCTAssertFalse(CartridgeCatalog.isLeftOut(acp, defaults: defaults))
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
