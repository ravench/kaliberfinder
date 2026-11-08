#if canImport(Kaliberfinder)
@testable import Kaliberfinder
#endif
import Foundation

/// How well the photo matching finds the calibre of tagged shots, in automatic mode as the phone
/// starts. GoldenSetTests scores the golden set with it on every pull request; the evaluation tool
/// (tools/evaluate) compiles it with the app's analysis code and scores every training shot on a Mac.
///
/// Scores go by the list as the phone shows it, with calibres that look exactly the same from the side
/// in one row, for each setting of the «Erkennung» switches (`Switches`). The headline, with both
/// switches off, is what a user sees first: the target is the right calibre in the first row there.
enum Evaluation {
    /// The «Erkennung» switches on the home screen: which hidden calibres the phone's list shows.
    enum Switches: CaseIterable {
        /// Rare and obsolete calibres hidden, as the app starts.
        case off
        /// Obsolete calibres shown, rare ones hidden.
        case obsolete
        /// Every calibre shown.
        case obsoleteAndRare

        /// The tags hidden for a shot of `calibre`: a rare or obsolete calibre's own switch is on, as
        /// its user would have it, or the phone could never list it.
        func hidden(showing calibre: Cartridge?) -> Set<HiddenTag> {
            HiddenTag.hidden(includeObsolete: self != .off || calibre?.obsolete == true,
                             includeRare: self == .obsoleteAndRare || calibre?.rare == true)
        }
    }

    /// What one shot gave: the row of its calibre in the phone's list with the switches off, with
    /// obsolete calibres on, and with obsolete and rare on (nil: not listed, or a result from before
    /// rows were counted); its rank among every calibre, each on its own; whether automatic mode saw
    /// the right part; and for calibres with a clear neck whether the neck was found.
    struct ShotResult: Codable, Equatable {
        var row: Int?
        var rowObsolete: Int?
        var rowAll: Int?
        var rank: Int?
        var part: Bool
        var neck: Bool?

        /// The row with the switches set as `switches`.
        func row(_ switches: Switches) -> Int? {
            switch switches {
            case .off: row
            case .obsolete: rowObsolete
            case .obsoleteAndRare: rowAll
            }
        }

        /// Whether any row was counted (results from before have ranks only).
        var hasRows: Bool { row != nil || rowObsolete != nil || rowAll != nil }
    }

    /// Shares in percent: calibre in the first row and in the first five rows of the phone's list with
    /// the switches off, with obsolete calibres on, and with obsolete and rare on; part right; neck
    /// found (of the shots of calibres with a neck).
    struct Scores: Codable, Equatable {
        var top1: Double
        var top5: Double
        var top1Obsolete: Double
        var top5Obsolete: Double
        var top1All: Double
        var top5All: Double
        var part: Double
        var neck: Double

        init(_ results: [ShotResult]) {
            func share(_ hits: Int, of n: Int) -> Double { n == 0 ? 0 : (1000 * Double(hits) / Double(n)).rounded() / 10 }
            func first(_ s: Switches) -> Double { share(results.filter { $0.row(s) == 1 }.count, of: results.count) }
            func five(_ s: Switches) -> Double { share(results.filter { ($0.row(s) ?? .max) <= 5 }.count, of: results.count) }
            let necked = results.compactMap(\.neck)
            top1 = first(.off)
            top5 = five(.off)
            top1Obsolete = first(.obsolete)
            top5Obsolete = five(.obsolete)
            top1All = first(.obsoleteAndRare)
            top5All = five(.obsoleteAndRare)
            part = share(results.filter(\.part).count, of: results.count)
            neck = share(necked.filter { $0 }.count, of: necked.count)
        }

        /// Results from before the rows were counted lack the switched-on scores. A comparison
        /// recounts the scores from the shots anyway.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            top1 = try c.decode(Double.self, forKey: .top1)
            top5 = try c.decode(Double.self, forKey: .top5)
            top1Obsolete = try c.decodeIfPresent(Double.self, forKey: .top1Obsolete) ?? 0
            top5Obsolete = try c.decodeIfPresent(Double.self, forKey: .top5Obsolete) ?? 0
            top1All = try c.decodeIfPresent(Double.self, forKey: .top1All) ?? 0
            top5All = try c.decodeIfPresent(Double.self, forKey: .top5All) ?? 0
            part = try c.decode(Double.self, forKey: .part)
            neck = try c.decode(Double.self, forKey: .neck)
        }

        /// First and top 5 with the switches set as `switches`.
        func scores(_ switches: Switches) -> (top1: Double, top5: Double) {
            switch switches {
            case .off: (top1, top5)
            case .obsolete: (top1Obsolete, top5Obsolete)
            case .obsoleteAndRare: (top1All, top5All)
            }
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
        /// Vision on a crop of the photo, after it found nothing in the whole photo (`PhotoAnalyzer.firstLook`).
        case crop
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
        /// The calibre in the first row of the phone's list with the switches off; nil when nothing is listed.
        let first: String?
        let result: ShotResult
    }

