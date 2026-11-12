import XCTest
@testable import Kaliberfinder

/// «3 weitere Kaliber: 3 veraltete · Einblenden»: matching calibres hidden by a switch. On `Fixture.catalogue`.
final class HiddenMatchesTests: XCTestCase {
    private let gp1890ID = "7.5x53.5 mm Swiss (GP 1890)"
    private let gp1890 = MeasuredDimensions(overallLength: 77.2, caseLength: 53.5, rim: 12.5)

    private func match(_ c: Cartridge, _ deviation: Double) -> DimensionMatch {
        DimensionMatch(cartridge: c, maxDeviation: deviation, meanDeviation: deviation)
    }

    private let bothOff: Set<HiddenTag> = [.obsolete, .rare]

    func testSwitchesMapToHiddenTags() {
        XCTAssertEqual(HiddenTag.hidden(includeObsolete: false, includeRare: false), [.obsolete, .rare])
        XCTAssertEqual(HiddenTag.hidden(includeObsolete: true, includeRare: false), [.rare])
        XCTAssertEqual(HiddenTag.hidden(includeObsolete: false, includeRare: true), [.obsolete])
        XCTAssertEqual(HiddenTag.hidden(includeObsolete: true, includeRare: true), [])
    }

    func testHiddenRareMatchIsCountedAsRare() throws {
        let rifle = try XCTUnwrap(Fixture.cartridge(".450 No. 2 Nitro Express"))
        XCTAssertTrue(rifle.rare)
        XCTAssertFalse(rifle.obsolete)
        let measured = MeasuredDimensions(overallLength: 109.98, caseLength: 88.9, rim: 16.76)
        let r = DimensionMatcher.rankHiding(bothOff, measured, cartridges: Fixture.catalogue)
        XCTAssertFalse(r.shown.contains { $0.cartridge.rare || $0.cartridge.obsolete })
        XCTAssertEqual(r.list(revealing: true).first?.cartridge.id, rifle.id)
        XCTAssertTrue(r.counts.contains { $0.tag == .rare })
        XCTAssertTrue(try XCTUnwrap(r.summary).contains(HiddenTag.rare.countText(r.counts.first { $0.tag == .rare }?.count ?? 0)))
        // With the rare switch on it is the first match.
        XCTAssertEqual(DimensionMatcher.rankHiding([.obsolete], measured, cartridges: Fixture.catalogue).shown.first?.cartridge.id, rifle.id)
    }

    func testCalibreWithBothTagsCountsOnceUnderObsolete() throws {
        let gras = try XCTUnwrap(Fixture.cartridge("11x59 mm R Gras"))
        XCTAssertEqual(HiddenMatches([match(gras, 0)], hiding: bothOff, limit: 5).counts.map(\.tag), [.obsolete])
        XCTAssertEqual(HiddenMatches([match(gras, 0)], hiding: [.rare], limit: 5).counts.map(\.tag), [.rare])
        XCTAssertEqual(HiddenMatches([match(gras, 0)], hiding: [.rare], limit: 5).summary,
                       "1 weiteres Kaliber".loc + ": " + "1 seltenes".loc)
    }

    func testHiddenObsoleteMatchIsCountedAndRevealedInRankOrder() throws {
        let r = DimensionMatcher.rankHiding(bothOff, gp1890, cartridges: Fixture.catalogue)
        XCTAssertFalse(r.shown.contains { $0.cartridge.obsolete || $0.cartridge.rare })
        XCTAssertFalse(r.hidden.isEmpty)
        XCTAssertTrue(r.hidden.allSatisfy { ($0.cartridge.obsolete || $0.cartridge.rare) && $0.fit != .poor })
        XCTAssertTrue(r.hidden.contains { $0.cartridge.id == gp1890ID })
        // Revealing puts GP 1890 back at the top, in place, and keeps every shown row.
        XCTAssertEqual(r.list(revealing: true).first?.cartridge.id, gp1890ID)
        XCTAssertEqual(r.revealed.count, r.shown.count + r.hidden.count)
        XCTAssertEqual(r.list(revealing: false).map(\.id), r.shown.map(\.id))
        XCTAssertEqual(r.counts.first?.tag, .obsolete)
        XCTAssertEqual(r.counts.map(\.count).reduce(0, +), r.hidden.count)
        let summary = try XCTUnwrap(r.summary)
        XCTAssertTrue(summary.contains(HiddenTag.obsolete.countText(r.counts[0].count)), summary)
    }

