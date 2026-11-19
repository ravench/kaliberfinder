import SwiftUI

/// Where the calliper values of a training series are taken, as on the «Where to measure» drawing of
/// the old-ammunition page (Raven 2026-11-10): a rimmed bottleneck round from the side and from its
/// head, each measurement marked with the letter its field carries. The same sketch for every calibre,
/// drawn in the units of `box` and scaled to the width it gets. The dimensions form shows the same sketch
/// with the letters of its fields only (TestFlight 2026-11-16), and its outline as the form's shape and head
/// choices say (TestFlight 2026-11-17): the default is the rimmed bottleneck round.
struct MeasuringGuide: View {
    /// The letters to draw, with their lines; nil draws them all.
    var letters: Set<String>?
    var shape: CaseShape = .any
    var head: RimKind = .any

    /// A dimension line from `from` to `to`, its letter centred on `label` (the baseline).
    struct Mark {
        let letter: String
        let from: CGPoint
        let to: CGPoint
        let label: CGPoint
    }

    /// The box with every length's row.
    static let box = CGRect(x: 30, y: 4, width: 615, height: 232)
    /// The box without the head view, up to the OAL line's end.
    static let sideBox = CGRect(x: 30, y: 4, width: 490, height: 232)
    /// The head view shows only with a letter on it: the dimensions form has no field there (TestFlight 2026-11-17),
    /// so its sketch is the side view alone, drawn that much wider.
    var showsHead: Bool { letters?.contains("P") ?? true }
    /// As wide as the views shown, down to the last length's row: a sketch without a length has no empty row for it.
    var box: CGRect {
        let full = showsHead ? Self.box : Self.sideBox
        return CGRect(x: full.minX, y: full.minY, width: full.width, height: (rows.values.max() ?? Self.firstRow) + 8 - full.minY)
    }

    /// The lengths in the order taken, each on a row of its own below the drawing (Raven 2026-11-19).
    static let lengths = ["E", "H", "L", "OAL"]
    static let firstRow = 156.0, rowStep = 24.0
    /// The row of each length shown, from the first row down, with no gaps (review 2026-11-19).
    var rows: [String: Double] {
        let shown = Self.lengths.filter { letters?.contains($0) ?? true }
        return Dictionary(uniqueKeysWithValues: shown.enumerated().map { ($1, Self.firstRow + Self.rowStep * Double($0)) })
    }
    /// Height of the letters.
    static let letterSize = 22.0

    static let marks: [Mark] = [
        // Diameters across the side view, the primer's across the head; their letters above.
        Mark(letter: "R", from: pt(44.8, 52.8), to: pt(44.8, 139.2), label: pt(44.8, 26)),
        Mark(letter: "B", from: pt(84, 59.2), to: pt(84, 132.8), label: pt(84, 26)),
        Mark(letter: "S", from: pt(276, 61.2), to: pt(276, 130.8), label: pt(276, 26)),
        Mark(letter: "N", from: pt(340, 70.5), to: pt(340, 121.5), label: pt(340, 26)),
        Mark(letter: "D", from: pt(380, 72.3), to: pt(380, 119.7), label: pt(380, 26)),
        Mark(letter: "P", from: pt(578, 96), to: pt(610, 96), label: pt(594, 26)),
        // Lengths from the head, below, on their rows (`rows`; here all shown): the rim's thickness first, its letter
        // beside the short line, clear of a belt's G above; H ends where the shoulder starts.
        Mark(letter: "E", from: pt(40, 156), to: pt(49.6, 156), label: pt(76, 161)),
        Mark(letter: "H", from: pt(40, 180), to: pt(286, 180), label: pt(163, 175)),
        Mark(letter: "L", from: pt(40, 204), to: pt(362.2, 204), label: pt(201, 199)),
        Mark(letter: "OAL", from: pt(40, 228), to: pt(503.2, 228), label: pt(272, 223)),
        // The paper patch in front of the case mouth, under the bullet: above it the line would sit under D's letter
        // (review 2026-11-19). Its letter beyond the line's end.
        Mark(letter: "PP", from: pt(362.2, 150), to: pt(430, 150), label: pt(458, 155)),
    ]

    /// The dimension lines and a slash at each of their ends.
    static func dimensionLines(_ marks: [Mark]) -> [[CGPoint]] {
        let ends: [CGPoint] = marks.flatMap { [$0.from, $0.to] }
        let ticks: [[CGPoint]] = ends.map { end in [pt(end.x - 3, end.y + 3), pt(end.x + 3, end.y - 3)] }
        return marks.map { [$0.from, $0.to] } + ticks
    }

