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
    /// Whether the photo was compared with the whole cartridge or with its empty case.
    var part: ShapePart = .cartridge

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

/// What the user is photographing (SCAN-01): the app decides by itself, or the user says so.
enum ScanMode: String, CaseIterable, Identifiable {
    case auto
    case cartridge
    case emptyCase

    static let storageKey = "scanMode"

    var id: String { rawValue }

    /// German text, used as localization key.
    var title: String {
        switch self {
        case .auto: "Automatisch"
        case .cartridge: "Patrone"
        case .emptyCase: "Leere Hülse"
        }
    }

    /// What to compare the photo with. Automatic: a square-cut end is a case mouth, a
    /// narrowing end a bullet tip (SCAN-02).
    func part(for shape: ShapeMeasurement) -> ShapePart {
        switch self {
        case .cartridge: .cartridge
        case .emptyCase: .emptyCase
        case .auto: shape.features?.isFlatEnd == true ? .emptyCase : .cartridge
        }
    }
}

/// Combines the photo's shape and the text found in it into a ranked list of calibres.
enum Matcher {
    /// Side views further off than this are not listed (SCAN-04), unless the text names the calibre.
    static let maxShapeDistance = 0.35
    /// …nor those clearly worse than the best match.
    static let maxBehindBest = 0.25
    /// …nor those whose size, measured with LiDAR, is off by more than this many mm.
    static let maxSizeDeviation = 3.0

    static func rank(shape: ShapeMeasurement?,
                     hits: [HeadstampReader.Hit],
                     size: MeasuredSize? = nil,
                     mode: ScanMode = .auto,
                     cartridges: [Cartridge] = CartridgeCatalog.all,
                     limit: Int = 8) -> [Match] {
        let hitByID = Dictionary(hits.map { ($0.cartridgeID, $0) }, uniquingKeysWith: { a, _ in a })
        let photoPart = shape.map { mode.part(for: $0) } ?? .cartridge
        var matches: [Match] = []
        for c in cartridges {
            let hit = hitByID[c.id]
            // Calibres without a case (balls, Minié bullets) are compared whole.
            let part: ShapePart = c.hasCase ? photoPart : .cartridge
            var distance: Double?
            // A round silhouette is either a cartridge seen end-on or a round ball: compare
            // round with round and long with long only.
            if let shape, let e = expected(c, part), e.isEndView == shape.isEndView {
                distance = ShapeMatcher.distance(shape, to: e, part: part)
            }
            // The size only says something about cartridges compared from the side.
            var sizeDeviation: Double?
            if distance != nil, shape?.isEndView == false, let size { sizeDeviation = deviation(of: c, from: size, part: part) }
            // A round silhouette says little about the calibre, so only side views are cut off.
            let sideView = shape?.isEndView == false
            if hit == nil {
                guard let distance, !sideView || distance <= maxShapeDistance else { continue }
                if let sizeDeviation, sizeDeviation > maxSizeDeviation { continue }
            }
            var score = distance.map { exp(-3 * $0) } ?? 0
            score += sizeDeviation.map { exp(-$0 / 2) } ?? 0
            switch hit?.strength {
            // More than shape and size together can reach, so a strong text hit stays first.
            case .strong: score += 3
            case .weak: score += 0.5
            case nil: break
            }
            matches.append(Match(cartridge: c, score: score, headstamp: hit, shapeDistance: distance,
                                 sizeDeviation: sizeDeviation, part: part))
        }
        if shape?.isEndView == false {
            let best = matches.filter { $0.headstamp == nil }.compactMap(\.shapeDistance).min() ?? 0
            matches.removeAll { $0.headstamp == nil && ($0.shapeDistance ?? 0) > best + maxBehindBest }
        }
        return Array(matches.sorted { $0.score > $1.score }.prefix(limit))
    }

    private static func expected(_ c: Cartridge, _ part: ShapePart) -> ShapeMeasurement? {
        part == .emptyCase ? ShapeMatcher.caseCatalogue[c.id] : ShapeMatcher.catalogue[c.id]
    }

    /// Like measured dimensions (MEAS-02), with the measurement's own uncertainty as tolerance
    /// (at least 0.15 mm): mean over length and body diameter. The outline's body is the base,
    /// so the diameter is compared with the base, not the rim. An empty case is as long as the case.
    static func deviation(of c: Cartridge, from size: MeasuredSize, part: ShapePart = .cartridge) -> Double {
        let d = c.dimensions
        let expectedLength = part == .emptyCase ? d.caseLength : d.overallLength
        let length = max(0, abs(size.length - expectedLength) - max(DimensionMatcher.tolerance, size.lengthError))
        let diameter = max(0, abs(size.diameter - d.base) - max(DimensionMatcher.tolerance, size.diameterError))
        return (length + diameter) / 2
    }
}
