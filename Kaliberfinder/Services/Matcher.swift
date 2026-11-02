import Foundation

/// A catalogue cartridge that may be the one in the photo.
struct Match: Identifiable, Equatable {
    let cartridge: Cartridge
    /// Higher is better: shape score (0…1) plus size score (0…1, with LiDAR); text hits add 3 (strong) or 0.5 (weak).
    let score: Double
    let headstamp: HeadstampReader.Hit?
    /// `ShapeMatcher.distance` to the photo, if the photo showed the cartridge from the side.
    let shapeDistance: Double?
    /// Mean difference to the size measured with LiDAR, beyond its uncertainty, in mm.
    var sizeDeviation: Double?

    var id: String { cartridge.id }

    enum Fit { case good, rough, poor }

    var shapeFit: Fit? {
        guard let d = shapeDistance else { return nil }
        return d < 0.15 ? .good : (d < 0.35 ? .rough : .poor)
    }

    /// Same thresholds as measured dimensions (MEAS-03).
    var sizeFit: Fit? {
        guard let d = sizeDeviation else { return nil }
        return d <= 0.3 ? .good : (d <= 1.0 ? .rough : .poor)
    }
}

/// Combines the photo's shape and the text found in it into a ranked list of calibres.
enum Matcher {
    static func rank(shape: ShapeMeasurement?,
                     hits: [HeadstampReader.Hit],
                     size: MeasuredSize? = nil,
                     cartridges: [Cartridge] = CartridgeCatalog.all,
                     expected: [String: ShapeMeasurement] = ShapeMatcher.catalogue,
                     limit: Int = 8) -> [Match] {
        let hitByID = Dictionary(hits.map { ($0.cartridgeID, $0) }, uniquingKeysWith: { a, _ in a })
        var matches: [Match] = []
        for c in cartridges {
            let hit = hitByID[c.id]
            var distance: Double?
            // A round silhouette is either a cartridge seen end-on or a round ball: compare
            // round with round and long with long only.
            if let shape, let e = expected[c.id], e.isEndView == shape.isEndView { distance = ShapeMatcher.distance(shape, e) }
            guard hit != nil || distance != nil else { continue }
            var score = distance.map { exp(-3 * $0) } ?? 0
            // The size only says something about cartridges compared from the side.
            var sizeDeviation: Double?
            if distance != nil, shape?.isEndView == false, let size { sizeDeviation = deviation(of: c, from: size) }
            score += sizeDeviation.map { exp(-$0 / 2) } ?? 0
            switch hit?.strength {
            // More than shape and size together can reach, so a strong text hit stays first.
            case .strong: score += 3
            case .weak: score += 0.5
            case nil: break
            }
            matches.append(Match(cartridge: c, score: score, headstamp: hit, shapeDistance: distance, sizeDeviation: sizeDeviation))
        }
        return Array(matches.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// Like measured dimensions (MEAS-02), with the measurement's own uncertainty as tolerance
    /// (at least 0.15 mm): mean over length and body diameter. The outline's body is the base,
    /// so the diameter is compared with the base, not the rim.
    static func deviation(of c: Cartridge, from size: MeasuredSize) -> Double {
        let d = c.dimensions
        let length = max(0, abs(size.length - d.overallLength) - max(DimensionMatcher.tolerance, size.lengthError))
        let diameter = max(0, abs(size.diameter - d.base) - max(DimensionMatcher.tolerance, size.diameterError))
        return (length + diameter) / 2
    }
}
