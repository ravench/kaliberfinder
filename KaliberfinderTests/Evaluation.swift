#if canImport(Kaliberfinder)
@testable import Kaliberfinder
#endif
import Foundation

/// How well the photo matching finds the calibre of tagged shots, in automatic mode as the phone
/// starts. GoldenSetTests scores the golden set with it on every pull request; the evaluation tool
/// (tools/evaluate) compiles it with the app's analysis code and scores every training shot on a Mac.
///
/// The headline is the list as the phone shows it: rare and obsolete calibres hidden (unless the
/// shot's own calibre is one, as for a user who switched them on) and calibres that look exactly the
/// same from the side in one row. Where the calibre ranks among every catalogue calibre, each on its
/// own, is reported too.
enum Evaluation {
    /// What one shot gave: the row of its calibre in the phone's list (nil: not listed), where it
    /// ranks among every calibre (nil: not listed), whether automatic mode saw the right part, and
    /// for calibres with a clear neck whether the neck was found.
    struct ShotResult: Codable, Equatable {
        /// Row in the list as the phone shows it; nil in results from before it was counted.
        var row: Int?
        var rank: Int?
        var part: Bool
        var neck: Bool?
    }

    /// Shares in percent: calibre in the first row and in the first five rows of the phone's list,
    /// calibre first and in the first five among every calibre, part right, neck found (of the shots
    /// of calibres with a neck).
    struct Scores: Codable, Equatable {
        var top1: Double
        var top5: Double
        var top1All: Double
        var top5All: Double
        var part: Double
        var neck: Double

        init(_ results: [ShotResult]) {
            func share(_ hits: Int, of n: Int) -> Double { n == 0 ? 0 : (1000 * Double(hits) / Double(n)).rounded() / 10 }
            let necked = results.compactMap(\.neck)
            top1 = share(results.filter { $0.row == 1 }.count, of: results.count)
            top5 = share(results.filter { ($0.row ?? .max) <= 5 }.count, of: results.count)
            top1All = share(results.filter { $0.rank == 1 }.count, of: results.count)
            top5All = share(results.filter { ($0.rank ?? .max) <= 5 }.count, of: results.count)
            part = share(results.filter(\.part).count, of: results.count)
            neck = share(necked.filter { $0 }.count, of: necked.count)
        }

