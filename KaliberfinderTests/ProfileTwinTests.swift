import XCTest
@testable import Kaliberfinder

/// Calibres of one one-size calibre-data lookalike group are suggested as one row, the group's
/// (Raven, 2026-11-11: the groups from calibre-data, once per size; 2026-11-13: whatever their sheets say).
final class ProfileTwinTests: XCTestCase {
    private func c(_ id: String) throws -> Cartridge { try Fixture.cartridge(id) }

    /// The other catalogue calibres that look exactly like `c` from the side, in catalogue order.
    private func twins(of c: Cartridge) -> [Cartridge] {
        CartridgeCatalog.all.filter { $0.id != c.id && CartridgeCatalog.sameProfile($0, c) }
    }

    func testCatalogueTwins() throws {
        XCTAssertEqual(twins(of: try c(".308 Winchester")).map(\.id), ["7.62x51 mm NATO"])
        XCTAssertEqual(Set(twins(of: try c("5.6 mm GP 90")).map(\.id)),
                       [".223 Remington", "5.56x45 mm NATO"])
        XCTAssertEqual(twins(of: try c("10.4x38 mm R Vetterli")).map(\.id), ["10.4x38 mm R Vetterli Centrefire"],
                       "the ignition does not show from the side")
        XCTAssertEqual(twins(of: try c("9x19 mm")).map(\.id), ["9 mm Glisenti"], "one size by calibre-data, 0.5 mm apart in the sheets")
        XCTAssertTrue(twins(of: try c("7x57 mm Mauser")).isEmpty, "the 7x57 R of its group has a rim")
        XCTAssertTrue(twins(of: try c("7.5x55 mm Swiss (GP 11)")).isEmpty)
        XCTAssertTrue(twins(of: try c("7.5x53.5 mm Swiss (GP 1890)")).isEmpty)
        XCTAssertFalse(CartridgeCatalog.sameProfile(try c("9x19 mm"), try c("9x21 mm IMI")), "9x21 has a longer case")
    }

    /// The settings switch off: every calibre its own row and column.
    func testUngroupedKeepsEveryCalibre() throws {
        let both = try ["9x19 mm", "9 mm Glisenti"].map { try XCTUnwrap(CartridgeCatalog.cartridge(id: $0)) }
        XCTAssertEqual(CartridgeCatalog.groupedByProfile(both, cartridge: { $0 }, merged: false).map(\.count), [1, 1])
        XCTAssertEqual(CartridgeCatalog.groupedByProfile(both, cartridge: { $0 }, merged: true).map(\.count), [2])
    }

    /// A comparison column of a group member stands for the group; a calibre's own 1:1 shows the calibre.
    func testComparisonColumnStandsForTheGroup() throws {
        let glisenti = try XCTUnwrap(CartridgeCatalog.cartridge(id: "9 mm Glisenti"))
        XCTAssertEqual(TrueScaleView.shownGroup(of: glisenti, linking: true)?.id, "9x19 mm")
        XCTAssertNil(TrueScaleView.shownGroup(of: glisenti, linking: false))
        XCTAssertNil(TrueScaleView.shownGroup(of: try c(".45 ACP"), linking: true))
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

    /// A row is drawn and rated as its group's parent, unless another member is nearer by more than a margin or the
    /// only one to fit. Measured exactly, a .32 S&W Long Wadcutter came up as the .32 S&W Long, «Abweichung bis 9.09 mm»,
    /// and a 7.62x25 mm Tokarev as the .30 Borchardt, 1 mm off, which the 1:1 button then left out (review 2026-11-13).
    func testAMemberClearlyNearerThanTheParentLeadsItsRow() throws {
        func live(_ id: String) throws -> Cartridge { try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id) }
        let swLong = ".32 S&W Long", wadcutter = ".32 S&W Long Wadcutter", luger = "9x19 mm", glisenti = "9 mm Glisenti"
        let borchardt = ".30 Borchardt", mauser = "7.63x25 mm Mauser", tokarev = "7.62x25 mm Tokarev"
        XCTAssertEqual(CartridgeCatalog.lookalikeGroup(of: try live(tokarev))?.calibres, [borchardt, mauser, tokarev])

        // Dimension matches off by this much each, the best first as the ranking hands them over.
        func measured(_ deviations: KeyValuePairs<String, Double>) throws -> [DimensionMatch] {
            try deviations.map { id, deviation in
                DimensionMatch(cartridge: try live(id), maxDeviation: deviation, meanDeviation: deviation)
            }
        }
        // The calibres of the one row they make, its lead first.
        func row(_ deviations: KeyValuePairs<String, Double>) throws -> [String] {
            let rows = DimensionMatcher.grouped(try measured(deviations))
            XCTAssertEqual(rows.count, 1, "\(deviations.map(\.key)) are not one row")
            return rows.flatMap(\.items).map(\.cartridge.id)
        }
        XCTAssertEqual(try row([wadcutter: 0, swLong: 9.09]), [wadcutter, swLong], "the parent is 9 mm too long")
        XCTAssertEqual(try row([wadcutter: 1.08, swLong: 7.86]), [wadcutter, swLong], "also where neither fits")
        XCTAssertEqual(try row([swLong: 0, wadcutter: 9.09]), [swLong, wadcutter])
        XCTAssertEqual(try row([mauser: 0, tokarev: 0.25, borchardt: 0.61]), [mauser, borchardt, tokarev])
        XCTAssertEqual(try row([tokarev: 0, mauser: 0.25, borchardt: 1.01]), [mauser, borchardt, tokarev],
                       "the first of the group's order within the margin, not the nearest")
        // Less than the margin leaves the row its parent's: these sheets are 0.48 mm apart in overall length.
        XCTAssertEqual(try row([glisenti: 0, luger: 0.33]), [luger, glisenti], "a 29.2 mm round stays a 9x19 mm")
        XCTAssertEqual(try row([glisenti: 1.33, luger: 1.36]), [luger, glisenti])
        XCTAssertEqual(try row([tokarev: 0.5, mauser: 0.6, borchardt: 0.9]), [borchardt, mauser, tokarev])
        // Unless only another fits: the row counts as fitting then.
        XCTAssertEqual(try row([tokarev: 0.75, mauser: 1.15]), [tokarev, mauser])
        XCTAssertEqual(try row([glisenti: 0.56, luger: 1.04]), [glisenti, luger])
        // The 1:1 button takes and counts the row as it is rated.
        let found = try measured([tokarev: 0, mauser: 0.25, borchardt: 1.01])
        XCTAssertEqual(DimensionMatcher.toCompare(found).map(\.id), [mauser])
        XCTAssertEqual(MeasureView.compareTitle(matches: found), String(format: "Alle passenden 1:1 vergleichen (%lld)".loc, 1))

        // A photo's row goes by the distance the list is ranked by.
        func photoRow(_ distances: KeyValuePairs<String, Double>) throws -> [String] {
            let matches = try distances.map { id, distance in Match(cartridge: try live(id), score: -distance, shapeDistance: distance) }
            return Matcher.grouped(matches).flatMap(\.items).map(\.cartridge.id)
        }
        XCTAssertEqual(try photoRow([wadcutter: 0.1, swLong: 0.35]), [wadcutter, swLong], "a wadcutter's photo is not the .32 S&W Long's")
        XCTAssertEqual(try photoRow([wadcutter: 0.1, swLong: 0.15]), [swLong, wadcutter])
        XCTAssertEqual(try photoRow([glisenti: 0.28, luger: 0.31]), [luger, glisenti], "a few hundredths, though across a fit's border")
    }
}
