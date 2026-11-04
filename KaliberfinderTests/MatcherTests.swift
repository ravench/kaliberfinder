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
        XCTAssertEqual(matches.count, 8)
        // .308 Win and 7.62 NATO share their dimensions, so both are on top.
        let top2 = Set(Matcher.rank(shape: try expected(".308 Winchester")).prefix(2).map(\.cartridge.id))
        XCTAssertEqual(top2, [".308 Winchester", "7.62x51 mm NATO"])
    }

    func testRoundSilhouetteComparesOnlyWithRoundBalls() {
        let disc = ShapeMeasurement(aspect: 1, profile: ShapeMatcher.fractions.map { _ in 1 })
        let matches = Matcher.rank(shape: disc, limit: .max)
        XCTAssertFalse(matches.isEmpty)
        XCTAssertTrue(matches.allSatisfy { $0.cartridge.kind == "ball" || $0.cartridge.kind == "pellet" }, matches.map(\.cartridge.id).joined(separator: ", "))
    }

    func testFarOffShapesAreNeverListed() throws {
        // Without text from a headstamp, nothing brings back a calibre whose side profile is off.
        for id in ["9x19 mm", ".308 Winchester", "7.5x55 mm Swiss (GP 11)"] {
            let matches = Matcher.rank(shape: try expected(id), limit: .max)
            let best = try XCTUnwrap(matches.compactMap(\.shapeDistance).min(), id)
            XCTAssertTrue(matches.allSatisfy { ($0.shapeDistance ?? .infinity) <= min(Matcher.maxShapeDistance, best + Matcher.maxBehindBest) }, id)
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
        let all = MatchesView.notes(for: PhotoAnalysis(shape: disc)) + MatchesView.notes(for: PhotoAnalysis(shape: nil), depth: DepthScale(tableDistance: 0.25, focalLength: 3000, referenceLongSide: 4032))
        XCTAssertFalse(all.contains { $0.contains("Aufschrift") || $0.localizedCaseInsensitiveContains("headstamp") }, all.joined(separator: "\n"))
    }

    func testCompareButtonTakesAllMatches() throws {
        let matches = Matcher.rank(shape: try expected("7.5x55 mm Swiss (GP 11)"))
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
        XCTAssertTrue(Match(cartridge: c, score: 2, shapeDistance: 0.05, sizeDeviation: 0.1).fitsWell)
        // Shape only, size only rough, or shape only rough: no highlight.
        XCTAssertFalse(Match(cartridge: c, score: 1, shapeDistance: 0.05).fitsWell)
        XCTAssertFalse(Match(cartridge: c, score: 1, shapeDistance: 0.05, sizeDeviation: 0.8).fitsWell)
        XCTAssertFalse(Match(cartridge: c, score: 1, shapeDistance: 0.25, sizeDeviation: 0.1).fitsWell)
        XCTAssertFalse(Match(cartridge: c, score: 0, shapeDistance: nil).fitsWell)
    }
}
