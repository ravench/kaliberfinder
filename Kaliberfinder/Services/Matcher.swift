import Foundation

/// A catalogue cartridge that may be the one in the photo.
struct Match: Identifiable, Equatable {
    let cartridge: Cartridge
    /// Higher is better: minus the distance (`Matcher.distance`).
    let score: Double
    /// `Matcher.distance` to the photo: shape, size and what the photo's colours add; nil for an end view
    /// compared with a round thing.
    let shapeDistance: Double?
    /// Mean difference to the size measured with LiDAR, beyond its tolerance, in mm.
    var sizeDeviation: Double?
    /// Whether the photo was compared with the whole cartridge or with its empty case.
    var part: ShapePart = .cartridge

    var id: String { cartridge.id }

    enum Fit { case good, rough, poor }

    /// On the training shots (2026-11-08) the right calibre's distance is 0.24 in the middle and under
    /// 0.47 in nine of ten shots where it comes first.
    var shapeFit: Fit? {
        guard let d = shapeDistance else { return nil }
        return d < Matcher.goodDistance ? .good : (d < Matcher.roughDistance ? .rough : .poor)
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

    /// What to compare the photo with when nothing else decides: a square-cut end is a case mouth, a
    /// narrowing end a bullet tip (SCAN-02). Matching itself weighs both (`Matcher.rank`): the end's width
    /// says how likely each is, and the better comparison wins per calibre.
    func part(for shape: ShapeMeasurement) -> ShapePart {
        switch self {
        case .cartridge: .cartridge
        case .emptyCase: .emptyCase
        case .auto:
            Matcher.endIsAMouth(shape) || Matcher.endWidth(shape) >= Matcher.partMiddle ? .emptyCase : .cartridge
        }
    }
}

/// Ranks the calibres by the photo's side profile (shape, size with LiDAR, and the colours), as the
/// matcher rewritten from scratch on the training shots does (tools/research/matcher, 2026-11-08). The
/// weights are the ones fitted there.
enum Matcher {
    // MARK: Weights (tools/research/matcher/params.json)

    /// Length over width, as |log(photo / calibre)|.
    static let aspectWeight = 0.5
    /// Mean difference of the slice widths (relative to the body), the narrow end first and the other
    /// way round; the better way counts.
    static let profileWeight = 6.0
    /// A rim (relative to the body) off by more than `rimTolerance` costs `rimPenalty`.
    static let rimPenalty = 0.05
    static let rimTolerance = 0.1
    /// LiDAR size: per 10 mm beyond the tolerance.
    static let lengthWeight = 2.0
    static let lengthTolerance = 2.0
    /// Inside a shotshell's crimp range (`Cartridge.overallLengths`) the catalogue's length still counts,
    /// this much: a folded 12/70 is no outsider, but a 64 mm shell is still a 12/70 before a 12/76.
    static let crimpRangeWeight = 0.25
    static let diameterWeight = 1.0
    static let diameterTolerance = 0.3
    /// The measured length is a little long, the diameter a little short (2026-11-08: +3.4 % and −0.3 % on
    /// the training shots after the end rise).
    static let lengthScaleWhole = 0.98
    static let lengthScaleCase = 0.96
    static let diameterScale = 1.02
    /// The end's width (median of the first three slices, relative to the body) that is as likely a case
    /// mouth as a bullet tip; farther on either side costs `partWeight` per unit, a flat end twice.
    static let partWeight = 0.5
    static let partMiddle = 0.7
    /// The case's share of the length where the colours show the mouth (`ShapeContour.mouth`), against the
    /// calibre's, and with LiDAR the case's length in mm; each capped, since real cartridges differ from
    /// the catalogue (a long silver bullet on Raven's GP 11, a brass band on the Vetterli).
    static let shareWeight = 0.5
    static let shareTolerance = 0.03
    static let caseLengthWeight = 0.5
    static let caseLengthTolerance = 0.3
    static let mouthCap = 0.05

    /// Fit labels (`Match.shapeFit`).
    static let goodDistance = 0.3
    static let roughDistance = 0.6
    /// Calibres this far behind the best are not listed (SCAN-04), nor any beyond `maxDistance`: on the
    /// training shots the right calibre lies within 0.25 of the best in nine of ten shots where it is not first.
    static let maxBehindBest = 0.5
    static let maxDistance = 1.5

    /// Kinds without a bullet to seat: compared whole, like blanks.
    static let wholeKinds: Set<String> = ["shot", "ball", "minie", "pellet"]

    /// A square-cut end, or a neck that runs right up to the end (on a loaded round the bullet narrows in
    /// front of it): the end is a case mouth, and in automatic mode a calibre with a bullet is compared
    /// as an empty case only. Otherwise the end's width weighs both comparisons (`partWeight`).
    static func endIsAMouth(_ shape: ShapeMeasurement) -> Bool {
        shape.features?.isFlatEnd == true || (shape.neck?.slices.lowerBound ?? .max) <= 2
    }

