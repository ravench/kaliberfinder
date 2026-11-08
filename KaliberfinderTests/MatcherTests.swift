import XCTest
@testable import Kaliberfinder

final class MatcherTests: XCTestCase {
    private func expected(_ id: String) throws -> ShapeMeasurement {
        try XCTUnwrap(ShapeMatcher.catalogue[id])
    }

    func testExactShapeRanksFirstOrTiesWithTwin() throws {
        let matches = Matcher.rank(shape: try expected("7.5x55 mm Swiss (GP 11)"))
        XCTAssertEqual(matches.first?.cartridge.id, "7.5x55 mm Swiss (GP 11)")
        XCTAssertEqual(matches.first?.shapeFit, .good)
        XCTAssertEqual(matches.count, 12)
        // .308 Win and 7.62 NATO share their dimensions, so both are on top.
        let top2 = Set(Matcher.rank(shape: try expected(".308 Winchester")).prefix(2).map(\.cartridge.id))
        XCTAssertEqual(top2, [".308 Winchester", "7.62x51 mm NATO"])
    }

    func testRoundSilhouetteComparesOnlyWithRoundBalls() {
        let disc = ShapeMeasurement(aspect: 1, profile: ShapeMatcher.fractions.map { _ in 1 })
        let matches = Matcher.rank(shape: disc, limit: .max)
        XCTAssertFalse(matches.isEmpty)
        // Besides balls and pellets only cartridges that are themselves about as long as wide,
        // like the 6 mm Flobert and .45 Knall blanks, whose side view also looks round.
        XCTAssertTrue(matches.allSatisfy { $0.cartridge.kind == "ball" || $0.cartridge.kind == "pellet" || ShapeMatcher.catalogue[$0.cartridge.id]?.isEndView == true },
                      matches.map(\.cartridge.id).joined(separator: ", "))
        XCTAssertTrue(matches.contains { $0.cartridge.kind == "ball" })
    }

    func testFarOffShapesAreNeverListed() throws {
        // Without text from a headstamp, nothing brings back a calibre whose side profile is off.
        for id in ["9x19 mm", ".308 Winchester", "7.5x55 mm Swiss (GP 11)"] {
            let matches = Matcher.rank(shape: try expected(id), limit: .max)
            let best = try XCTUnwrap(matches.compactMap(\.shapeDistance).min(), id)
            XCTAssertTrue(matches.allSatisfy { ($0.shapeDistance ?? .infinity) <= min(Matcher.maxDistance, best + Matcher.maxBehindBest) }, id)
        }
    }

    func testLongSilhouetteIgnoresRoundBalls() throws {
        let matches = Matcher.rank(shape: try expected("9x19 mm"), limit: .max)
        XCTAssertFalse(matches.contains { $0.cartridge.kind == "ball" })
    }

    func testNothingFoundGivesNoMatches() {
        XCTAssertTrue(Matcher.rank(shape: nil).isEmpty)
    }

    func testLimit() throws {
        XCTAssertEqual(Matcher.rank(shape: try expected("9x19 mm"), limit: 3).count, 3)
    }

    func testReasonAndNotes() throws {
        let c = try XCTUnwrap(CartridgeCatalog.cartridge(id: "9x19 mm"))
        let both = Match(cartridge: c, score: 1.5, shapeDistance: 0.1, sizeDeviation: 0.5)
        XCTAssertEqual(MatchesView.reason(for: both), ["Form passt gut".loc, "Grösse passt ungefähr".loc].joined(separator: " · "))
        XCTAssertEqual(MatchesView.reason(for: Match(cartridge: c, score: 0, shapeDistance: nil)), "")
        XCTAssertEqual(MatchesView.notes(for: PhotoAnalysis(shape: nil)).count, 2)
        let side = ShapeMeasurement(aspect: 3, profile: [1])
        XCTAssertTrue(MatchesView.notes(for: PhotoAnalysis(shape: side)).isEmpty)
        // Only the side profile counts: no hint sends the user to photograph the base.
        let disc = ShapeMeasurement(aspect: 1, profile: [1])
        let depth = DepthScale(tableDistance: 250, focalLength: 3000, referenceLongSide: 4032)
        let all = MatchesView.notes(for: PhotoAnalysis(shape: disc)) + MatchesView.notes(for: PhotoAnalysis(shape: nil), depth: depth)
        let words = ["Aufschrift", "headstamp", "marking"]
        XCTAssertFalse(all.contains { note in words.contains { note.localizedCaseInsensitiveContains($0) } }, all.joined(separator: "\n"))
    }

    func testCompareButtonTakesAllMatches() throws {
        let matches = Matcher.rank(shape: try expected("7.5x55 mm Swiss (GP 11)"))
        XCTAssertGreaterThan(matches.count, 3)
        // Every listed row, not just the best three; identical-looking calibres once.
        let rows = Matcher.grouped(matches)
        let compare = MatchesView.toCompare(matches)
        XCTAssertEqual(compare.map(\.id).sorted(), rows.map(\.lead.cartridge.id).sorted())
        XCTAssertEqual(MatchesView.compareTitle(matches), String(format: "Alle passenden 1:1 vergleichen (%lld)".loc, rows.count))
        XCTAssertTrue(MatchesView.compareTitle(matches).contains("\(rows.count)"))
        // The 1:1 screen stands them by length, while the list keeps the best match on top.
        let lengths = compare.map(\.dimensions.overallLength)
        XCTAssertEqual(lengths, lengths.sorted(), compare.map(\.id).joined(separator: ", "))
        XCTAssertEqual(rows.first?.lead.cartridge.id, "7.5x55 mm Swiss (GP 11)")
    }

