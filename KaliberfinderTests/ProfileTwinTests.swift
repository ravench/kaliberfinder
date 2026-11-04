import XCTest
@testable import Kaliberfinder

/// Calibres with identical measurements look the same from the side and are suggested as one row.
final class ProfileTwinTests: XCTestCase {
    private func c(_ id: String) throws -> Cartridge { try XCTUnwrap(CartridgeCatalog.cartridge(id: id), id) }

    func testCatalogueTwins() throws {
        XCTAssertEqual(CartridgeCatalog.twins(of: try c(".308 Winchester")).map(\.id), ["7.62x51 mm NATO"])
        XCTAssertEqual(Set(CartridgeCatalog.twins(of: try c("5.6 mm GP 90")).map(\.id)),
                       [".223 Remington", "5.56x45 mm NATO"])
        XCTAssertTrue(CartridgeCatalog.twins(of: try c("9x19 mm")).isEmpty)
        XCTAssertTrue(CartridgeCatalog.twins(of: try c("7.5x55 mm Swiss (GP 11)")).isEmpty)
        XCTAssertTrue(CartridgeCatalog.twins(of: try c("7.5x53.5 mm Swiss (GP 1890)")).isEmpty)
        XCTAssertFalse(CartridgeCatalog.sameProfile(try c("9x19 mm"), try c("9x21 mm IMI")), "9x21 has a longer case")
    }

    func testOnlyTheKnownGroupsAreTwins() {
        let all = CartridgeCatalog.all
        let groups = CartridgeCatalog.groupedByProfile(all, cartridge: { $0 }).filter { $0.count > 1 }
        XCTAssertEqual(Set(groups.map { Set($0.map(\.id)) }),
                       [[".308 Winchester", "7.62x51 mm NATO"], [".223 Remington", "5.56x45 mm NATO", "5.6 mm GP 90"],
                        [".45 ACP", ".45 Super"]])
        // Grouping never loses or duplicates a calibre.
        XCTAssertEqual(CartridgeCatalog.groupedByProfile(all, cartridge: { $0 }).flatMap { $0 }.map(\.id).sorted(), all.map(\.id).sorted())
    }

    func testPhotoMatchesShowTwinsInOneRow() throws {
        let matches = Matcher.rank(shape: try XCTUnwrap(ShapeMatcher.catalogue[".308 Winchester"]))
        let rows = Matcher.grouped(matches)
        XCTAssertEqual(rows.flatMap(\.items).count, matches.count)
        let first = try XCTUnwrap(rows.first)
        XCTAssertEqual(Set(first.items.map(\.cartridge.id)), [".308 Winchester", "7.62x51 mm NATO"])
        XCTAssertEqual(first.others.count, 1)
        XCTAssertEqual(CartridgeCatalog.profileNote(for: first.lead.cartridge, merged: first.others.map(\.cartridge)),
                       "Im Profil nicht unterscheidbar".loc)
        // The 1:1 view and its button show the shape once.
        let compare = MatchesView.toCompare(matches).map(\.id)
        XCTAssertEqual(compare.filter { [".308 Winchester", "7.62x51 mm NATO"].contains($0) }.count, 1)
        XCTAssertEqual(MatchesView.compareTitle(matches), String(format: "Alle passenden 1:1 vergleichen (%lld)".loc, rows.count))
    }

    func testMeasuredDimensionsShowTwinsInOneRow() throws {
        let matches = DimensionMatcher.rank(MeasuredDimensions(overallLength: 57.4, caseLength: 44.7, rim: 9.6))
        let rows = DimensionMatcher.grouped(matches)
        let first = try XCTUnwrap(rows.first)
        XCTAssertEqual(Set(first.items.map(\.cartridge.id)), [".223 Remington", "5.56x45 mm NATO", "5.6 mm GP 90"])
        XCTAssertEqual(first.lead.fit, .good)
        let compare = DimensionMatcher.toCompare(matches).map(\.id)
        XCTAssertEqual(compare.first, first.lead.cartridge.id)
        XCTAssertEqual(compare.filter { first.items.map(\.cartridge.id).contains($0) }.count, 1, "the shape is compared once")
        XCTAssertEqual(MeasureView.compareTitle(matches: matches, selected: 0),
                       String(format: "Alle passenden 1:1 vergleichen (%lld)".loc, compare.count))
    }

    func testCatalogueRowsNameTheTwin() throws {
        XCTAssertEqual(CartridgeCatalog.profileNote(for: try c("7.62x51 mm NATO")),
                       String(format: "Im Profil nicht unterscheidbar von %@".loc, ".308 Winchester"))
        XCTAssertNil(CartridgeCatalog.profileNote(for: try c("9x19 mm")))
    }
}
