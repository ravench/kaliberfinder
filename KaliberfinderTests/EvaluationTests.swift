import XCTest
@testable import Kaliberfinder

/// The scoring and report shared by GoldenSetTests and the evaluation tool (tools/evaluate).
final class EvaluationTests: XCTestCase {
    private typealias ShotResult = Evaluation.ShotResult

    /// A shot whose calibre is in list rows `rows` (switches off, obsolete on, all on) and ranks
    /// `rank` among all calibres.
    private func shot(_ name: String, _ calibre: String, _ part: ScanMode = .cartridge, rows: [Int?], rank: Int?, first: String?,
                      sized: Bool = false, source: Evaluation.Source = .phone) -> Evaluation.Shot {
        Evaluation.Shot(name: name, calibre: calibre, part: part,
                        size: sized ? MeasuredSize(length: 29.7, diameter: 9.9, lengthError: 0.3, diameterError: 0.2) : nil,
                        source: source, first: first, result: result(rows, rank: rank, part: part == .cartridge, neck: part == .emptyCase ? false : nil))
    }

    private func result(_ rows: [Int?], rank: Int?, part: Bool = true, neck: Bool? = nil) -> ShotResult {
        ShotResult(row: rows[0], rowObsolete: rows[1], rowAll: rows[2], rank: rank, part: part, neck: neck)
    }

    private var shots: [Evaluation.Shot] {
        [shot("9x19-a/01", "9x19 mm", rows: [1, 1, 2], rank: 2, first: "9x19 mm", sized: true),
         shot("9x19-a/02", "9x19 mm", rows: [3, 4, 7], rank: 7, first: ".38 S&W", source: .colour),
         shot("acp-b/01", ".45 ACP", .emptyCase, rows: [nil, nil, nil], rank: nil, first: ".357 SIG", source: .mac),
         shot("acp-b/02", ".45 ACP", .emptyCase, rows: [2, 2, 1], rank: 1, first: ".357 SIG")]
    }

    func testScoresAreSharesOfTheShots() {
        let scores = Evaluation.Scores([result([1, 1, 1], rank: 1, neck: true), result([4, 6, 9], rank: 9, neck: false),
                                        result([1, 2, 3], rank: 3, part: false), result([nil, nil, nil], rank: nil, part: false)])
        XCTAssertEqual(scores.top1, 50)
        XCTAssertEqual(scores.top5, 75)
        XCTAssertEqual(scores.top1Obsolete, 25)
        XCTAssertEqual(scores.top5Obsolete, 50)
        XCTAssertEqual(scores.top1All, 25)
        XCTAssertEqual(scores.top5All, 50)
        XCTAssertEqual(scores.part, 50)
        XCTAssertEqual(scores.neck, 50, "of the shots of calibres with a neck")
        XCTAssertEqual(Evaluation.Scores([]).top1, 0)
    }

    func testTheReportGroupsByCalibreAndKind() {
        let report = Evaluation.report(shots, title: "Matching")
        XCTAssertTrue(report.hasPrefix("# Matching\n\n4 shots: calibre first 25.0 %, in the top 5 75.0 % as the phone lists them with the switches off; "
                                       + "with obsolete calibres on 25.0 %, 75.0 %; with obsolete and rare on 25.0 %, 50.0 %; part right 50.0 %, neck found 0.0 %"),
                      report)
        XCTAssertTrue(report.contains("| Calibre | Shots | First | Top 5 | First, obsolete on | Top 5, obsolete on | First, all on | Top 5, all on | Part | Neck |"), report)
        XCTAssertTrue(report.contains("| 9x19 mm, cartridge | 2 | 50.0 % | 100.0 % | 50.0 % | 100.0 % | 0.0 % | 50.0 % | 100.0 % | – |"), report)
        XCTAssertTrue(report.contains("| .45 ACP, empty case | 2 | 0.0 % | 50.0 % | 0.0 % | 50.0 % | 50.0 % | 50.0 % | 0.0 % | 0.0 % |"), report)
        XCTAssertTrue(report.contains("| With LiDAR size | 1 | 100.0 % |"), report)
        XCTAssertTrue(report.contains("| Outline from Vision on the Mac | 1 |"), report)
        XCTAssertFalse(report.contains("| No outline |"), "empty groups are left out")
    }