    func testCompareSortsByLengthThenDiameter() throws {
        func match(_ id: String) throws -> Match {
            Match(cartridge: try XCTUnwrap(CartridgeCatalog.cartridge(id: id)), score: 1, shapeDistance: 0.1)
        }
        // All three are 29.7 mm long: the narrower .30 Super Carry (Ø 8.74) comes first, and
        // 9x21 IMI and 9x19 (both Ø 9.96) keep their rank order.
        let ranked = [try match("9x21 mm IMI"), try match("9x19 mm"), try match(".30 Super Carry"), try match(".45 ACP"),
                      try match("9 mm Browning kurz (.380 ACP)")]
        XCTAssertEqual(MatchesView.toCompare(ranked).map(\.id),
                       ["9 mm Browning kurz (.380 ACP)", ".30 Super Carry", "9x21 mm IMI", "9x19 mm", ".45 ACP"])
        XCTAssertEqual(MatchesView.toCompare(Array(ranked.reversed())).map(\.id),
                       ["9 mm Browning kurz (.380 ACP)", ".30 Super Carry", "9x19 mm", "9x21 mm IMI", ".45 ACP"])
    }

    func testEmptyCasesCompareByCaseLength() throws {
        func match(_ id: String, _ part: ShapePart) throws -> Match {
            Match(cartridge: try XCTUnwrap(CartridgeCatalog.cartridge(id: id)), score: 1, shapeDistance: 0.1, part: part)
        }
        let ids = ["7.5x55 mm Swiss (GP 11)", ".308 Winchester", "6 mm Creedmoor", "6.5 mm Creedmoor"]
        // Cases 55.6, 51.2, 48.8 (Ø 12.01) and 48.8 mm (Ø 12.0): the narrower 6.5 mm Creedmoor first.
        XCTAssertEqual(MatchesView.toCompare(try ids.map { try match($0, .emptyCase) }).map(\.id),
                       ["6.5 mm Creedmoor", "6 mm Creedmoor", ".308 Winchester", "7.5x55 mm Swiss (GP 11)"])
        // Loaded, the same calibres are 77.5, 71.1 (Ø 11.9), 71.1 (Ø 12.01) and 71.8 mm long.
        XCTAssertEqual(MatchesView.toCompare(try ids.map { try match($0, .cartridge) }).map(\.id),
                       [".308 Winchester", "6 mm Creedmoor", "6.5 mm Creedmoor", "7.5x55 mm Swiss (GP 11)"])
    }

    func testOneToOneKnowsWhichMatchesAreEmptyCases() throws {
        let gp11 = "7.5x55 mm Swiss (GP 11)"
        let cases = Matcher.rank(shape: try XCTUnwrap(ShapeMatcher.caseCatalogue[gp11]), mode: .emptyCase)
        XCTAssertTrue(MatchesView.emptyCases(cases).contains(gp11))
        // Only what was compared as a case: blanks, balls and loaded rounds are drawn and labelled whole.
        XCTAssertEqual(MatchesView.emptyCases(cases), Set(cases.filter { $0.part == .emptyCase }.map(\.cartridge.id)))
        XCTAssertTrue(MatchesView.emptyCases(Matcher.rank(shape: try expected(gp11))).isEmpty)
    }

    func testCompareButtonLooksLikeAButton() {
        XCTAssertNotNil(UIImage(systemName: CompareButton.symbol))
        // Taller than the 44 pt touch target, and clear of the screen edges.
        XCTAssertGreaterThanOrEqual(CompareButton.height, 50)
        XCTAssertGreaterThanOrEqual(CompareButton.margin, 20)
    }

    func testFitsWellNeedsGoodShapeAndSize() throws {
        let c = try XCTUnwrap(CartridgeCatalog.cartridge(id: "9x19 mm"))
        XCTAssertTrue(Match(cartridge: c, score: 2, shapeDistance: 0.05, sizeDeviation: 0.1).fitsWell)
        // Shape only, size only rough, or shape only rough: no highlight.
        XCTAssertFalse(Match(cartridge: c, score: 1, shapeDistance: 0.05).fitsWell)
        XCTAssertFalse(Match(cartridge: c, score: 1, shapeDistance: 0.05, sizeDeviation: 0.8).fitsWell)
        XCTAssertFalse(Match(cartridge: c, score: 1, shapeDistance: 0.45, sizeDeviation: 0.1).fitsWell)
        XCTAssertFalse(Match(cartridge: c, score: 0, shapeDistance: nil).fitsWell)
    }

    // Weak photo results ask for measurements by hand.
    func testManualEntryIsSuggestedOnlyWithoutAGoodShape() throws {
        let c = try XCTUnwrap(CartridgeCatalog.current.first)
        let roughSize = Match(cartridge: c, score: 1, shapeDistance: 0.05, sizeDeviation: 0.8)
        let shapeOnly = Match(cartridge: c, score: 1, shapeDistance: 0.05)
        let roughShape = Match(cartridge: c, score: 1, shapeDistance: 0.45, sizeDeviation: 0.1)
        // A good shape is compared on the 1:1 screen, with or without LiDAR.
        XCTAssertNil(MatchesView.manualEntryHint([roughSize]))
        XCTAssertNil(MatchesView.manualEntryHint([shapeOnly, roughShape]))
        XCTAssertEqual(MatchesView.manualEntryHint([]),
                       "Keine passenden Kaliber gefunden. Miss die Patrone mit einer Schieblehre und gib die Masse ein.".loc)
        XCTAssertEqual(MatchesView.manualEntryHint([roughShape]),
                       "Kein sicherer Treffer. Miss die Patrone mit einer Schieblehre und gib die Masse ein.".loc)
    }
}
