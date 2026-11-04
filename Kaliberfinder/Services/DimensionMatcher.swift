import Foundation

/// Dimensions measured by hand (e.g. with a calliper), in millimetres. Empty fields are nil.
struct MeasuredDimensions: Equatable {
    var overallLength: Double?
    var caseLength: Double?
    var rim: Double?
    var bullet: Double?
    /// Narrows the list to straight or bottleneck cases.
    var shape: CaseShape = .any

    /// No dimension entered (the shape alone doesn't rank anything).
    var isEmpty: Bool { [overallLength, caseLength, rim, bullet].allSatisfy { $0 == nil } }
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
        case .any: "Beliebige Form"
        case .straight: "Gerade Hülse"
        case .bottleneck: "Hülse mit Flaschenhals"
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

    static func rank(_ measured: MeasuredDimensions,
                     cartridges: [Cartridge] = CartridgeCatalog.current,
                     limit: Int = 15) -> [DimensionMatch] {
        guard !measured.isEmpty else { return [] }
        let matches = cartridges.filter(measured.shape.fits).map { c -> DimensionMatch in
            let d = c.dimensions
            let pairs: [(Double?, Double)] = [
                (measured.overallLength, d.overallLength),
                (measured.caseLength, d.caseLength),
                (measured.rim, max(d.rim, d.base)),
                (measured.bullet, d.bullet),
            ]
            let deviations = pairs.compactMap { pair in pair.0.map { max(0, abs($0 - pair.1) - tolerance) } }
            return DimensionMatch(cartridge: c,
                                  maxDeviation: deviations.max() ?? 0,
                                  meanDeviation: deviations.reduce(0, +) / Double(deviations.count))
        }
        return Array(matches.sorted {
            ($0.meanDeviation, $0.maxDeviation) < ($1.meanDeviation, $1.maxDeviation)
        }.prefix(limit))
    }

    /// What the compare button shows when nothing is selected (MEAS-04): every calibre that fits
    /// well or roughly, or the best three when none does.
    /// Calibres that look exactly the same are compared once.
    static func toCompare(_ matches: [DimensionMatch]) -> [Cartridge] {
        let rows = grouped(matches).map(\.lead)
        let fitting = rows.filter { $0.fit != .poor }.map(\.cartridge)
        return fitting.isEmpty ? Array(rows.prefix(3).map(\.cartridge)) : fitting
    }

    /// Reads millimetres typed with either decimal separator, e.g. "29,7" or "29.7". Empty or invalid text is nil.
    static func number(_ text: String) -> Double? {
        LengthUnit.metric.parse(text)
    }
}