        /// Results from before the phone's list was counted have no `top1All` and `top5All`. A
        /// comparison recounts the scores from the shots anyway.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            top1 = try c.decode(Double.self, forKey: .top1)
            top5 = try c.decode(Double.self, forKey: .top5)
            top1All = try c.decodeIfPresent(Double.self, forKey: .top1All) ?? 0
            top5All = try c.decodeIfPresent(Double.self, forKey: .top5All) ?? 0
            part = try c.decode(Double.self, forKey: .part)
            neck = try c.decode(Double.self, forKey: .neck)
        }
    }

    /// The scores and each shot's result: Golden/baseline.json, and what the evaluation tool's
    /// `--json` writes and `--compare` reads.
    struct Baseline: Codable, Equatable {
        var scores: Scores
        var shots: [String: ShotResult]

        init(_ shots: [String: ShotResult]) {
            scores = Scores(Array(shots.values))
            self.shots = shots
        }
    }

    /// Where a shot's outline came from.
    enum Source: String {
        /// The phone's Vision mask, stored with the shot.
        case phone
        /// Vision on the Mac, for a photo the phone never analysed (or with --mac-vision).
        case mac
        /// The colour cut-out: Vision found no cartridge.
        case colour
        /// Nothing measurable.
        case none
    }

    /// One scored shot, with what the report groups it by.
    struct Shot {
        /// "<package>/<shot>".
        let name: String
        let calibre: String
        let part: ScanMode
        /// Measured with LiDAR; nil without depth or when the size failed.
        let size: MeasuredSize?
        let source: Source
        /// The calibre in the first row of the phone's list; nil when nothing is listed.
        let first: String?
        let result: ShotResult
    }

    /// Scores the analysis of a photo of `package`'s calibre and part, with the LiDAR scale it was
    /// taken with, in automatic mode as the phone starts: its row in the list the phone shows (see
    /// `Evaluation`) and its rank among every calibre.
    static func shot(_ name: String, analysis: PhotoAnalysis, depth: DepthScale?, package: CapturePackage,
                     source: Source = .phone) -> Shot {
        let size = try? analysis.size(depth: depth).get()
        let ranked = Matcher.rank(shape: analysis.shape, size: size, mode: .auto, cartridges: CartridgeCatalog.all,
                                  brass: analysis.isBrass, limit: .max)
        let rank = ranked.firstIndex { $0.cartridge.id == package.calibre }.map { $0 + 1 }
        let calibre = CartridgeCatalog.cartridge(id: package.calibre)
        let rows = Matcher.grouped(listed(ranked, showing: calibre))
        let row = rows.firstIndex { $0.items.contains { $0.cartridge.id == package.calibre } }.map { $0 + 1 }
        let part = analysis.shape.map { ScanMode.auto.part(for: $0) == package.scanMode.part(for: $0) } ?? false
        let expected = calibre.flatMap {
            ShapeMatcher.expected(for: $0, part: package.scanMode == .emptyCase ? .emptyCase : .cartridge)
        }
        let neck = expected?.neck?.isClear == true ? analysis.shape?.neck != nil : nil
        return Shot(name: name, calibre: package.calibre, part: package.scanMode, size: size,
                    source: analysis.shape == nil ? .none : source, first: rows.first?.lead.cartridge.id,
                    result: ShotResult(row: row, rank: rank, part: part, neck: neck))
    }

    /// What the phone lists of `ranked` (every calibre, in rank order): the rare and obsolete
    /// calibres hidden, as with the switches off, except those of `calibre`'s own kind, whose switch
    /// its user would have on.
    static func listed(_ ranked: [Match], showing calibre: Cartridge?) -> [Match] {
        let hidden = HiddenTag.hidden(includeObsolete: calibre?.obsolete ?? false, includeRare: calibre?.rare ?? false)
        return HiddenMatches(ranked, hiding: hidden, limit: Matcher.shownLimit).shown
    }

    // MARK: - Report

    /// The report in Markdown: the scores overall, by calibre and by kind of shot, what calibres
    /// are taken for, and every shot whose calibre is not in the first row. Shot names and numbers
    /// only, never a photo. `before`: an earlier run (`Baseline`) to compare with.
    static func report(_ shots: [Shot], title: String, before: Baseline? = nil) -> String {
        var lines = ["# \(title)", "", summary(Scores(shots.map(\.result)), count: shots.count), ""]
        if let before { lines += comparison(shots, with: before) }
        let byCalibre = Dictionary(grouping: shots) { "\($0.calibre), \(partName($0.part))" }
        lines += table("Calibre", byCalibre.keys.sorted().map { ($0, byCalibre[$0] ?? []) })
        lines += table("Shots", kinds(shots))
        lines += confusions(shots)
        lines += misses(shots)
        return lines.joined(separator: "\n")
    }

    static func summary(_ scores: Scores, count: Int) -> String {
        String(format: "%d shots: calibre first %.1f %%, in the top 5 %.1f %% as the phone lists them; "
               + "among all calibres first %.1f %%, in the top 5 %.1f %%; part right %.1f %%, neck found %.1f %%",
               count, scores.top1, scores.top5, scores.top1All, scores.top5All, scores.part, scores.neck)
    }

    private static func partName(_ part: ScanMode) -> String { part == .emptyCase ? "empty case" : "cartridge" }

    private static func percent(_ value: Double) -> String { String(format: "%.1f %%", value) }

    /// One row per group: shots, calibre first and in the top 5 as listed and among all calibres,
    /// part right, neck found.
    private static func table(_ header: String, _ groups: [(String, [Shot])]) -> [String] {
        let rows = groups.filter { !$0.1.isEmpty }.map { label, shots in
            let s = Scores(shots.map(\.result))
            let neck = shots.contains { $0.result.neck != nil } ? percent(s.neck) : "–"
            return "| \(label) | \(shots.count) | \(percent(s.top1)) | \(percent(s.top5)) | \(percent(s.top1All)) | "
                + "\(percent(s.top5All)) | \(percent(s.part)) | \(neck) |"
        }
        return ["| \(header) | Shots | First | Top 5 | First of all | Top 5 of all | Part | Neck |",
                "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"] + rows + [""]
    }

    private static func kinds(_ shots: [Shot]) -> [(String, [Shot])] {
        [("Cartridges", shots.filter { $0.part != .emptyCase }), ("Empty cases", shots.filter { $0.part == .emptyCase }),
         ("With LiDAR size", shots.filter { $0.size != nil }), ("Without size", shots.filter { $0.size == nil }),
         ("Outline from the phone's Vision mask", shots.filter { $0.source == .phone }),
         ("Outline from Vision on the Mac", shots.filter { $0.source == .mac }),
         ("Outline from the colour cut-out", shots.filter { $0.source == .colour }),
         ("No outline", shots.filter { $0.source == .none })]
    }

    /// The calibres most often in the first row instead of the right one.
    private static func confusions(_ shots: [Shot]) -> [String] {
        let wrong = shots.filter { $0.result.row != 1 }.compactMap { shot in shot.first.map { "\(shot.calibre) | \($0)" } }
        guard !wrong.isEmpty else { return [] }
        let counts = Dictionary(wrong.map { ($0, 1) }, uniquingKeysWith: +).sorted { ($1.value, $0.key) < ($0.value, $1.key) }
        return ["## Taken for", "", "| Calibre | First instead | Shots |", "| --- | --- | ---: |"]
            + counts.prefix(20).map { "| \($0.key) | \($0.value) |" } + [""]
    }

    /// Every shot whose calibre is not in the first row.
    private static func misses(_ shots: [Shot]) -> [String] {
        let missed = shots.filter { $0.result.row != 1 }.sorted { $0.name < $1.name }
        guard !missed.isEmpty else { return [] }
        return ["## Not first", "", "| Shot | Calibre | Row | Rank of all | First | Part | Size | Outline |",
                "| --- | --- | ---: | ---: | --- | --- | --- | --- |"]
            + missed.map { shot in
                let size = shot.size.map { String(format: "%.1f × %.1f mm", $0.length, $0.diameter) } ?? "–"
                return "| \(shot.name) | \(shot.calibre) | \(number(shot.result.row)) | \(number(shot.result.rank)) | \(shot.first ?? "–") | "
                    + "\(shot.result.part ? "ok" : "wrong") | \(size) | \(shot.source.rawValue) |"
            } + [""]
    }

    private static func number(_ n: Int?) -> String { n.map(String.init) ?? "–" }

    /// The scores against an earlier run, on the shots both have, and the shots that changed. A run
    /// from before the phone's list was counted has no rows: its first two scores show as «–».
    private static func comparison(_ shots: [Shot], with before: Baseline) -> [String] {
        let common = shots.filter { before.shots[$0.name] != nil }
        let earlier = common.compactMap { before.shots[$0.name] }
        let was = Scores(earlier), now = Scores(common.map(\.result))
        let hadRows = earlier.contains { $0.row != nil }
        let rows = [("First", hadRows ? was.top1 : nil, now.top1), ("Top 5", hadRows ? was.top5 : nil, now.top5),
                    ("First of all", was.top1All, now.top1All), ("Top 5 of all", was.top5All, now.top5All),
                    ("Part", was.part, now.part), ("Neck", was.neck, now.neck)]
            .map { label, a, b in
                "| \(label) | \(a.map(percent) ?? "–") | \(percent(b)) | \(a.map { String(format: "%+.1f", b - $0) } ?? "–") |"
            }
        let changed = common.filter { before.shots[$0.name] != $0.result }.sorted { $0.name < $1.name }.map { shot in
            "| \(shot.name) | \(describe(before.shots[shot.name])) | \(describe(shot.result)) |"
        }
        var lines = ["## Against the earlier run", "", "\(common.count) shots in both runs.", "",
                     "| Score | Before | Now | Change |", "| --- | ---: | ---: | ---: |"] + rows + [""]
        if !changed.isEmpty { lines += ["| Changed shot | Before | Now |", "| --- | --- | --- |"] + changed + [""] }
        return lines
    }

    private static func describe(_ result: ShotResult?) -> String {
        guard let result else { return "–" }
        let neck = result.neck.map { $0 ? ", neck found" : ", neck missed" } ?? ""
        return "row \(number(result.row)), rank \(number(result.rank)), part \(result.part ? "ok" : "wrong")\(neck)"
    }
}