    /// From the drawing to the letters above and to the length lines below, each with the letters it serves:
    /// the line down the head is shared by the lengths, the mouth's by the case and the patch. Drawn for the
    /// default round with every length shown; `shownExtensions` fits them to this one.
    static let extensions: [(letters: [String], line: [CGPoint])] = [
        (["R"], [pt(44.8, 52), pt(44.8, 30)]), (["B"], [pt(84, 58), pt(84, 30)]), (["S"], [pt(276, 60), pt(276, 30)]),
        (["N"], [pt(340, 69), pt(340, 30)]), (["D"], [pt(380, 71), pt(380, 30)]), (["P"], [pt(594, 80), pt(594, 30)]),
        (headLine, [pt(40, 140), pt(40, 232)]), (["E"], [pt(49.6, 140), pt(49.6, 160)]),
        (["H"], [pt(286, 134), pt(286, 184)]), (["L", "PP"], [pt(362.2, 124), pt(362.2, 208)]),
        (["OAL"], [pt(503.2, 100), pt(503.2, 232)]), (["PP"], [pt(430, 119), pt(430, 154)]),
    ]
    static let headLine = ["E", "H", "L", "OAL"]
    /// The nose's half-width where the patch ends (x 430), as a share of the bullet's radius: the curve of `bullet`
    /// there (t 0.268).
    static let patchEndShare = 0.902

    /// The round's axis.
    static let axis = 96.0
    /// A straight case's bullet nearly fills its mouth; a bottleneck's sits in the narrower neck.
    var bulletRadius: Double { shape == .straight ? 31 : 23.7 }
    /// The neck is the mouth of a straight case, nearly the body; a bottleneck's is narrower.
    var neckRadius: Double { shape == .straight ? 34.3 : 25.5 }
    /// A rim stands over the body (37.1 behind it), a semi-rim a little; a rimless or belted case's is the body's.
    var rimRadius: Double {
        switch head {
        case .any, .rimmed: 43.2
        case .semiRimmed: 39.5
        case .rimless, .belted: 37.1
        }
    }
    /// The belt behind the extractor groove, with its own mark for the form's belt field.
    static let belt = (from: 58.0, to: 80.0, radius: 40.0)
    /// Its mark sits left of centre, clear of the training sketch's B beside it.
    static let beltMark = Mark(letter: "G", from: pt(66, axis - belt.radius), to: pt(66, axis + belt.radius), label: pt(66, 26))

    /// The marks to draw, the rim's and the bullet's as wide as this round's, the lengths on their rows.
    var shownMarks: [Mark] {
        let rows = rows
        let marks: [Mark] = Self.marks.filter { letters?.contains($0.letter) ?? true }.map { mark -> Mark in
            if let row = rows[mark.letter] {
                let dy = row - mark.from.y
                return Mark(letter: mark.letter, from: pt(mark.from.x, row), to: pt(mark.to.x, row), label: pt(mark.label.x, mark.label.y + dy))
            }
            return switch mark.letter {
            case "R": Mark(letter: "R", from: pt(44.8, Self.axis - rimRadius), to: pt(44.8, Self.axis + rimRadius), label: mark.label)
            case "D": Mark(letter: "D", from: pt(380, Self.axis - bulletRadius), to: pt(380, Self.axis + bulletRadius), label: mark.label)
            case "N": Mark(letter: "N", from: pt(340, Self.axis - neckRadius), to: pt(340, Self.axis + neckRadius), label: mark.label)
            default: mark
            }
        }
        return head == .belted ? marks + [Self.beltMark] : marks
    }
    var shownExtensions: [[CGPoint]] {
        let rows = rows
        let lines: [[CGPoint]] = Self.extensions.filter { ext in letters.map { !$0.isDisjoint(with: ext.letters) } ?? true }.map { ext -> [CGPoint] in
            let x = ext.line[0].x
            // Down to the lowest length row it serves, as this sketch's rows lie.
            let end = ext.letters.compactMap { rows[$0] }.max().map { $0 + 4 } ?? ext.line[1].y
            return [pt(x, start(ext.letters) ?? ext.line[0].y), pt(x, end)]
        }
        return head == .belted ? lines + [[pt(66, Self.axis - Self.belt.radius - 1), pt(66, 30)]] : lines
    }