    func testNothingIsHiddenWithTheSwitchOn() {
        let r = DimensionMatcher.rankHiding([], gp1890, cartridges: Fixture.catalogue)
        XCTAssertTrue(r.hidden.isEmpty)
        XCTAssertNil(r.summary)
        XCTAssertEqual(r.shown.first?.cartridge.id, gp1890ID)
        XCTAssertEqual(r.shown.count, DimensionMatcher.shownLimit)
    }

    func testShownListMatchesRankingWithoutObsoleteCalibres() {
        let r = DimensionMatcher.rankHiding(bothOff, gp1890, cartridges: Fixture.catalogue)
        let old = DimensionMatcher.rank(gp1890, cartridges: Fixture.current)
        XCTAssertEqual(r.shown.count, old.count)
        XCTAssertEqual(Set(r.shown.prefix(5).map(\.id)), Set(old.prefix(5).map(\.id)))
    }

    func testOnlyHiddenCalibresWithinTheLimitCountAndTextsAgree() throws {
        let current = Fixture.catalogue.filter { !$0.obsolete }.prefix(2)
        let old = Fixture.catalogue.filter(\.obsolete).prefix(3)
        XCTAssertEqual(current.count, 2)
        XCTAssertEqual(old.count, 3)
        let c1 = current[current.startIndex], c2 = current[current.startIndex + 1]
        let o = Array(old)
        let ranked = [match(c1, 0), match(o[0], 0.1), match(c2, 0.2), match(o[1], 0.3), match(o[2], 0.4)]

        let three = HiddenMatches(ranked, hiding: [.obsolete], limit: 3)
        XCTAssertEqual(three.shown.map(\.id), [c1.id, c2.id])
        XCTAssertEqual(three.hidden.map(\.id), [o[0].id])
        XCTAssertEqual(three.revealed.map(\.id), [c1.id, o[0].id, c2.id])
        XCTAssertEqual(three.summary, "1 weiteres Kaliber".loc + ": " + "1 veraltetes".loc)

        let all = HiddenMatches(ranked, hiding: [.obsolete], limit: 10)
        XCTAssertEqual(all.revealed.map(\.id), ranked.map(\.id))
        XCTAssertEqual(all.summary, String(format: "%lld weitere Kaliber".loc, 3) + ": " + String(format: "%lld veraltete".loc, 3))

        XCTAssertNil(HiddenMatches(ranked, hiding: [], limit: 10).summary)
        let near = HiddenMatches(ranked, hiding: [.obsolete], limit: 10) { $0.maxDeviation < 0.35 }
        XCTAssertEqual(near.hidden.map(\.id), [o[0].id, o[1].id])
        XCTAssertEqual(near.revealed.map(\.id), [c1.id, o[0].id, c2.id, o[1].id])
        XCTAssertNil(HiddenMatches<DimensionMatch>.none.summary)
    }

    func testPhotoResultsHideObsoleteCalibres() throws {
        let shape = try Fixture.shape(gp1890ID)
        let r = Matcher.rankHiding(bothOff, shape: shape, cartridges: Fixture.catalogue)
        XCTAssertFalse(r.shown.contains { $0.cartridge.obsolete || $0.cartridge.rare })
        XCTAssertTrue(r.hidden.contains { $0.cartridge.id == gp1890ID })
        // Calibres with the same proportions score the same, so GP 1890 is among the first
        // non-rare ones (rare look-alikes may tie with it).
        XCTAssertTrue(r.revealed.filter { !$0.cartridge.rare }.prefix(3).contains { $0.cartridge.id == gp1890ID })
        XCTAssertTrue(Matcher.rankHiding([], shape: shape, cartridges: Fixture.catalogue).hidden.isEmpty)
    }
}
