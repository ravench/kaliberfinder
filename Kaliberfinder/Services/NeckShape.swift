import Foundation

/// The neck of a bottleneck case as the silhouette shows it (SHAPE-06): the narrow, straight part
/// in front of the shoulder. Found in the slice widths, so the photo and the catalogue outline are
/// measured the same way. A loaded round's neck runs on over the bullet's straight part when the
/// two are about as wide.
struct NeckShape: Equatable {
    /// Width relative to the body: GP 11 about 0.68, .223 Remington about 0.67.
    let width: Double
    /// Length in body diameters.
    let length: Double
    /// Slices (tip first) the neck covers, and the last slice of the shoulder, next to the body.
    let slices: ClosedRange<Int>
    let shoulderSlice: Int

    /// Slices narrower than this between the neck and the body belong to the shoulder.
    static let bodyFrom = 0.9
    /// A neck is no wider than this. Straight cases narrow to 0.88 or more at the bullet, and their
    /// bullets taper off without a straight run, so they show none. Noise in a photo can make a
    /// slice of the body a little narrower than the body, but not this narrow.
    static let neckUpTo = 0.85
    /// Slices of one neck differ by no more than this.
    static let straightWithin = 0.04
    /// A shoulder narrows over at most this many slices.
    static let maxShoulderSlices = 4
    /// Necks at least this narrow are clearly there: a photo showing one rules out calibres with a
    /// much wider neck, and a calibre with one is unlikely when the photo shows none.
    static let clearUpTo = 0.8

    /// Nil when the widths show no neck. `widths` run tip (or case mouth) first, relative to the body.
    init?(widths w: [Double], aspect: Double) {
        let n = w.count
        // The rim, belt and extractor groove sit in the last 15 %; the body starts in front of them.
        let bodyEnd = n - 1 - n * 15 / 100
        guard bodyEnd > 0 else { return nil }
        // Toward the tip, the first slice narrow enough for a neck.
        var i = bodyEnd
        while i >= 0 && w[i] > Self.neckUpTo { i -= 1 }
        guard i >= 1, i < bodyEnd else { return nil }
        // The narrowest of the next few slices is in the neck, past any flat step on a blurred
        // shoulder. The first slice is left out: it is often only partly filled.
        let around = max(1, i - Self.maxShoulderSlices)...i
        guard var start = around.min(by: { w[$0] < w[$1] || (w[$0] == w[$1] && $0 > $1) }) else { return nil }
        // The neck: the straight run around it, at least three slices long unless it runs to the
        // case mouth. A short flat on a round-nose bullet is no neck.
        let narrowest = w[start]
        var end = start
        while end > 0 && abs(w[end - 1] - narrowest) <= Self.straightWithin { end -= 1 }
        while start + 1 <= i && abs(w[start + 1] - narrowest) <= Self.straightWithin { start += 1 }
        guard start - end >= 2 || (start > end && end <= 1) else { return nil }
        // The shoulder runs on to the first slice as wide as the body.
        var shoulder = i
        while shoulder + 1 < bodyEnd && shoulder - i < Self.maxShoulderSlices && w[shoulder + 1] < Self.bodyFrom { shoulder += 1 }
        let run = w[end...start].sorted()
        width = run[run.count / 2]
        length = Double(run.count) / Double(n) * aspect
        slices = end...start
        shoulderSlice = shoulder
    }

    var isClear: Bool { width <= Self.clearUpTo }
}

extension ShapeMeasurement {
    /// The neck, if the slice widths are known and show one.
    var neck: NeckShape? { widths.count == ShapeMatcher.bins ? NeckShape(widths: widths, aspect: aspect) : nil }
}