    func testTheReportListsConfusionsAndEveryMiss() {
        let report = Evaluation.report(shots, title: "Matching")
        XCTAssertTrue(report.contains("| .45 ACP | .357 SIG | 2 |\n| 9x19 mm | .38 S&W | 1 |"), report)
        XCTAssertTrue(report.contains("| 9x19-a/02 | 9x19 mm | 3 | 4 | 7 | .38 S&W | ok | – | colour |"), report)
        XCTAssertTrue(report.contains("| acp-b/01 | .45 ACP | – | – | – | .357 SIG | wrong | – | mac |"), report)
        XCTAssertTrue(report.contains("| acp-b/02 | .45 ACP | 2 | 2 | 1 | .357 SIG |"), "first with all switches on, not with them off")
        XCTAssertFalse(report.contains("| 9x19-a/01 |"), "a shot in the first row is no miss")
        XCTAssertFalse(report.contains("Against the earlier run"))
    }

    func testTheReportComparesWithAnEarlierRun() {
        let before = Evaluation.Baseline(["9x19-a/01": result([2, 2, 2], rank: 2), "9x19-a/02": result([3, 4, 7], rank: 7),
                                          "gone/01": result([1, 1, 1], rank: 1)])
        let report = Evaluation.report(shots, title: "Matching", before: before)
        XCTAssertTrue(report.contains("2 shots in both runs."), report)
        XCTAssertTrue(report.contains("| First | 0.0 % | 50.0 % | +50.0 |"), report)
        XCTAssertTrue(report.contains("| First, obsolete on | 0.0 % | 50.0 % | +50.0 |"), report)
        XCTAssertTrue(report.contains("| First, all on | 0.0 % | 0.0 % | +0.0 |"), report)
        XCTAssertTrue(report.contains("| 9x19-a/01 | rows 2 · 2 · 2, rank 2, part ok | rows 1 · 1 · 2, rank 2, part ok |"), report)
        XCTAssertFalse(report.contains("| 9x19-a/02 | rows"), "unchanged shots are not listed")
    }

    /// Results from before the list rows were counted (an older tool, for a comparison) still
    /// read, and their missing rows don't count as misses or changes.
    func testResultsWithoutRowsCompareAsUnknown() throws {
        let old = #"{"scores":{"top1":50,"top5":50,"part":100,"neck":0},"shots":{"9x19-a/01":{"rank":1,"part":true}}}"#
        let before = try TrainingCapture.decoder.decode(Evaluation.Baseline.self, from: Data(old.utf8))
        XCTAssertNil(before.shots["9x19-a/01"]?.row)
        XCTAssertFalse(try XCTUnwrap(before.shots["9x19-a/01"]).hasRows)
        let report = Evaluation.report(shots, title: "Matching", before: before)
        XCTAssertTrue(report.contains("| First | – | 100.0 % | – |"), report)
        XCTAssertTrue(report.contains("| Top 5, all on | – | 100.0 % | – |"), report)
        XCTAssertTrue(report.contains("| 9x19-a/01 | rank 1, part ok | rows 1 · 1 · 2, rank 2, part ok |"), report)

        let same = #"{"scores":{"top1":0,"top5":0,"part":100,"neck":0},"shots":{"9x19-a/01":{"rank":2,"part":true}}}"#
        let unchanged = Evaluation.report(shots, title: "Matching",
                                          before: try TrainingCapture.decoder.decode(Evaluation.Baseline.self, from: Data(same.utf8)))
        XCTAssertFalse(unchanged.contains("| 9x19-a/01 |"), "new rows alone are no change")
    }

    /// The tool's --json output is what --compare reads back.
    func testTheResultsSurviveJSON() throws {
        let baseline = Evaluation.Baseline(["a/01": result([3, 2, nil], rank: nil, part: false, neck: true)])
        let json = try TrainingCapture.encoder.encode(baseline)
        XCTAssertEqual(try TrainingCapture.decoder.decode(Evaluation.Baseline.self, from: json), baseline)
    }

    /// The phone hides rare and obsolete calibres while the switches are off; a shot of such a
    /// calibre is counted as by a user who switched its kind on.
    func testTheSwitchesDecideWhatIsListed() throws {
        let acp = try XCTUnwrap(CartridgeCatalog.cartridge(id: ".45 ACP"))
        let rare = try XCTUnwrap(CartridgeCatalog.all.first { $0.rare && !$0.obsolete })
        let old = try XCTUnwrap(CartridgeCatalog.all.first { $0.obsolete && !$0.rare })
        let ranked = [rare, old, acp].map { Match(cartridge: $0, score: 1, shapeDistance: 0.1) }
        XCTAssertEqual(Evaluation.listed(ranked, showing: acp).map(\.id), [acp.id])
        XCTAssertEqual(Evaluation.listed(ranked, showing: acp, switches: .obsolete).map(\.id), [old.id, acp.id])
        XCTAssertEqual(Evaluation.listed(ranked, showing: acp, switches: .obsoleteAndRare).map(\.id), [rare.id, old.id, acp.id])
        XCTAssertEqual(Evaluation.listed(ranked, showing: rare).map(\.id), [rare.id, acp.id], "its own switch on, obsolete ones still hidden")
        XCTAssertEqual(Evaluation.listed(ranked, showing: old).map(\.id), [old.id, acp.id])
    }