    /// The packages that can be scored: a series of a round the catalogue lacks
    /// (`CapturePackage.unlisted`) has no right calibre to find.
    static func scored(_ packages: [SavedCapture]) -> [SavedCapture] {
        packages.filter { !$0.package.isUnlisted }
    }

    /// Scores the analysis of a photo of `package`'s calibre and part, with the LiDAR scale it was
    /// taken with, in automatic mode as the phone starts: its row in the list the phone shows for each
    /// setting of the switches (see `Evaluation`) and its rank among every calibre.
    static func shot(_ name: String, analysis: PhotoAnalysis, depth: DepthScale?, package: CapturePackage,
                     source: Source = .phone) -> Shot {
        let size = try? analysis.size(depth: depth).get()
        let ranked = Matcher.rank(shape: analysis.shapeAtAxis(depth: depth), size: size, mode: .auto, cartridges: CartridgeCatalog.all,
                                  brass: analysis.isBrass, limit: .max)
        let rank = ranked.firstIndex { $0.cartridge.id == package.calibre }.map { $0 + 1 }
        let calibre = CartridgeCatalog.cartridge(id: package.calibre)
        let rows = Dictionary(uniqueKeysWithValues: Switches.allCases.map { ($0, Matcher.grouped(listed(ranked, showing: calibre, switches: $0))) })
        func row(_ s: Switches) -> Int? {
            rows[s]?.firstIndex { $0.items.contains { $0.cartridge.id == package.calibre } }.map { $0 + 1 }
        }
        let part = analysis.shape.map { ScanMode.auto.part(for: $0) == package.scanMode.part(for: $0) } ?? false
        let expected = calibre.flatMap {
            ShapeMatcher.expected(for: $0, part: package.scanMode == .emptyCase ? .emptyCase : .cartridge)
        }
        let neck = expected?.neck?.isClear == true ? analysis.shape?.neck != nil : nil
        return Shot(name: name, calibre: package.calibre, part: package.scanMode, size: size,
                    source: analysis.shape == nil ? .none : source, first: rows[.off]?.first?.lead.cartridge.id,
                    result: ShotResult(row: row(.off), rowObsolete: row(.obsolete), rowAll: row(.obsoleteAndRare),
                                       rank: rank, part: part, neck: neck))
    }

    /// What the phone lists of `ranked` (every calibre, in rank order) with the switches set as
    /// `switches`, for a shot of `calibre` (`Switches.hidden(showing:)`).
    static func listed(_ ranked: [Match], showing calibre: Cartridge?, switches: Switches = .off) -> [Match] {
        HiddenMatches(ranked, hiding: switches.hidden(showing: calibre), limit: Matcher.shownLimit).shown
    }

    // MARK: - Report

