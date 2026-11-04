import XCTest
@testable import Kaliberfinder

final class MatcherTests: XCTestCase {
    private func expected(_ id: String) throws -> ShapeMeasurement {
        try XCTUnwrap(ShapeMatcher.catalogue[id])
    }

    func testExactShapeRanksFirstOrTiesWithTwin() throws {
        let matches = Matcher.rank(shape: try expected("7.5x55 mm Swiss (GP 11)"), hits: [])
        XCTAssertEqual(matches.first?.cartridge.id, "7.5x55 mm Swiss (GP 11)")
        XCTAssertEqual(matches.first?.shapeFit, .good)
        XCTAssertEqual(matches.count, 12)
        // .308 Win and 7.62 NATO share their dimensions, so both are on top.
        let top2 = Set(Matcher.rank(shape: try expected(".308 Winchester"), hits: []).prefix(2).map(\.cartridge.id))
        XCTAssertEqual(top2, [".308 Winchester", "7.62x51 mm NATO"])
    }

    func testStrongTextBeatsShape() throws {
        let hit = HeadstampReader.Hit(cartridgeID: "9x19 mm", text: "9MM LUGER", strength: .strong)
        let matches = Matcher.rank(shape: try expected(".308 Winchester"), hits: [hit])
        XCTAssertEqual(matches.first?.cartridge.id, "9x19 mm")
        XCTAssertEqual(matches.first?.headstamp, hit)
        XCTAssertNotNil(matches.first?.shapeDistance)
    }

    func testRoundSilhouetteComparesOnlyWithRoundBalls() {
        let disc = ShapeMeasurement(aspect: 1, profile: ShapeMatcher.fractions.map { _ in 1 })
        let hit = HeadstampReader.Hit(cartridgeID: ".45 ACP", text: "45 AUTO", strength: .strong)
        let matches = Matcher.rank(shape: disc, hits: [hit])
        XCTAssertEqual(matches.first?.cartridge.id, ".45 ACP")
        XCTAssertNil(matches.first?.shapeDistance)
        XCTAssertNil(matches.first?.shapeFit)
        let others = matches.dropFirst()
        XCTAssertFalse(others.isEmpty)
        XCTAssertTrue(others.allSatisfy { $0.cartridge.kind == "ball" || $0.cartridge.kind == "pellet" }, others.map(\.cartridge.id).joined(separator: ", "))
    }

    func testLongSilhouetteIgnoresRoundBalls() throws {
        let matches = Matcher.rank(shape: try expected("9x19 mm"), hits: [], limit: .max)
        XCTAssertFalse(matches.contains { $0.cartridge.kind == "ball" })
    }

    func testNothingFoundGivesNoMatches() {
        XCTAssertTrue(Matcher.rank(shape: nil, hits: []).isEmpty)
    }

    func testLimit() throws {
        XCTAssertEqual(Matcher.rank(shape: try expected("9x19 mm"), hits: [], limit: 3).count, 3)
    }

    func testReasonAndNotes() throws {
        let c = try XCTUnwrap(CartridgeCatalog.cartridge(id: "9x19 mm"))
        let both = Match(cartridge: c, score: 3, headstamp: HeadstampReader.Hit(cartridgeID: c.id, text: "9MM LUGER", strength: .strong), shapeDistance: 0.1)
        XCTAssertTrue(MatchesView.reason(for: both).contains("9MM LUGER"))
        XCTAssertTrue(MatchesView.reason(for: both).contains(" · "))
        XCTAssertEqual(MatchesView.reason(for: Match(cartridge: c, score: 0, headstamp: nil, shapeDistance: nil)), "")
        XCTAssertEqual(MatchesView.notes(for: PhotoAnalysis(shape: nil, texts: [])).count, 2)
        let side = ShapeMeasurement(aspect: 3, profile: [1])
        XCTAssertTrue(MatchesView.notes(for: PhotoAnalysis(shape: side, texts: [])).isEmpty)
    }

    func testCompareButtonTakesAllMatches() throws {
        let matches = Matcher.rank(shape: try expected("7.5x55 mm Swiss (GP 11)"), hits: [])
        XCTAssertGreaterThan(matches.count, 3)
        // Every listed row, not just the best three, in rank order; identical-looking calibres once.
        let rows = Matcher.grouped(matches)
        XCTAssertEqual(MatchesView.toCompare(matches).map(\.id), rows.map(\.lead.cartridge.id))
        XCTAssertEqual(MatchesView.compareTitle(matches), String(format: "Alle passenden 1:1 vergleichen (%lld)".loc, rows.count))
        XCTAssertTrue(MatchesView.compareTitle(matches).contains("\(rows.count)"))
    }

    func testCompareButtonLooksLikeAButton() {
        XCTAssertNotNil(UIImage(systemName: CompareButton.symbol))
        // Taller than the 44 pt touch target, and clear of the screen edges.
        XCTAssertGreaterThanOrEqual(CompareButton.height, 50)
        XCTAssertGreaterThanOrEqual(CompareButton.margin, 20)
    }

    func testFitsWellNeedsGoodShapeAndSize() throws {
        let c = try XCTUnwrap(CartridgeCatalog.cartridge(id: "9x19 mm"))
        XCTAssertTrue(Match(cartridge: c, score: 2, headstamp: nil, shapeDistance: 0.05, sizeDeviation: 0.1).fitsWell)
        // Shape only, size only rough, or shape only rough: no highlight.
        XCTAssertFalse(Match(cartridge: c, score: 1, headstamp: nil, shapeDistance: 0.05).fitsWell)
        XCTAssertFalse(Match(cartridge: c, score: 1, headstamp: nil, shapeDistance: 0.05, sizeDeviation: 0.8).fitsWell)
        XCTAssertFalse(Match(cartridge: c, score: 1, headstamp: nil, shapeDistance: 0.25, sizeDeviation: 0.1).fitsWell)
        XCTAssertFalse(Match(cartridge: c, score: 0, headstamp: nil, shapeDistance: nil).fitsWell)
    }
}
