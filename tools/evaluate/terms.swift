// The matcher's raw terms for every shot and calibre, written by `evaluate --terms FILE` (one JSON object per
// line per shot), so tools/research/matcher/refit.py can search the weights on what the app measured
// (2026-11-12). Mirrors `Matcher.score` and `Matcher.distance` without their weights: whatever a weight
// multiplies is a term here, whatever a tolerance clips is a raw difference.
import Foundation

enum Terms {
    /// The calibres in catalogue order, once at the top of the file.
    static func catalogue() -> String {
        let all = CartridgeCatalog.all
        var group = [String: Int]()
        for (i, twins) in CartridgeCatalog.groupedByProfile(all, cartridge: { $0 }).enumerated() {
            for c in twins { group[c.id] = i }
        }
        let rows = all.map { c -> String in
            let wholeOnly = c.blank || !c.hasCase || Matcher.wholeKinds.contains(c.kind)
            let whole = ShapeMatcher.catalogue[c.id], emptyCase = wholeOnly ? nil : ShapeMatcher.caseCatalogue[c.id]
            let d = c.dimensions
            return "{\"id\":\(json(c.id)),\"rare\":\(c.rare),\"obsolete\":\(c.obsolete),\"hasCase\":\(c.hasCase),\"shot\":\(c.kind == "shot"),"
                + "\"wholeOnly\":\(wholeOnly),\"hasWhole\":\(whole != nil),\"wholeEndView\":\(whole?.isEndView ?? false),"
                + "\"hasCaseShape\":\(emptyCase != nil),\"caseEndView\":\(emptyCase?.isEndView ?? false),\"group\":\(group[c.id] ?? -1),"
                + "\"case\":\(d.caseLength),\"overall\":\(d.overallLength),\"neckRatio\":\(d.neck / d.base)}"
        }
        return "{\"catalogue\":[\(rows.joined(separator: ","))]}"
    }

    /// One shot: what the photo gave, and per calibre the terms of its whole, empty-case and hull comparisons.
    static func shot(_ name: String, calibre: String, part: ScanMode, analysis: PhotoAnalysis, depth: DepthScale?) -> String? {
        guard let shape = analysis.shape else { return nil }
        let photo = Matcher.Photo(shape: shape, size: analysis.rawSize(depth: depth), perspective: analysis.perspective(depth: depth),
                                  mouth: analysis.contour?.mouth)
        let decided = Matcher.decidedPart(photo)
        let ways = shape.widths.count == ShapeMatcher.bins ? [shape, shape.reversed()] : [shape]
        var keys: [String: [String]] = [:]
        func put(_ key: String, _ value: Double?) { keys[key, default: []].append(value.map(number) ?? "null") }
        for c in CartridgeCatalog.all {
            let wholeOnly = c.blank || !c.hasCase || Matcher.wholeKinds.contains(c.kind)
            let hasBullet = c.hasCase && !wholeOnly
            let whole = ShapeMatcher.catalogue[c.id], emptyCase = wholeOnly ? nil : ShapeMatcher.caseCatalogue[c.id]
            var expected: [(String, Matcher.Expected?)] = [("w", whole.map { Matcher.wholeExpected(c, $0, hasBullet: hasBullet) })]
            expected.append(("c", emptyCase.map {
                Matcher.Expected(shape: $0, length: c.dimensions.caseLength, diameter: c.dimensions.base, lengthScale: Matcher.lengthScaleCase,
                                 front: Matcher.endWidth($0) / 2, back: Matcher.rim($0) / 2)
            }))
            if c.kind == "shot", let whole {
                let hull = ShapeMeasurement(aspect: whole.aspect * c.dimensions.caseLength / c.dimensions.overallLength, profile: whole.profile, widths: whole.widths)
                expected.append(("h", Matcher.Expected(shape: hull, length: c.dimensions.caseLength, diameter: c.dimensions.base,
                                                       lengthScale: Matcher.lengthScaleWhole, front: Matcher.endWidth(hull) / 2, back: Matcher.rim(hull) / 2)))
            } else {
                expected.append(("h", nil))
            }
            for (tag, e) in expected {
                guard let e else {
                    for k in ["a", "prof0", "prof1", "rimd0", "rimd1", "missing", "len", "lo", "hi", "dia", "front", "back"] { put("\(tag)_\(k)", nil) }
                    continue
                }
                put("\(tag)_a", abs(log(shape.aspect / e.shape.aspect)))
                put("\(tag)_prof0", Matcher.profileDifference(ways[0], e.shape))
                put("\(tag)_prof1", ways.count > 1 ? Matcher.profileDifference(ways[1], e.shape) : nil)
                let b = e.shape.features
                put("\(tag)_rimd0", ways[0].features.flatMap { a in b.map { abs(a.rim - $0.rim) } })
                put("\(tag)_rimd1", ways.count > 1 ? ways[1].features.flatMap { a in b.map { abs(a.rim - $0.rim) } } : nil)
                put("\(tag)_missing", Matcher.shownRim(shape).flatMap { shown in b.map { shown - $0.rim } })
                put("\(tag)_len", e.length)
                put("\(tag)_lo", e.lengths?.lowerBound ?? e.length)
                put("\(tag)_hi", e.lengths?.upperBound ?? e.length)
                put("\(tag)_dia", e.diameter)
                put("\(tag)_front", e.front)
                put("\(tag)_back", e.back)
            }
        }
        let neck = shape.neck.flatMap { $0.isClear ? $0.width : nil }
        var fields = ["\"name\":\(json(name))", "\"calibre\":\(json(calibre))", "\"part\":\(json(part == .emptyCase ? "emptyCase" : "cartridge"))",
                      "\"endView\":\(shape.isEndView)", "\"end\":\(number(Matcher.endWidth(shape)))",
                      "\"decided\":\(decided == nil ? "null" : json(decided == .emptyCase ? "emptyCase" : "cartridge"))",
                      "\"brass\":\(analysis.isBrass)", "\"L\":\(photo.size.map { number($0.length) } ?? "null")",
                      "\"D\":\(photo.size.map { number($0.diameter) } ?? "null")", "\"p\":\(photo.perspective.map(number) ?? "null")",
                      "\"mouth\":\(photo.mouth.map(number) ?? "null")", "\"neck\":\(neck.map(number) ?? "null")"]
        for key in keys.keys.sorted() { fields.append("\(json(key)):[\(keys[key]!.joined(separator: ","))]") }
        return "{\(fields.joined(separator: ","))}"
    }

    private static func number(_ v: Double) -> String { v.isFinite ? String(format: "%.5g", v) : "null" }

    private static func json(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