    /// Added when the photo shows a clear neck (`NeckShape.clearUpTo`) and the calibre's neck, over its
    /// base, is wider by more than `neckTolerance`: a straight case, or a slight bottleneck like the .32-20
    /// (Raven 2026-11-05: an empty GP 11 case taken for a .30 Carbine).
    static let neckPenalty = 0.3
    static let neckTolerance = 0.15

    /// Median width of the first three slices, relative to the body (the narrow end first); 0 without slices.
    static func endWidth(_ shape: ShapeMeasurement) -> Double {
        guard shape.widths.count >= 3 else { return 0 }
        return shape.widths.prefix(3).sorted()[1]
    }

    /// What the photo gives the matching: its silhouette as measured (not corrected for the end rise), its
    /// LiDAR size the same way (`PhotoAnalysis.rawSize`), its body width over the focal length
    /// (`PhotoAnalysis.perspective`), and where the colours put the case mouth, as a fraction of the
    /// length from the tip (`ShapeContour.mouth`).
    struct Photo {
        let shape: ShapeMeasurement
        var size: MeasuredSize?
        var perspective: Double?
        var mouth: Double?
    }

    /// One side of a calibre to compare with: its outline, its length and diameter in mm, the scale the
    /// measured length gets, and how high its ends stand above the axis of the lying cartridge, in body
    /// widths (a bullet tip lies on the axis, a case mouth or a crimp half its width up, the head half the rim).
    struct Expected {
        let shape: ShapeMeasurement
        /// The catalogue's length, and the lengths a loaded round can have (a shotshell's depend on its crimp).
        let length: Double
        var lengths: ClosedRange<Double>?
        let diameter: Double
        let lengthScale: Double
        let front: Double
        let back: Double
    }

    static func rank(shape: ShapeMeasurement?,
                     size: MeasuredSize? = nil,
                     perspective: Double? = nil,
                     mouth: Double? = nil,
                     mode: ScanMode = .auto,
                     cartridges: [Cartridge] = CartridgeCatalog.current,
                     brass: Bool = false,
                     limit: Int = 12) -> [Match] {
        guard let shape else { return [] }
        let photo = Photo(shape: shape, size: size, perspective: perspective, mouth: mouth)
        var matches: [Match] = []
        // A brass-coloured object is no lead ball, Minié bullet or air gun pellet.
        for c in cartridges where !brass || c.hasCase {
            guard let scored = score(photo, c, mode: mode) else { continue }
            matches.append(scored)
        }
        matches.sort { $0.score > $1.score }
        if !shape.isEndView, let best = matches.first?.shapeDistance {
            matches.removeAll { ($0.shapeDistance ?? .infinity) > min(maxDistance, best + maxBehindBest) }
        }
        return Array(matches.prefix(limit))
    }

    /// One calibre against the photo: the better of the whole cartridge and its empty case, unless `mode`
    /// says which; nil when nothing compares (a round silhouette against a long one, or the reverse).
    static func score(_ photo: Photo, _ c: Cartridge, mode: ScanMode) -> Match? {
        let shape = photo.shape
        let wholeOnly = c.blank || !c.hasCase || wholeKinds.contains(c.kind)
        let whole = ShapeMatcher.catalogue[c.id]
        let emptyCase = wholeOnly ? nil : ShapeMatcher.caseCatalogue[c.id]
        // A round silhouette is either a cartridge seen end-on or a round ball: compare round with round only.
        if shape.isEndView {
            guard let whole, whole.isEndView else { return nil }
            let d = aspectWeight * abs(log(shape.aspect / whole.aspect)) + profileWeight * profileDifference(shape, whole)
            return Match(cartridge: c, score: -d, shapeDistance: nil, sizeDeviation: nil, part: .cartridge)
        }
        let end = endWidth(shape)
        let hasBullet = c.hasCase && !wholeOnly
        let caseOnly = mode == .emptyCase || (mode == .auto && hasBullet && endIsAMouth(shape))
        let neck = shape.neck.flatMap { $0.isClear && c.dimensions.neck / c.dimensions.base > $0.width + neckTolerance ? neckPenalty : 0 } ?? 0
        var candidates: [(distance: Double, deviation: Double?, part: ShapePart)] = []
        if !caseOnly || emptyCase == nil, let whole, !whole.isEndView {
            // A bullet's tip lies on the axis; a crimp or a ball's end stands half its width above it.
            let front = hasBullet ? 0 : endWidth(whole) / 2
            var (d, deviation) = distance(photo, Expected(shape: whole, length: c.dimensions.overallLength, lengths: c.overallLengths,
                                                          diameter: c.dimensions.base, lengthScale: lengthScaleWhole, front: front,
                                                          back: rim(whole) / 2))
            // Blanks, shotshells and balls have no bullet to narrow: their end is as it is.
            if mode == .auto, hasBullet { d += partWeight * max(0, end - partMiddle) }
            if hasBullet, let mouth = photo.mouth { d += mouthPenalty(mouth, c, size: photo.size) }
            candidates.append((d + neck, deviation, .cartridge))
        }
        if mode != .cartridge, let emptyCase, !emptyCase.isEndView {
            var (d, deviation) = distance(photo, Expected(shape: emptyCase, length: c.dimensions.caseLength, diameter: c.dimensions.base,
                                                          lengthScale: lengthScaleCase, front: endWidth(emptyCase) / 2, back: rim(emptyCase) / 2))
            if mode == .auto, !caseOnly { d += partWeight * max(0, partMiddle - end) }
            candidates.append((d + neck, deviation, .emptyCase))
        }
        guard let best = candidates.min(by: { $0.distance < $1.distance }) else { return nil }
        return Match(cartridge: c, score: -best.distance, shapeDistance: best.distance, sizeDeviation: best.deviation, part: best.part)
    }