    /// GP 90 looks exactly like .223 Remington and 5.56 NATO: they share the first row.
    func testTwinsShareARow() throws {
        let gp90 = try XCTUnwrap(CartridgeCatalog.cartridge(id: "5.6 mm GP 90"))
        let caseShape = try XCTUnwrap(ShapeMatcher.expected(for: gp90, part: .emptyCase))
        let cases = CapturePackage(calibre: gp90.id, part: "emptyCase", created: Date())
        let scored = Evaluation.shot("gp90/01", analysis: PhotoAnalysis(shape: caseShape, isBrass: true), depth: nil, package: cases)
        XCTAssertEqual(scored.result.row, 1)
        XCTAssertEqual(scored.result.rowAll, 1)
        XCTAssertLessThanOrEqual(try XCTUnwrap(scored.result.rank), 3, "its two twins score the same")
    }

    /// The first row is the first calibre the phone shows: an obsolete calibre ranked first among
    /// all is hidden.
    func testTheFirstIsTheFirstListedCalibre() throws {
        let enfield = try XCTUnwrap(CartridgeCatalog.cartridge(id: ".476 Enfield"))
        XCTAssertTrue(enfield.obsolete)
        let shape = try XCTUnwrap(ShapeMatcher.catalogue[enfield.id])
        let rounds = CapturePackage(calibre: ".45 ACP", part: "cartridge", created: Date())
        let scored = Evaluation.shot("acp/01", analysis: PhotoAnalysis(shape: shape, isBrass: true), depth: nil, package: rounds)
        let first = try XCTUnwrap(scored.first.flatMap(CartridgeCatalog.cartridge(id:)))
        XCTAssertNotEqual(first.id, enfield.id)
        XCTAssertFalse(first.obsolete || first.rare, first.id)
    }

    /// Series of a round the catalogue lacks have no right calibre, so the scores leave them out.
    func testUnlistedSeriesAreNotScored() {
        let url = URL(fileURLWithPath: "/captures")
        func capture(_ name: String, unlisted: Bool?) -> SavedCapture {
            SavedCapture(url: url.appendingPathComponent(name),
                         package: CapturePackage(calibre: name, part: "cartridge", created: Date(), unlisted: unlisted))
        }
        let packages = [capture("9x19 mm", unlisted: nil), capture("11 mm Gras court", unlisted: true), capture(".45 ACP", unlisted: false)]
        XCTAssertEqual(Evaluation.scored(packages).map(\.package.calibre), ["9x19 mm", ".45 ACP"])
    }

    /// Drawn from the calibre's own outline, so it ranks near the top (twins with the same outline
    /// may come first).
    func testAShotIsScoredInAutomaticMode() throws {
        let gp11 = try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5x55 mm Swiss (GP 11)"))
        let caseShape = try XCTUnwrap(ShapeMatcher.expected(for: gp11, part: .emptyCase))
        let cases = CapturePackage(calibre: gp11.id, part: "emptyCase", created: Date())
        let scored = Evaluation.shot("gp11/01", analysis: PhotoAnalysis(shape: caseShape, isBrass: true), depth: nil, package: cases)
        XCTAssertLessThanOrEqual(try XCTUnwrap(scored.result.rank), 5)
        XCTAssertLessThanOrEqual(try XCTUnwrap(scored.result.row), try XCTUnwrap(scored.result.rank))
        XCTAssertNotNil(scored.first)
        XCTAssertTrue(scored.result.part, "automatic mode sees the case mouth")
        XCTAssertEqual(scored.result.neck, true)
        XCTAssertNil(scored.size)
        XCTAssertEqual(scored.source, .phone)

        let rounds = CapturePackage(calibre: "9x19 mm", part: "cartridge", created: Date())
        let round = Evaluation.shot("9x19/01", analysis: PhotoAnalysis(shape: try XCTUnwrap(ShapeMatcher.catalogue["9x19 mm"]), isBrass: true),
                                    depth: nil, package: rounds, source: .mac)
        XCTAssertNil(round.result.neck, "9x19 mm has no neck")
        XCTAssertEqual(round.source, .mac)
        let nothing = Evaluation.shot("9x19/02", analysis: PhotoAnalysis(shape: nil), depth: nil, package: rounds, source: .colour)
        XCTAssertEqual(nothing.source, .none)
        XCTAssertNil(nothing.result.rank)
        XCTAssertNil(nothing.result.row)
        XCTAssertNil(nothing.first)
        XCTAssertFalse(nothing.result.part)
    }
}
