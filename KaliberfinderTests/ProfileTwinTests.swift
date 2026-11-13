import XCTest
@testable import Kaliberfinder

/// Calibres of one one-size calibre-data lookalike group are suggested as one row, the group's
/// (Raven, 2026-11-11: the groups from calibre-data, once per size; 2026-11-13: whatever their sheets say).
final class ProfileTwinTests: XCTestCase {
    private func c(_ id: String) throws -> Cartridge { try Fixture.cartridge(id) }

    func testCatalogueTwins() throws {
        XCTAssertEqual(CartridgeCatalog.twins(of: try c(".308 Winchester")).map(\.id), ["7.62x51 mm NATO"])
        XCTAssertEqual(Set(CartridgeCatalog.twins(of: try c("5.6 mm GP 90")).map(\.id)),
                       [".223 Remington", "5.56x45 mm NATO"])
        XCTAssertEqual(CartridgeCatalog.twins(of: try c("10.4x38 mm R Vetterli")).map(\.id), ["10.4x38 mm R Vetterli Centrefire"],
                       "the ignition does not show from the side")
        XCTAssertEqual(CartridgeCatalog.twins(of: try c("9x19 mm")).map(\.id), ["9 mm Glisenti"], "one size by calibre-data, 0.5 mm apart in the sheets")
        XCTAssertTrue(CartridgeCatalog.twins(of: try c("7x57 mm Mauser")).isEmpty, "the 7x57 R of its group has a rim")
        XCTAssertTrue(CartridgeCatalog.twins(of: try c("7.5x55 mm Swiss (GP 11)")).isEmpty)
        XCTAssertTrue(CartridgeCatalog.twins(of: try c("7.5x53.5 mm Swiss (GP 1890)")).isEmpty)
        XCTAssertFalse(CartridgeCatalog.sameProfile(try c("9x19 mm"), try c("9x21 mm IMI")), "9x21 has a longer case")
    }

    func testOnlyTheKnownGroupsAreTwins() {
        let all = CartridgeCatalog.all
        let groups = CartridgeCatalog.groupedByProfile(all, cartridge: { $0 }).filter { $0.count > 1 }
        // The known twin sets are among them; the catalogue may add more (the .500/450 Express pair with #196).
        XCTAssertTrue(Set(groups.map { Set($0.map(\.id)) }).isSuperset(of:
                       [[".308 Winchester", "7.62x51 mm NATO"], [".223 Remington", "5.56x45 mm NATO", "5.6 mm GP 90"],
                        ["10.4x38 mm R Vetterli", "10.4x38 mm R Vetterli Centrefire"]]), "\(groups.map { $0.map(\.id) })")
        // Every twin pair comes from a one-size lookalike group of calibre-data, never from equal numbers alone,
        // and the group's parent leads the row.
        for group in groups {
            let sizeGroups = Set(group.compactMap { CartridgeCatalog.sizeGroup(of: $0)?.id })
            XCTAssertEqual(sizeGroups.count, 1, "\(group.map(\.id))")
            XCTAssertEqual(group[0].id, sizeGroups.first)
        }
        // Grouping never loses or duplicates a calibre.
        XCTAssertEqual(CartridgeCatalog.groupedByProfile(all, cartridge: { $0 }).flatMap { $0 }.map(\.id).sorted(), all.map(\.id).sorted())
    }

    func testPhotoMatchesShowTwinsInOneRow() throws {
        let matches = Matcher.rank(shape: try Fixture.shape(".308 Winchester"), cartridges: Fixture.catalogue)
        let rows = Matcher.grouped(matches)
        XCTAssertEqual(rows.flatMap(\.items).count, matches.count)
        let first = try XCTUnwrap(rows.first)
        XCTAssertEqual(Set(first.items.map(\.cartridge.id)), [".308 Winchester", "7.62x51 mm NATO"])
        XCTAssertEqual(first.lead.cartridge.id, ".308 Winchester", "the group's parent names the row")
        XCTAssertEqual(first.others.count, 1)
        // The 1:1 view and its button show the shape once.
        let compare = MatchesView.toCompare(matches).map(\.id)
        XCTAssertEqual(compare.filter { [".308 Winchester", "7.62x51 mm NATO"].contains($0) }.count, 1)
        XCTAssertEqual(MatchesView.compareTitle(matches), String(format: "Alle passenden 1:1 vergleichen (%lld)".loc, rows.count))
    }

    func testMeasuredDimensionsShowTwinsInOneRow() throws {
        let matches = DimensionMatcher.rank(MeasuredDimensions(overallLength: 57.4, caseLength: 44.7, rim: 9.6), cartridges: Fixture.current)
        let rows = DimensionMatcher.grouped(matches)
        let first = try XCTUnwrap(rows.first)
        XCTAssertEqual(Set(first.items.map(\.cartridge.id)), [".223 Remington", "5.56x45 mm NATO", "5.6 mm GP 90"])
        XCTAssertEqual(first.lead.fit, .good)
        let compare = DimensionMatcher.toCompare(matches).map(\.id)
        XCTAssertEqual(compare.first, first.lead.cartridge.id)
        XCTAssertEqual(compare.filter { first.items.map(\.cartridge.id).contains($0) }.count, 1, "the shape is compared once")
        XCTAssertEqual(MeasureView.compareTitle(matches: matches),
                       String(format: "Alle passenden 1:1 vergleichen (%lld)".loc, compare.count))
    }
}