    /// Shape and size against one expected outline, and the size deviation shown for it. With the photo's
    /// perspective, the expected ends' heights say how much longer the outline looks than the cartridge at
    /// its axis's height (`EndRise`).
    static func distance(_ photo: Photo, _ expected: Expected) -> (Double, Double?) {
        let shape = photo.shape
        let aspect = aspectWeight * abs(log(shape.aspect / expected.shape.aspect))
        let ways = shape.widths.count == ShapeMatcher.bins ? [shape, shape.reversed()] : [shape]
        var d = Double.infinity
        for way in ways {
            var rimPen = 0.0
            if let a = way.features, let b = expected.shape.features, abs(a.rim - b.rim) > rimTolerance { rimPen = rimPenalty }
            d = min(d, aspect + profileWeight * profileDifference(way, expected.shape) + rimPen)
        }
        guard let size = photo.size else { return (d, nil) }
        var rise = 1.0
        if let p = photo.perspective, p > 0, p < 0.5 { rise = (1 / (1 - expected.front * p) + 1 / (1 - expected.back * p)) / 2 }
        let length = size.length * expected.lengthScale / rise, diameter = size.diameter * diameterScale
        let lengths = expected.lengths ?? expected.length...expected.length
        let lengthOff = max(0, DimensionMatcher.outside(length, lengths) - lengthTolerance)
        // Within the range, the catalogue's length counts `crimpRangeWeight` as much (0 for a single length).
        let fromCatalogue = max(0, abs(length - expected.length) - lengthTolerance) - lengthOff
        let diameterOff = max(0, abs(diameter - expected.diameter) - diameterTolerance)
        d += lengthWeight * (lengthOff + crimpRangeWeight * fromCatalogue) / 10 + diameterWeight * diameterOff / 10
        return (d, (lengthOff + diameterOff) / 2)
    }

    /// Mean difference of the slice widths (relative to the body), or of the coarse profile where a shape
    /// was built by hand without slices.
    static func profileDifference(_ a: ShapeMeasurement, _ b: ShapeMeasurement) -> Double {
        if a.widths.count == ShapeMatcher.bins, b.widths.count == ShapeMatcher.bins {
            return zip(a.widths, b.widths).reduce(0) { $0 + abs($1.0 - $1.1) } / Double(ShapeMatcher.bins)
        }
        guard a.profile.count == b.profile.count, !a.profile.isEmpty else { return 1 }
        return zip(a.profile, b.profile).reduce(0) { $0 + abs($1.0 - $1.1) } / Double(a.profile.count)
    }

    /// The expected rim relative to the body (1 where the shape has no slices).
    static func rim(_ expected: ShapeMeasurement) -> Double { expected.features?.rim ?? 1 }

    /// What the case mouth the colours show adds to a loaded round's distance to calibre `c`: its share of
    /// the length against the calibre's, and with LiDAR the case's length in mm, each capped at `mouthCap`.
    static func mouthPenalty(_ mouth: Double, _ c: Cartridge, size: MeasuredSize?) -> Double {
        let share = 1 - mouth
        let expectedShare = c.dimensions.caseLength / c.dimensions.overallLength
        var penalty = min(mouthCap, shareWeight * max(0, abs(share - expectedShare) - shareTolerance))
        if let size {
            let caseLength = size.length * lengthScaleWhole * share
            penalty += min(mouthCap, caseLengthWeight * max(0, abs(caseLength - c.dimensions.caseLength) - caseLengthTolerance) / 10)
        }
        return penalty
    }
}
