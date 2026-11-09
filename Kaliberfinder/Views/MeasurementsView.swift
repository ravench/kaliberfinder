import SwiftUI

/// A calibre's catalogue measurements on a drawing of it: the diameters as horizontal dimension
/// lines with their labels in a column on the left, the lengths as vertical ones on the right.
/// The drawing is as large as fits, not at real size (that is `TrueScaleView`).
struct MeasurementsView: View {
    let cartridge: Cartridge
    @AppStorage(LengthUnit.storageKey) private var unit: LengthUnit = .metric
    /// Size of a label (name over value); grows with the text size up to xxxLarge, where the label
    /// text stops growing (`dynamicTypeSize` below): the drawing needs the room. The values in any
    /// size are on the calibre's page.
    @ScaledMetric(relativeTo: .caption) private var labelWidth = 86.0
    @ScaledMetric(relativeTo: .caption) private var labelHeight = 36.0
    private static let largestLabel = (width: 114.0, height: 54.0)

    var body: some View {
        GeometryReader { geo in
            let asked = CGSize(width: min(labelWidth, Self.largestLabel.width), height: min(labelHeight, Self.largestLabel.height))
            let layout = DimensionLayout(cartridge: cartridge, size: geo.size, label: asked)
            ZStack(alignment: .topLeading) {
                CartridgeView(cartridge: cartridge, pointsPerMM: layout.scale)
                    .offset(x: layout.origin.x, y: layout.origin.y)
                    .accessibilityHidden(true)
                Polylines(lines: layout.dimensions.map { [$0.from, $0.to] } + layout.lines)
                    .stroke(.primary, lineWidth: 0.8)
                Polylines(lines: layout.arrowheads, closed: true)
                    .fill(.primary)
                ForEach(layout.dimensions, id: \.part) { label in
                    VStack(alignment: label.trailing ? .trailing : .leading, spacing: 1) {
                        // Readable at a glance (Raven 2026-11-09): the name in full colour, the value a size larger.
                        Text(label.part.title.loc)
                            .font(.caption)
                        Text(DimensionLayout.valueText(label, unit: unit))
                            .font(.subheadline.monospacedDigit().weight(.medium))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: layout.labelSize.width, height: layout.labelSize.height, alignment: label.trailing ? .trailing : .leading)
                    .position(x: label.anchor.x + (label.trailing ? -layout.labelSize.width : layout.labelSize.width) / 2, y: label.anchor.y)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: label.part.spokenTitle.loc + " " + unit.format(label.mm)))
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding()
        .navigationTitle(Text(verbatim: cartridge.name))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Open lines, or closed ones to fill (`closed`), in points.
private struct Polylines: Shape {
    let lines: [[CGPoint]]
    var closed = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for line in lines {
            path.addLines(line)
            if closed { path.closeSubpath() }
        }
        return path
    }
}

/// Where the parts of `MeasurementsView` go, in points inside `size`: the label column, the
/// cartridge as large as fits, then the length lines and their labels; centred.
struct DimensionLayout {
    /// The measurements the detail screen lists.
    enum Part {
        case bullet, neck, shoulder, base, rim, overall, caseLength

        /// Short German name over the value, used as localization key.
        var title: String {
            switch self {
            case .bullet: "Geschoss"
            case .neck: "Hals"
            case .shoulder: "Schulter"
            case .base: "Boden"
            case .rim: "Rand"
            case .overall: "Gesamt"
            case .caseLength: "Hülse"
            }
        }

        /// The detail screen's German name, for VoiceOver; used as localization key.
        var spokenTitle: String {
            switch self {
            case .bullet: "Geschossdurchmesser"
            case .neck: "Halsdurchmesser"
            case .shoulder: "Schulterdurchmesser"
            case .base: "Bodendurchmesser"
            case .rim: "Randdurchmesser"
            case .overall: "Gesamtlänge"
            case .caseLength: "Hülsenlänge"
            }
        }

        var isDiameter: Bool { self != .overall && self != .caseLength }
    }

    /// A measurement in mm at a height of the outline (mm from the tip, as in `Cartridge.Outline`).
    struct Mark {
        let part: Part
        let mm: Double
        /// Diameters: where the drawing is that wide (the base for the rim). Lengths: their top.
        let y: Double
    }

    /// A dimension line from `from` to `to`, and its label.
    struct Dimension {
        let part: Part
        let mm: Double
        let from: CGPoint
        let to: CGPoint
        /// Middle of the label's side that faces the drawing.
        let anchor: CGPoint
        /// Diameter labels stand left of the drawing and end at `anchor`; length labels start there.
        var trailing: Bool { part.isDiameter }
    }

    /// Points per mm of the drawing.
    let scale: Double
    /// Top left corner of the outline in the view.
    let origin: CGPoint
    /// Diameters top to bottom, then the lengths, inner first.
    let dimensions: [Dimension]
    /// The labels' size: as asked, or narrower where the screen is too narrow for it and the drawing.
    let labelSize: CGSize
    /// Extension lines and the leaders from the diameter labels to their lines.
    let lines: [[CGPoint]]
    /// Filled arrowheads at both ends of each dimension line.
    let arrowheads: [[CGPoint]]

    /// Label column to drawing: room for a leader to bend to a label moved off its line.
    static let labelGap = 18.0
    /// Drawing to the first length line.
    static let lengthGap = 12.0
    /// The outer length line to the length labels.
    static let labelInset = 4.0
    /// The case length's line to the overall length's, right next to it.
    static let lengthSpacing = 12.0
    /// Base to the rim's dimension line.
    static let rimGap = 20.0
    /// Smallest scale the labels give way to, in points per mm.
    static let minScale = 3.0
    static let arrowLength = 6.0
    static let arrowWidth = 4.4
    /// Sampling step along the outline, in mm.
    static let step = 0.1

    init(cartridge c: Cartridge, size: CGSize, label: CGSize) {
        let o = c.outline
        let lengths = Self.lengths(of: c), diameters = Self.diameters(of: c)
        let n = Double(lengths.count), lh = Double(label.height)
        let gaps = Self.labelGap + Self.lengthGap + (n - 1) * Self.lengthSpacing + Self.labelInset
        // Large text: narrower labels (their text shrinks) keep the drawing at least `minScale`.
        let lw = max(0, min(Double(label.width), (Double(size.width) - gaps - Self.minScale * o.width) / 2))
        let left = lw + Self.labelGap
        let right = Self.lengthGap + (n - 1) * Self.lengthSpacing + Self.labelInset + lw
        // Half a label above the tip (a flush wadcutter's bullet is labelled there) and the rim's line below the base.
        let above = lh / 2, below = c.hasCase ? Self.rimGap + lh / 2 : 0
        let s = max(0, min((Double(size.width) - left - right) / o.width, (Double(size.height) - above - below) / o.height))
        let ox = (Double(size.width) - left - o.width * s - right) / 2 + left
        let oy = (Double(size.height) - above - o.height * s - below) / 2 + above
        let cx = ox + o.width / 2 * s, base = oy + o.height * s
        var dimensions: [Dimension] = [], lines: [[CGPoint]] = [], arrowheads: [[CGPoint]] = []

        let bounds = lh / 2...max(lh / 2, Double(size.height) - lh / 2)
        let ys = diameters.map { $0.part == .rim ? base + Self.rimGap : oy + $0.y * s }
        let labelYs = Self.spread(ys, spacing: lh, within: bounds)
        for (i, mark) in diameters.enumerated() {
            let y = ys[i], xs = [cx - mark.mm / 2 * s, cx + mark.mm / 2 * s]
            let a = CGPoint(x: xs[0], y: y), b = CGPoint(x: xs[1], y: y)
            arrowheads += [Self.arrowhead(at: a, dx: -1, dy: 0), Self.arrowhead(at: b, dx: 1, dy: 0)]
            if mark.part == .rim {
                lines += xs.map { [CGPoint(x: $0, y: base + 2), CGPoint(x: $0, y: y + 4)] }
            }
            let labelRight = ox - Self.labelGap
            lines.append([CGPoint(x: labelRight + 3, y: labelYs[i]), CGPoint(x: ox - 6, y: y), a])
            dimensions.append(Dimension(part: mark.part, mm: mark.mm, from: a, to: b, anchor: CGPoint(x: labelRight, y: labelYs[i])))
        }

        let whole = OutlineGeometry(o), empty = OutlineGeometry(o, includeBullet: false)
        let firstX = ox + o.width * s + Self.lengthGap, outerX = firstX + (n - 1) * Self.lengthSpacing
        // Both labels stand right of the outer line, each level with the middle of its own line. The
        // overall length's middle is the higher one, so reversed they run top to bottom for `spread`.
        let middles = lengths.map { (oy + $0.y * s + base) / 2 }
        let lengthYs = Array(Self.spread(middles.reversed(), spacing: lh, within: bounds).reversed())
        for (i, mark) in lengths.enumerated() {
            let x = firstX + Double(i) * Self.lengthSpacing
            let topY = oy + mark.y * s
            let top = CGPoint(x: x, y: topY), bottom = CGPoint(x: x, y: base)
            arrowheads += [Self.arrowhead(at: top, dx: 0, dy: -1), Self.arrowhead(at: bottom, dx: 0, dy: 1)]
            let edge = (mark.part == .overall ? whole : empty).width(at: mark.y + 0.01) / 2
            lines.append([CGPoint(x: cx + edge * s + 2, y: topY), CGPoint(x: x + 3, y: topY)])
            dimensions.append(Dimension(part: mark.part, mm: mark.mm, from: top, to: bottom,
                                        anchor: CGPoint(x: outerX + Self.labelInset, y: lengthYs[i])))
        }
        // The lengths share the base's extension line, out to the outer one.
        lines.append([CGPoint(x: cx + whole.width(at: o.height - 0.01) / 2 * s + 2, y: base), CGPoint(x: outerX + 3, y: base)])

        scale = s
        origin = CGPoint(x: ox, y: oy)
        labelSize = CGSize(width: lw, height: lh)
        self.dimensions = dimensions
        self.lines = lines
        self.arrowheads = arrowheads
    }

    /// "Ø 8.5 mm" for a diameter, "55.6 mm" for a length; always with a decimal, so 9 mm reads 9.0 mm.
    static func valueText(_ dimension: Dimension, unit: LengthUnit, locale: Locale = .current) -> String {
        (dimension.part.isDiameter ? "Ø " : "") + unit.format(dimension.mm, locale: locale, decimals: 1)
    }

    /// The diameters the detail screen lists, top to bottom, each where the drawing is that wide.
    static func diameters(of c: Cartridge) -> [Mark] {
        let d = c.dimensions, height = c.outline.height, mouth = height - d.caseLength
        let empty = OutlineGeometry(c.outline, includeBullet: false)
        var marks: [Mark] = []
        if c.kind != "shot" && !c.blank {
            // Just above the case mouth a bullet is still parallel; a ball, Minié bullet or pellet where it is widest.
            marks.append(Mark(part: .bullet, mm: d.bullet, y: c.hasCase ? mouth - min(1.5, 0.15 * mouth) : widest(OutlineGeometry(c.outline))))
        }
        guard c.hasCase else { return marks }
        if c.kind != "shot" {
            // Halfway down the neck, at most 1.5 mm below the mouth (a straight case narrows to the mouth).
            var neck = 0.0
            while mouth + neck + step < height, abs(empty.width(at: mouth + neck + step) - d.neck) <= 0.15 { neck += step }
            marks.append(Mark(part: .neck, mm: d.neck, y: mouth + min(1.5, neck / 2)))
        }
        if let shoulder = d.shoulder {
            // Just below where the shoulder meets the body.
            var y = mouth
            while y < height, empty.width(at: y) < shoulder - 0.15 { y += step }
            marks.append(Mark(part: .shoulder, mm: shoulder, y: y + 0.5))
        }
        let body = bodyStart(of: c, in: empty) ?? min(3.3, d.caseLength / 3)
        marks.append(Mark(part: .base, mm: d.base, y: height - body - 1))
        marks.append(Mark(part: .rim, mm: d.rim, y: height))
        return marks
    }

    /// The lengths, inner first: the case length where it differs from the overall length (not for
    /// blanks, shot shells and flush-seated wadcutters), then the overall length.
    static func lengths(of c: Cartridge) -> [Mark] {
        let d = c.dimensions
        let overall = Mark(part: .overall, mm: d.overallLength, y: 0)
        guard c.hasCase, d.caseLength < d.overallLength - 0.05 else { return [overall] }
        return [Mark(part: .caseLength, mm: d.caseLength, y: c.outline.height - d.caseLength), overall]
    }

    /// Height above the base (mm) where the body starts in front of the rim, extractor groove or belt:
    /// going up from the base, the first place where the case comes to the base diameter after being
    /// wider or narrower, and stays there for 1 mm (a belt's ramp only crosses it). Nil if none.
    static func bodyStart(of c: Cartridge, in empty: OutlineGeometry) -> Double? {
        let d = c.dimensions, height = c.outline.height
        // Above a belt the body is drawn 1.5 % narrower than the base diameter (calibre-data outline.py).
        let tolerance = max(0.25, 0.02 * d.base)
        func atBase(_ t: Double) -> Bool { abs(empty.width(at: height - t) - d.base) <= tolerance }
        var below = atBase(0.01)
        for t in stride(from: step, to: min(d.caseLength, 20), by: step) {
            let here = atBase(t)
            if here, !below, stride(from: t, to: t + 1, by: step).allSatisfy(atBase) { return t }
            below = here
        }
        return nil
    }

    /// Height of the middle of the widest stretch of a drawing: the equator of a ball, the band of a
    /// Minié bullet, the head of a pellet.
    static func widest(_ g: OutlineGeometry) -> Double {
        let ys = Array(stride(from: 0, through: g.height, by: step))
        let widths = ys.map(g.width(at:))
        let most = widths.max() ?? 0
        var best = (start: 0, end: -1), start = 0
        for i in ys.indices {
            if widths[i] < most - 0.02 {
                start = i + 1
            } else if i - start > best.end - best.start {
                best = (start, i)
            }
        }
        return ys[(best.start + best.end) / 2]
    }

    /// Moves label centres `ys` (top to bottom) apart until they are `spacing` apart, inside `bounds`
    /// where there is room.
    static func spread(_ ys: [Double], spacing: Double, within bounds: ClosedRange<Double>) -> [Double] {
        var result = ys
        for i in result.indices {
            result[i] = max(result[i], i == 0 ? bounds.lowerBound : result[i - 1] + spacing)
        }
        for i in result.indices.reversed() {
            result[i] = min(result[i], i == result.count - 1 ? bounds.upperBound : result[i + 1] - spacing)
        }
        return result
    }

    /// A filled arrowhead with its tip at `tip`, pointing along (`dx`, `dy`).
    static func arrowhead(at tip: CGPoint, dx: Double, dy: Double) -> [CGPoint] {
        let bx = Double(tip.x) - dx * arrowLength, by = Double(tip.y) - dy * arrowLength, w = arrowWidth / 2
        return [tip, CGPoint(x: bx - dy * w, y: by + dx * w), CGPoint(x: bx + dy * w, y: by - dx * w)]
    }
}
