import Foundation

/// Dimensions measured by hand (e.g. with a calliper), in millimetres. Empty fields are nil.
struct MeasuredDimensions: Equatable {
    var overallLength: Double?
    var caseLength: Double?
    var rim: Double?
    /// The belt of a belted case (tester, 2026-11-14).
    var belt: Double?
    var bullet: Double?
    /// Narrows the list to straight or bottleneck cases.
    var shape: CaseShape = .any
    /// Narrows the list by the case head.
    var head: RimKind = .any

    /// No dimension entered (the shape and the head alone don't rank anything).
    var isEmpty: Bool { [overallLength, caseLength, rim, belt, bullet].allSatisfy { $0 == nil } }
}

/// The case shape picked on the dimensions screen (MEAS-05).
enum CaseShape: String, CaseIterable, Identifiable {
    case any
    case straight
    case bottleneck

    var id: String { rawValue }

    /// German text, used as localization key.
    var title: String {
        switch self {
        case .any: "Beliebig"
        case .straight: "Gerade"
        case .bottleneck: "Flaschenhals"
        }
    }

    /// Bottleneck cases have a shoulder; straight ones (pistol, revolver, shotgun) don't.
    /// Balls, Minié bullets and pellets have no case at all.
    func fits(_ c: Cartridge) -> Bool {
        switch self {
        case .any: true
        case .straight: c.hasCase && c.dimensions.shoulder == nil
        case .bottleneck: c.dimensions.shoulder != nil
        }
    }
}

/// The case head picked on the dimensions screen («Randform», TestFlight 2026-11-16), by calibre-data's kind.
enum RimKind: String, CaseIterable, Identifiable {
    case any
    case rimmed
    case semiRimmed
    case rimless
    case belted

    var id: String { rawValue }

    /// German text, used as localization key.
    var title: String {
        switch self {
        case .any: "Beliebige Randform"
        case .rimmed: "Mit Rand"
        case .semiRimmed: "Halbrand"
        case .rimless: "Randlos"
        case .belted: "Gürtelhülse"
        }
    }

    /// The token `CaseIcon` draws it by (`RoundFacts.head`).
    var token: String { self == .semiRimmed ? "semi" : rawValue }

    /// Rimfire rounds and shotshells have a rim. A semi-rim is hard to tell by eye, so it passes as rimmed
    /// and as rimless too. Balls, Minié bullets and pellets have no head.
    func fits(_ c: Cartridge) -> Bool {
        switch self {
        case .any: true
        case .rimmed: ["rimmed", "rimfire", "shot", "semi-rimmed"].contains(c.kind)
        case .semiRimmed: c.kind == "semi-rimmed"
        case .rimless: ["rimless", "semi-rimmed"].contains(c.kind)
        case .belted: c.kind == "belted"
        }
    }
}

/// A calibre ranked by how far its catalogue dimensions are from the measured ones.
struct DimensionMatch: Identifiable, Equatable {
    let cartridge: Cartridge
    /// Largest difference over the measured fields, in mm.
    let maxDeviation: Double
    /// Average difference over the measured fields, in mm.
    let meanDeviation: Double

    var id: String { cartridge.id }

    var fit: Match.Fit { maxDeviation <= 0.3 ? .good : (maxDeviation <= 1.0 ? .rough : .poor) }
}

/// Finds calibres from measured dimensions, for users who don't want to take a photo.
enum DimensionMatcher {
    /// Catalogue values are rounded and real cartridges vary, so differences up to this many mm count as equal.
    static let tolerance = 0.15
    /// Calibres this far (mm) behind the best are not listed, nor any beyond `maxDeviation`, as after a photo
    /// (`Matcher.maxBehindBest`): the list was always full, down to a 7.9 mm bullet for a 9 mm one (tester, 2026-11-17).
    static let maxBehindBest = 0.5
    static let maxDeviation = 1.5

    static func rank(_ measured: MeasuredDimensions,
                     cartridges: [Cartridge] = CartridgeCatalog.current,
                     limit: Int = 15) -> [DimensionMatch] {
        guard !measured.isEmpty else { return [] }
        // A typed bullet diameter was measured on a bullet: a blank has none (its `dimensions.bullet` only repeats the case's diameter).
        let matches = cartridges.filter { measured.shape.fits($0) && measured.head.fits($0) && !(measured.bullet != nil && $0.blank) }.map { c -> (DimensionMatch, Double) in
            let d = c.dimensions
            // A shotshell is as long as its crimp makes it, or opened by firing to its case length, whichever field it was typed in.
            let shell = c.kind == "shot" ? [c.overallLengths, d.caseLength...d.caseLength] : nil
            let pairs: [(Double?, [ClosedRange<Double>])] = [
                (measured.overallLength, shell ?? [c.overallLengths]),
                (measured.caseLength, shell ?? [d.caseLength...d.caseLength]),
                (measured.rim, [d.rim...d.rim]),  // not the base: a rebated rim is narrower than it
                // A belt as wide as the rim is not in the data (calibre-data gives a belt only where it is wider), and a
                // calliper on the head of a case without one reads the rim: the rim stands in for a missing belt.
                (measured.belt, [(d.belt ?? d.rim)...(d.belt ?? d.rim)]),
                (measured.bullet, [d.bullet...d.bullet]),
            ]
            let deviations = pairs.compactMap { pair in pair.0.map { v in max(0, (pair.1.map { outside(v, $0) }.min() ?? 0) - tolerance) } }
            // Within a shotshell's crimp range, nearer the hull length goes first (12/70 before 12/76), loaded or opened;
            // the catalogue's length is the folded crimp's maximum (calibre-data #155), too short for a roll crimp.
            let typed = measured.overallLength ?? measured.caseLength
            let fromCatalogue = c.kind == "shot" ? typed.map { abs($0 - d.caseLength) } ?? 0 : 0
            return (DimensionMatch(cartridge: c,
                                   maxDeviation: deviations.max() ?? 0,
                                   meanDeviation: deviations.reduce(0, +) / Double(deviations.count)), fromCatalogue)
        }
        let ranked = matches.sorted {
            ($0.0.meanDeviation, $0.0.maxDeviation, $0.1) < ($1.0.meanDeviation, $1.0.maxDeviation, $1.1)
        }.map(\.0)
        let best = ranked.map(\.maxDeviation).min() ?? 0
        return Array(ranked.filter { $0.maxDeviation <= min(maxDeviation, best + maxBehindBest) }.prefix(limit))
    }

    /// How far `value` lies outside `range` (0 inside it).
    static func outside(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        max(0, range.lowerBound - value, value - range.upperBound)
    }

    /// What the compare button shows when nothing is selected (MEAS-04): every calibre that fits
    /// well or roughly, or the best three when none does.
    /// Calibres that look exactly the same are compared once; they stand by length (`CompareLength`).
    static func toCompare(_ matches: [DimensionMatch], by: CompareLength = .current) -> [Cartridge] {
        let rows = grouped(matches).map(\.lead)
        let fitting = rows.filter { $0.fit != .poor }.map(\.cartridge)
        return (fitting.isEmpty ? Array(rows.prefix(3).map(\.cartridge)) : fitting).byLength(by)
    }

    /// Reads millimetres typed with either decimal separator, e.g. "29,7" or "29.7". Empty or invalid text is nil.
    static func number(_ text: String) -> Double? {
        LengthUnit.metric.parse(text)
    }
}