    /// Where a line leaves the drawing, as wide as this round: above the rim, bullet and neck; below the rim for its
    /// thickness and the lengths, below the mouth for the case and the patch, below the nose where the patch ends.
    private func start(_ letters: [String]) -> Double? {
        switch letters {
        case ["R"]: Self.axis - rimRadius - 0.8
        case ["D"]: Self.axis - bulletRadius - 1.3
        case ["N"]: Self.axis - neckRadius - 1.5
        case ["E"], Self.headLine: Self.axis + rimRadius + 0.8
        case ["L", "PP"]: Self.axis + neckRadius + 2.5
        case ["PP"]: Self.axis + Self.patchEndShare * bulletRadius + 1.3
        default: nil
        }
    }

    /// The case from the side: the rim, a groove and belt where the head has them, the body tapering to the
    /// mouth, over a shoulder for a bottleneck. The upper edge, mirrored below the axis.
    var caseOutline: Path {
        var top = [pt(40, Self.axis - rimRadius), pt(49.6, Self.axis - rimRadius)]
        var body = 49.6
        if ![.any, .rimmed].contains(head) {  // the extractor groove behind the rim
            top += [pt(49.6, 65), pt(58, 65)]
            body = 58
            if head == .belted {
                top += [pt(Self.belt.from, Self.axis - Self.belt.radius), pt(Self.belt.to, Self.axis - Self.belt.radius)]
                body = Self.belt.to
            }
        }
        top.append(pt(body, 58.9))
        top += shape == .straight ? [pt(362.2, 61.9)] : [pt(286, 61.2), pt(310, 70.5), pt(362.2, 70.5)]
        return Path { p in
            p.addLines(top + top.reversed().map { pt($0.x, 2 * Self.axis - $0.y) })
            p.closeSubpath()
        }
    }

    var bullet: Path {
        let r = bulletRadius, a = Self.axis
        return Path { p in
            p.move(to: pt(356, a - r))
            p.addLine(to: pt(392, a - r))
            p.addCurve(to: pt(503.2, a), control1: pt(440, a - r), control2: pt(488, a - r / 2))
            p.addCurve(to: pt(392, a + r), control1: pt(488, a + r / 2), control2: pt(440, a + r))
            p.addLine(to: pt(356, a + r))
            p.closeSubpath()
        }
    }

    var body: some View {
        Canvas { context, size in
            let s = size.width / box.width
            context.scaleBy(x: s, y: s)
            context.translateBy(x: -box.minX, y: -box.minY)
            let ink = GraphicsContext.Shading.style(.primary)
            let head = CGPoint(x: 594, y: 96)
            func circle(_ r: Double) -> Path {
                Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: 2 * r, height: 2 * r))
            }
            var fills: [(Path, Color)] = [(bullet, CartridgeView.copper), (caseOutline, CartridgeView.brass)]
            if showsHead { fills += [(circle(43.2), CartridgeView.brass), (circle(16), CartridgeView.copper)] }
            for (shape, fill) in fills {
                context.fill(shape, with: .color(fill))
                context.stroke(shape, with: ink, lineWidth: 1.4)
            }
            // The body's edge, behind the rim.
            if showsHead { context.stroke(circle(37.1), with: ink, style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
            context.stroke(Self.lines(shownExtensions), with: .style(.secondary), lineWidth: 1)
            context.stroke(Self.lines(Self.dimensionLines(shownMarks)), with: ink, lineWidth: 1.3)
            for mark in shownMarks {
                // `label` is the letter's baseline, as in the page's SVG.
                let text: Text = Text(verbatim: mark.letter).font(.system(size: Self.letterSize, weight: .bold)).foregroundStyle(Color.accentColor)
                let letter: GraphicsContext.ResolvedText = context.resolve(text)
                let baseline: CGFloat = letter.firstBaseline(in: letter.measure(in: CGSize(width: 1000, height: 1000)))
                context.draw(letter, at: CGPoint(x: mark.label.x, y: mark.label.y - baseline), anchor: .top)
            }
        }
        .aspectRatio(box.width / box.height, contentMode: .fit)
        .accessibilityHidden(true)  // the fields carry the names
    }

    private static func lines(_ lines: [[CGPoint]]) -> Path {
        Path { p in lines.forEach { p.addLines($0) } }
    }
}

private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