    /// The report in Markdown: the scores overall, by calibre and by kind of shot, what calibres
    /// are taken for, and every shot whose calibre is not in the first row with the switches off. Shot
    /// names and numbers only, never a photo. `before`: an earlier run (`Baseline`) to compare with.
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
        String(format: "%d shots: calibre first %.1f %%, in the top 5 %.1f %% as the phone lists them with the switches off; "
               + "with obsolete calibres on %.1f %%, %.1f %%; with obsolete and rare on %.1f %%, %.1f %%; part right %.1f %%, neck found %.1f %%",
               count, scores.top1, scores.top5, scores.top1Obsolete, scores.top5Obsolete, scores.top1All, scores.top5All, scores.part, scores.neck)
    }

    private static func partName(_ part: ScanMode) -> String { part == .emptyCase ? "empty case" : "cartridge" }

    private static func percent(_ value: Double) -> String { String(format: "%.1f %%", value) }

    /// One row per group: shots, calibre first and in the top 5 for each setting of the switches,
    /// part right, neck found.
    private static func table(_ header: String, _ groups: [(String, [Shot])]) -> [String] {
        let rows = groups.filter { !$0.1.isEmpty }.map { label, shots in
            let s = Scores(shots.map(\.result))
            let neck = shots.contains { $0.result.neck != nil } ? percent(s.neck) : "–"
            let firsts = Switches.allCases.map { "\(percent(s.scores($0).top1)) | \(percent(s.scores($0).top5))" }.joined(separator: " | ")
            return "| \(label) | \(shots.count) | \(firsts) | \(percent(s.part)) | \(neck) |"
        }
        return ["| \(header) | Shots | First | Top 5 | First, obsolete on | Top 5, obsolete on | First, all on | Top 5, all on | Part | Neck |",
                "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"] + rows + [""]
    }

    private static func kinds(_ shots: [Shot]) -> [(String, [Shot])] {
        [("Cartridges", shots.filter { $0.part != .emptyCase }), ("Empty cases", shots.filter { $0.part == .emptyCase }),
         ("With LiDAR size", shots.filter { $0.size != nil }), ("Without size", shots.filter { $0.size == nil }),
         ("Outline from the phone's Vision mask", shots.filter { $0.source == .phone }),
         ("Outline from Vision on the Mac", shots.filter { $0.source == .mac }),
         ("Outline from Vision on a crop", shots.filter { $0.source == .crop }),
         ("Outline from the colour cut-out", shots.filter { $0.source == .colour }),
         ("No outline", shots.filter { $0.source == .none })]
    }

    /// The calibres most often in the first row instead of the right one (switches off).
    private static func confusions(_ shots: [Shot]) -> [String] {
        let wrong = shots.filter { $0.result.row != 1 }.compactMap { shot in shot.first.map { "\(shot.calibre) | \($0)" } }
        guard !wrong.isEmpty else { return [] }
        let counts = Dictionary(wrong.map { ($0, 1) }, uniquingKeysWith: +).sorted { ($1.value, $0.key) < ($0.value, $1.key) }
        return ["## Taken for", "", "| Calibre | First instead | Shots |", "| --- | --- | ---: |"]
            + counts.prefix(20).map { "| \($0.key) | \($0.value) |" } + [""]
    }

    /// Every shot whose calibre is not in the first row with the switches off.
    private static func misses(_ shots: [Shot]) -> [String] {
        let missed = shots.filter { $0.result.row != 1 }.sorted { $0.name < $1.name }
        guard !missed.isEmpty else { return [] }
        return ["## Not first", "", "| Shot | Calibre | Row | Obsolete on | All on | First | Part | Size | Outline |",
                "| --- | --- | ---: | ---: | ---: | --- | --- | --- | --- |"]
            + missed.map { shot in
                let size = shot.size.map { String(format: "%.1f × %.1f mm", $0.length, $0.diameter) } ?? "–"
                let r = shot.result
                return "| \(shot.name) | \(shot.calibre) | \(number(r.row)) | \(number(r.rowObsolete)) | \(number(r.rowAll)) | \(shot.first ?? "–") | "
                    + "\(r.part ? "ok" : "wrong") | \(size) | \(shot.source.rawValue) |"
            } + [""]
    }

    private static func number(_ n: Int?) -> String { n.map(String.init) ?? "–" }

    /// The scores against an earlier run, on the shots both have, and the shots that changed. A run
    /// from before the rows were counted has none: its row scores show as «–», and a shot counts as
    /// changed only when its rank, part or neck did.
    private static func comparison(_ shots: [Shot], with before: Baseline) -> [String] {
        let common = shots.filter { before.shots[$0.name] != nil }
        let earlier = common.compactMap { before.shots[$0.name] }
        let was = Scores(earlier), now = Scores(common.map(\.result))
        // A run with ranks but no rows comes from before the rows were counted.
        let hadRows = earlier.contains(where: \.hasRows) || !earlier.contains { $0.rank != nil }
        let labels: [(Switches, String)] = [(.off, ""), (.obsolete, ", obsolete on"), (.obsoleteAndRare, ", all on")]
        let rowScores = labels.flatMap { s, suffix in
            [("First\(suffix)", hadRows ? was.scores(s).top1 : nil, now.scores(s).top1),
             ("Top 5\(suffix)", hadRows ? was.scores(s).top5 : nil, now.scores(s).top5)]
        }
        let rows = (rowScores + [("Part", was.part, now.part), ("Neck", was.neck, now.neck)])
            .map { label, a, b in
                "| \(label) | \(a.map(percent) ?? "–") | \(percent(b)) | \(a.map { String(format: "%+.1f", b - $0) } ?? "–") |"
            }
        let changed = common.filter { shot in
            var now = shot.result
            if !hadRows { (now.row, now.rowObsolete, now.rowAll) = (nil, nil, nil) }
            return before.shots[shot.name] != now
        }.sorted { $0.name < $1.name }.map { shot in
            "| \(shot.name) | \(describe(before.shots[shot.name])) | \(describe(shot.result)) |"
        }
        var lines = ["## Against the earlier run", "", "\(common.count) shots in both runs.", "",
                     "| Score | Before | Now | Change |", "| --- | ---: | ---: | ---: |"] + rows + [""]
        if !changed.isEmpty { lines += ["| Changed shot | Before | Now |", "| --- | --- | --- |"] + changed + [""] }
        return lines
    }

    /// E.g. "rows 1 · 1 · 2, rank 3, part ok": the rows with the switches off, obsolete on and all on.
    private static func describe(_ result: ShotResult?) -> String {
        guard let r = result else { return "–" }
        let neck = r.neck.map { $0 ? ", neck found" : ", neck missed" } ?? ""
        let rows = r.hasRows ? "rows \(number(r.row)) · \(number(r.rowObsolete)) · \(number(r.rowAll)), " : ""
        return "\(rows)rank \(number(r.rank)), part \(r.part ? "ok" : "wrong")\(neck)"
    }
}
