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
        // Compared as an empty case while the photo is shown as a cartridge: said on the row; not the other way round
        // (balls and shotshells are always compared whole).
        let asCase = Match(cartridge: c, score: 1.5, shapeDistance: 0.1, sizeDeviation: nil, part: .emptyCase)
        XCTAssertEqual(MatchesView.reason(for: asCase, shownPart: .cartridge), ["als leere Hülse".loc, "Form passt gut".loc].joined(separator: " · "))
        XCTAssertEqual(MatchesView.reason(for: asCase, shownPart: .emptyCase), "Form passt gut".loc)
        XCTAssertEqual(MatchesView.reason(for: both, shownPart: .emptyCase), MatchesView.reason(for: both))
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
        let compare = MatchesView.toCompare(matches, by: .overallLength)
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
        XCTAssertEqual(MatchesView.toCompare(ranked, by: .overallLength).map(\.id),
                       ["9 mm Browning kurz (.380 ACP)", ".30 Super Carry", "9x21 mm IMI", "9x19 mm", ".45 ACP"])
        XCTAssertEqual(MatchesView.toCompare(Array(ranked.reversed()), by: .overallLength).map(\.id),
                       ["9 mm Browning kurz (.380 ACP)", ".30 Super Carry", "9x19 mm", "9x21 mm IMI", ".45 ACP"])
        // By the case, the standard: 17.3, 19.15, 20.3, 21.15 and 22.8 mm.
        XCTAssertEqual(MatchesView.toCompare(ranked, by: .caseLength).map(\.id),
                       ["9 mm Browning kurz (.380 ACP)", "9x19 mm", ".30 Super Carry", "9x21 mm IMI", ".45 ACP"])
    }

    func testCompareByFitKeepsTheRankOrderOnlyWithALiDARSize() throws {
        func match(_ id: String, deviation: Double?) throws -> Match {
            Match(cartridge: try XCTUnwrap(CartridgeCatalog.cartridge(id: id)), score: 1, shapeDistance: 0.1, sizeDeviation: deviation)
        }
        let ids = [".45 ACP", "9x19 mm", "9 mm Browning kurz (.380 ACP)"]
        let byLength = ["9 mm Browning kurz (.380 ACP)", "9x19 mm", ".45 ACP"]
        // Measured with LiDAR, the switch keeps the list's order; off, the calibres stand by length as before.
        let measured = try ids.map { try match($0, deviation: 0.2) }
        XCTAssertEqual(MatchesView.toCompare(measured, byFit: true).map(\.id), ids)
        XCTAssertEqual(MatchesView.toCompare(measured, byFit: false).map(\.id), byLength)
        XCTAssertEqual(MatchesView.toCompare(measured).map(\.id), byLength)
        // Without a size the rank is by shape only, so the switch changes nothing.
        let unmeasured = try ids.map { try match($0, deviation: nil) }
        XCTAssertEqual(MatchesView.toCompare(unmeasured, byFit: true).map(\.id), byLength)
        // Nothing stored until the user touches the switch; the views start it on (Raven, 2026-11-08).
        XCTAssertNil(UserDefaults.standard.object(forKey: MatchesView.compareByFitKey))
    }

    func testEmptyCasesCompareByCaseLength() throws {
        func match(_ id: String, _ part: ShapePart) throws -> Match {
            Match(cartridge: try XCTUnwrap(CartridgeCatalog.cartridge(id: id)), score: 1, shapeDistance: 0.1, part: part)
        }
        let ids = ["7.5x55 mm Swiss (GP 11)", ".308 Winchester", "6 mm Creedmoor", "6.5 mm Creedmoor"]
        // Cases 55.6, 51.2, 48.8 (Ø 12.01) and 48.8 mm (Ø 12.0): the narrower 6.5 mm Creedmoor first.
        XCTAssertEqual(MatchesView.toCompare(try ids.map { try match($0, .emptyCase) }).map(\.id),
                       ["6.5 mm Creedmoor", "6 mm Creedmoor", ".308 Winchester", "7.5x55 mm Swiss (GP 11)"])
        // Loaded, by the whole round the same calibres are 77.5, 71.1 (Ø 11.9), 71.1 (Ø 12.01) and 71.8 mm long …
        XCTAssertEqual(MatchesView.toCompare(try ids.map { try match($0, .cartridge) }, by: .overallLength).map(\.id),
                       [".308 Winchester", "6 mm Creedmoor", "6.5 mm Creedmoor", "7.5x55 mm Swiss (GP 11)"])
        // … and by the case, the standard, they stand like the empty cases.
        XCTAssertEqual(MatchesView.toCompare(try ids.map { try match($0, .cartridge) }, by: .caseLength).map(\.id),
                       ["6.5 mm Creedmoor", "6 mm Creedmoor", ".308 Winchester", "7.5x55 mm Swiss (GP 11)"])
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

    /// A fired 12/70 hull has opened to 70 mm (review 2026-11-10): with LiDAR it fits its gauge exactly, as
    /// an empty case, instead of trailing the 12/76 whose loaded range it falls into.
    func testAFiredHullFitsItsGauge() throws {
        let shell = try XCTUnwrap(CartridgeCatalog.cartridge(id: "12/70"))
        let shape = try XCTUnwrap(ShapeMatcher.catalogue[shell.id])
        let hull = ShapeMeasurement(aspect: 70 / 20.6, profile: shape.profile, widths: shape.widths)
        let size = MeasuredSize(length: 70 / Matcher.lengthScaleWhole, diameter: 20.6 / Matcher.diameterScale, lengthError: 1, diameterError: 0.3)
        let matches = Matcher.rank(shape: hull, size: size, limit: .max)
        let twelve = try XCTUnwrap(matches.first { $0.cartridge.id == shell.id })
        XCTAssertEqual(try XCTUnwrap(twelve.sizeDeviation), 0, accuracy: 1e-9)
        XCTAssertEqual(twelve.part, .emptyCase)
        XCTAssertEqual(twelve.score, try XCTUnwrap(matches.first?.score), accuracy: 1e-9, "as good as the best")
        XCTAssertEqual(Matcher.shotshellPart(Matcher.Photo(shape: hull, size: size, perspective: nil, mouth: nil), shell), .emptyCase)
    }

    /// A folded-crimp 12/70 shell is 6 mm shorter than the catalogue's 64 mm (Raven 2026-11-08): with
    /// LiDAR it still fits its gauge's length, as a 65.5 mm Remington does.
    func testAShortShotshellStillFitsByLength() throws {
        let shell = try XCTUnwrap(CartridgeCatalog.cartridge(id: "12/70"))
        let shape = try XCTUnwrap(ShapeMatcher.catalogue[shell.id])
        for length in [57.8, 65.5] {
            let short = ShapeMeasurement(aspect: length / 20.6, profile: shape.profile, widths: shape.widths)
            let size = MeasuredSize(length: length / Matcher.lengthScaleWhole, diameter: 20.6 / Matcher.diameterScale,
                                    lengthError: 1, diameterError: 0.3)
            let matches = Matcher.rank(shape: short, size: size, limit: .max)
            let twelve = try XCTUnwrap(matches.first { $0.cartridge.id == shell.id }, "\(length)")
            XCTAssertEqual(try XCTUnwrap(twelve.sizeDeviation), 0, accuracy: 1e-9, "\(length)")
            XCTAssertEqual(matches.first { $0.cartridge.dimensions.rim == shell.dimensions.rim }?.cartridge.id, shell.id, "\(length): 12/70 before 12/76")
            let magnum = matches.first { $0.cartridge.id == "12/89" }
            XCTAssertGreaterThan(magnum?.sizeDeviation ?? .infinity, 0, "\(length)")
        }
    }

    /// Raven's 8x50 mm R Lebel (TestFlight, 2026-11-08) was listed with the .300 and 7 mm Winchester Short
    /// Magnum: the same bottleneck shape, but rimless (rebated, which the slices cannot tell from rimless).
    /// A rim the photo shows clearly leaves every calibre without one off the list.
    func testAClearRimLeavesRimlessCalibresOffTheList() throws {
        let lebel = "8x50 mm R Lebel"
        let shape = try expected(lebel)
        XCTAssertTrue(try XCTUnwrap(shape.features).isRimmed)
        let shown = Matcher.rankHiding([.obsolete, .rare], shape: shape, size: lebelSize).shown
        XCTAssertEqual(shown.first?.cartridge.id, lebel)
        XCTAssertGreaterThan(shown.count, 1)
        for m in shown {
            XCTAssertTrue(ShapeMatcher.catalogue[m.cartridge.id]?.features?.isRimmed == true, m.cartridge.id)
        }
        // The rim is found whichever end the base is at: lying the other way round, the same rim costs the same.
        let wsm = try expected(".300 Winchester Short Magnum")
        XCTAssertEqual(Matcher.missingRim(shape, wsm), Matcher.missingRimWeight * (1.243 - 1.009 - Matcher.rimTolerance), accuracy: 0.01)
        XCTAssertEqual(Matcher.missingRim(shape.reversed(), wsm), Matcher.missingRim(shape, wsm))
        // A rim at least as wide as the photo's costs nothing, nor one within the tolerance.
        XCTAssertEqual(Matcher.missingRim(shape, shape), 0)
        XCTAssertEqual(Matcher.missingRim(shape, try expected("8x56 mm R Mannlicher")), 0)
    }

    /// A rim can hide in the shadow under the head: a silhouette with none, or a shallow one, punishes no
    /// rimmed calibre (only the small flat `rimPenalty`, as before), and rimless lookalikes stay listed.
    func testAHiddenRimDoesNotPunishRimmedCalibres() throws {
        let lebel = "8x50 mm R Lebel"
        let full = try expected(lebel)
        for rim in [1.0, 1.1] {
            var w = full.widths
            w[w.count - 1] = rim; w[w.count - 2] = rim
            let shape = ShapeMatcher.measurement(aspect: full.aspect, relativeWidths: w)
            XCTAssertEqual(Matcher.shownRim(shape), rim)
            XCTAssertEqual(Matcher.missingRim(shape, full), 0, "\(rim)")
            XCTAssertEqual(Matcher.missingRim(shape, try expected(".300 Winchester Short Magnum")), 0, "\(rim)")
            let shown = Matcher.rankHiding([.obsolete, .rare], shape: shape, size: lebelSize).shown
            XCTAssertEqual(shown.first?.cartridge.id, lebel, "\(rim)")
            XCTAssertEqual(shown.first?.shapeFit, .good, "\(rim)")
            XCTAssertTrue(shown.contains { $0.cartridge.id == "8.5x55 mm Blaser" }, "\(rim): a rimless lookalike stays listed")
        }
    }

    /// The Lebel as Raven's phone measured it: L ≈ 74 mm, Ø ≈ 13.5 mm.
    private var lebelSize: MeasuredSize {
        MeasuredSize(length: 74 / Matcher.lengthScaleWhole, diameter: 13.5 / Matcher.diameterScale, lengthError: 1, diameterError: 0.3)
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
        XCTAssertEqual(MatchesView.manualEntryHint([]), "Keine passenden Kaliber gefunden".loc)
        XCTAssertEqual(MatchesView.manualEntryHint([roughShape]), "Kein sicherer Treffer".loc)
    }

    func testAGoodMatchHasAGoodShapeAndSize() throws {
        let c = try XCTUnwrap(CartridgeCatalog.current.first)
        let good = Match(cartridge: c, score: 1, shapeDistance: 0.05, sizeDeviation: 0.1)
        let shapeOnly = Match(cartridge: c, score: 1, shapeDistance: 0.05)
        let wrongSize = Match(cartridge: c, score: 1, shapeDistance: 0.05, sizeDeviation: 0.8)
        XCTAssertTrue(MatchesView.hasGoodMatch([wrongSize, good]))
        XCTAssertTrue(MatchesView.hasGoodMatch([shapeOnly]), "without a size the shape decides")
        XCTAssertFalse(MatchesView.hasGoodMatch([wrongSize]))
        XCTAssertFalse(MatchesView.hasGoodMatch([]))
        // Only matches that fit well carry their reason to the 1:1 screen.
        XCTAssertEqual(MatchesView.goodMatches([good, wrongSize]), [c.id: MatchesView.reason(for: good)])
        XCTAssertTrue(MatchesView.goodMatches([shapeOnly]).isEmpty)
    }
}
