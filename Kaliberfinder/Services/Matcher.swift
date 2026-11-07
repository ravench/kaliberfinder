import Foundation

/// A catalogue cartridge that may be the one in the photo.
struct Match: Identifiable, Equatable {
    let cartridge: Cartridge
    /// Higher is better: shape score (0…1) plus size score (0…1, with LiDAR).
    let score: Double
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

    /// Shape and size both fit well: the row is highlighted in green.
    var fitsWell: Bool { shapeFit == .good && sizeFit == .good }
}

/// What the user is photographing (SCAN-01): the app decides by itself (`auto`), or the user
/// overrides that with one of the `choices`.
enum ScanMode: String, CaseIterable, Identifiable {
    case auto
    case cartridge
    case emptyCase

    var id: String { rawValue }

    /// The two segments of the picker; the one the app detects is highlighted until the user taps the other.
    static let choices: [ScanMode] = [.cartridge, .emptyCase]

    /// German text of a choice, used as localization key.
    var title: String {
        switch self {
        case .emptyCase: "Leere Hülse"
        default: "Patrone"
        }
    }

    /// The choice that matches what the app detects in this outline.
    static func detected(in shape: ShapeMeasurement) -> ScanMode {
        auto.part(for: shape) == .emptyCase ? .emptyCase : .cartridge
    }

    /// What to compare the photo with. Automatic: a square-cut end is a case mouth, a
    /// narrowing end a bullet tip (SCAN-02). In a photo the first slice is often only partly
    /// filled, so a neck that runs right up to the end also marks an empty case: on a loaded
    /// round the bullet narrows in front of it.
    func part(for shape: ShapeMeasurement) -> ShapePart {
        switch self {
        case .cartridge: .cartridge
        case .emptyCase: .emptyCase
        case .auto:
            shape.features?.isFlatEnd == true || (shape.neck?.slices.lowerBound ?? .max) <= 2 ? .emptyCase : .cartridge
        }
    }
}

/// Ranks the calibres by the photo's side profile (shape, and size with LiDAR).
enum Matcher {
    /// Side views further off than this are not listed (SCAN-04)…
    static let maxShapeDistance = 0.35
    /// …nor those clearly worse than the best match.
    static let maxBehindBest = 0.25
    /// …nor those whose size, measured with LiDAR, is off by more than this many mm.
    static let maxSizeDeviation = 3.0

    static func rank(shape: ShapeMeasurement?,
                     size: MeasuredSize? = nil,
                     mode: ScanMode = .auto,
                     cartridges: [Cartridge] = CartridgeCatalog.current,
                     brass: Bool = false,
                     limit: Int = 12) -> [Match] {
        let photoPart = shape.map { mode.part(for: $0) } ?? .cartridge
        var matches: [Match] = []
        // A brass-coloured object is no lead ball, Minié bullet or air gun pellet.
        for c in cartridges where !brass || c.hasCase {
            // Calibres without a case (balls, Minié bullets) are compared whole, and so is a blank:
            // its case is the whole cartridge, and a fired one's crimp and rim don't fit the case checks.
            let part: ShapePart = c.hasCase && !c.blank ? photoPart : .cartridge
            var distance: Double?
            // A round silhouette is either a cartridge seen end-on or a round ball: compare
            // round with round and long with long only.
            if let shape, var e = expected(c, part), e.isEndView == shape.isEndView {
                if c.blank { e = ShapeMatcher.tilted(e, toward: shape) }
                // Rim, neck and case length only mean something for side views of calibres with a case.
                distance = c.hasCase && !shape.isEndView
                    ? ShapeMatcher.distance(shape, to: e, part: part, neckRatio: c.dimensions.neck / c.dimensions.base,
                                            caseRatio: c.dimensions.caseLength / c.outline.height)
                    : ShapeMatcher.distance(shape, e)
            }
            // The size only says something about cartridges compared from the side.
            var sizeDeviation: Double?
            if distance != nil, shape?.isEndView == false, let size { sizeDeviation = deviation(of: c, from: size, part: part) }
            // A round silhouette says little about the calibre, so only side views are cut off.
            let sideView = shape?.isEndView == false
            guard let distance, !sideView || distance <= maxShapeDistance else { continue }
            if let sizeDeviation, sizeDeviation > maxSizeDeviation { continue }
            let score = exp(-3 * distance) + (sizeDeviation.map { exp(-$0 / 2) } ?? 0)
            matches.append(Match(cartridge: c, score: score, shapeDistance: distance,
                                 sizeDeviation: sizeDeviation, part: part))
        }
        if shape?.isEndView == false {
            let best = matches.compactMap(\.shapeDistance).min() ?? 0
            matches.removeAll { ($0.shapeDistance ?? 0) > best + maxBehindBest }
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
