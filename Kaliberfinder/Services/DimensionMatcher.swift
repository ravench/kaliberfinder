import Foundation

/// Dimensions measured by hand (e.g. with a calliper), in millimetres. Empty fields are nil.
struct MeasuredDimensions: Equatable {
    var overallLength: Double?
    var caseLength: Double?
    var rim: Double?
    var bullet: Double?

    var isEmpty: Bool { [overallLength, caseLength, rim, bullet].allSatisfy { $0 == nil } }
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
                     cartridges: [Cartridge] = CartridgeCatalog.all,
                     limit: Int = 10) -> [DimensionMatch] {
        guard !measured.isEmpty else { return [] }
        let matches = cartridges.map { c -> DimensionMatch in
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

    /// Reads millimetres typed with either decimal separator, e.g. "29,7" or "29.7". Empty or invalid text is nil.
    static func number(_ text: String) -> Double? {
        LengthUnit.metric.parse(text)
    }
}
