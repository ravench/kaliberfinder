import Foundation

/// A catalogue cartridge that may be the one in the photo.
struct Match: Identifiable, Equatable {
    let cartridge: Cartridge
    /// Higher is better. Text hits add 2 (strong) or 0.5 (weak) to the shape score (0…1).
    let score: Double
    let headstamp: HeadstampReader.Hit?
    /// `ShapeMatcher.distance` to the photo, if the photo showed the cartridge from the side.
    let shapeDistance: Double?

    var id: String { cartridge.id }

    enum Fit { case good, rough, poor }

    var shapeFit: Fit? {
        guard let d = shapeDistance else { return nil }
        return d < 0.15 ? .good : (d < 0.35 ? .rough : .poor)
    }
}

/// Combines the photo's shape and the text found in it into a ranked list of calibres.
enum Matcher {
    static func rank(shape: ShapeMeasurement?,
                     hits: [HeadstampReader.Hit],
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
            switch hit?.strength {
            case .strong: score += 2
            case .weak: score += 0.5
            case nil: break
            }
            matches.append(Match(cartridge: c, score: score, headstamp: hit, shapeDistance: distance))
        }
        return Array(matches.sorted { $0.score > $1.score }.prefix(limit))
    }
}
