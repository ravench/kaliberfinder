import XCTest
@testable import Kaliberfinder

/// The scoring and report shared by GoldenSetTests and the evaluation tool (tools/evaluate).
final class EvaluationTests: XCTestCase {
    private typealias ShotResult = Evaluation.ShotResult

    private func shot(_ name: String, _ calibre: String, _ part: ScanMode = .cartridge, rank: Int?, first: String?,
                      sized: Bool = false, source: Evaluation.Source = .phone) -> Evaluation.Shot {
        Evaluation.Shot(name: name, calibre: calibre, part: part,
                        size: sized ? MeasuredSize(length: 29.7, diameter: 9.9, lengthError: 0.3, diameterError: 0.2) : nil,
                        source: source, first: first, result: ShotResult(rank: rank, part: part == .cartridge, neck: part == .emptyCase ? false : nil))
    }

    private var shots: [Evaluation.Shot] {
        [shot("9x19-a/01", "9x19 mm", rank: 1, first: "9x19 mm", sized: true),
         shot("9x19-a/02", "9x19 mm", rank: 3, first: ".38 S&W", source: .colour),
         shot("acp-b/01", ".45 ACP", .emptyCase, rank: nil, first: ".357 SIG", source: .mac),
         shot("acp-b/02", ".45 ACP", .emptyCase, rank: 6, first: ".357 SIG")]
    }

    func testScoresAreSharesOfTheShots() {
        let scores = Evaluation.Scores([ShotResult(rank: 1, part: true, neck: true), ShotResult(rank: 4, part: true, neck: false),
                                        ShotResult(rank: nil, part: false, neck: nil)])
        XCTAssertEqual(scores.top1, 33.3)
        XCTAssertEqual(scores.top5, 66.7)
        XCTAssertEqual(scores.part, 66.7)
        XCTAssertEqual(scores.neck, 50, "of the shots of calibres with a neck")
        XCTAssertEqual(Evaluation.Scores([]).top1, 0)
    }

    func testTheReportGroupsByCalibreAndKind() {
        let report = Evaluation.report(shots, title: "Matching")
        XCTAssertTrue(report.hasPrefix("# Matching\n\n4 shots: calibre first 25.0 %, in the top 5 50.0 %, part right 50.0 %, neck found 0.0 %"), report)
        XCTAssertTrue(report.contains("| 9x19 mm, cartridge | 2 | 50.0 % | 100.0 % | 100.0 % | – |"), report)
        XCTAssertTrue(report.contains("| .45 ACP, empty case | 2 | 0.0 % | 0.0 % | 0.0 % | 0.0 % |"), report)
        XCTAssertTrue(report.contains("| With LiDAR size | 1 | 100.0 % |"), report)
        XCTAssertTrue(report.contains("| Outline from Vision on the Mac | 1 |"), report)
        XCTAssertFalse(report.contains("| No outline |"), "empty groups are left out")
    }

    func testTheReportListsConfusionsAndEveryMiss() {
        let report = Evaluation.report(shots, title: "Matching")
        XCTAssertTrue(report.contains("| .45 ACP | .357 SIG | 2 |\n| 9x19 mm | .38 S&W | 1 |"), report)
        XCTAssertTrue(report.contains("| 9x19-a/02 | 9x19 mm | 3 | .38 S&W | ok | – | colour |"), report)
        XCTAssertTrue(report.contains("| acp-b/01 | .45 ACP | – | .357 SIG | wrong | – | mac |"), report)
        XCTAssertFalse(report.contains("| 9x19-a/01 |"), "a shot ranked first is no miss")
        XCTAssertFalse(report.contains("Against the earlier run"))
    }

    func testTheReportComparesWithAnEarlierRun() {
        let before = Evaluation.Baseline(["9x19-a/01": ShotResult(rank: 2, part: true, neck: nil), "9x19-a/02": ShotResult(rank: 3, part: true, neck: nil),
                                          "gone/01": ShotResult(rank: 1, part: true, neck: nil)])
        let report = Evaluation.report(shots, title: "Matching", before: before)
        XCTAssertTrue(report.contains("2 shots in both runs."), report)
        XCTAssertTrue(report.contains("| First | 0.0 % | 50.0 % | +50.0 |"), report)
        XCTAssertTrue(report.contains("| 9x19-a/01 | rank 2, part ok | rank 1, part ok |"), report)
        XCTAssertFalse(report.contains("| 9x19-a/02 | rank 3"), "unchanged shots are not listed")
    }

    /// The tool's --json output is what --compare reads back.
    func testTheResultsSurviveJSON() throws {
        let baseline = Evaluation.Baseline(["a/01": ShotResult(rank: nil, part: false, neck: true)])
        let json = try TrainingCapture.encoder.encode(baseline)
        XCTAssertEqual(try TrainingCapture.decoder.decode(Evaluation.Baseline.self, from: json), baseline)
    }

    /// Drawn from the calibre's own outline, so it ranks near the top (twins with the same outline
    /// may come first).
    func testAShotIsScoredInAutomaticMode() throws {
        let gp11 = try XCTUnwrap(CartridgeCatalog.cartridge(id: "7.5x55 mm Swiss (GP 11)"))
        let caseShape = try XCTUnwrap(ShapeMatcher.expected(for: gp11, part: .emptyCase))
        let cases = CapturePackage(calibre: gp11.id, part: "emptyCase", created: Date())
        let scored = Evaluation.shot("gp11/01", analysis: PhotoAnalysis(shape: caseShape, isBrass: true), depth: nil, package: cases)
        XCTAssertLessThanOrEqual(try XCTUnwrap(scored.result.rank), 5)
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
        XCTAssertFalse(nothing.result.part)
    }
}
