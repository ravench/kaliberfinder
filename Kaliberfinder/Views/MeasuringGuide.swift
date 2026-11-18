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

    static let box = CGRect(x: 30, y: 4, width: 615, height: 208)
    /// The box without the head view, up to the OAL line's end.
    static let sideBox = CGRect(x: 30, y: 4, width: 490, height: 208)
    /// The head view shows only with a letter on it: the dimensions form has no field there (TestFlight 2026-11-17),
    /// so its sketch is the side view alone, drawn that much wider.
    var showsHead: Bool { letters?.contains("P") ?? true }
    var box: CGRect { showsHead ? Self.box : Self.sideBox }
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
        // Lengths from the head, below; H ends where the shoulder starts.
        Mark(letter: "H", from: pt(40, 156), to: pt(286, 156), label: pt(163, 151)),
        Mark(letter: "L", from: pt(40, 180), to: pt(362.2, 180), label: pt(201, 175)),
        Mark(letter: "OAL", from: pt(40, 204), to: pt(503.2, 204), label: pt(272, 199)),
    ]

    /// The dimension lines and a slash at each of their ends.
    static func dimensionLines(_ marks: [Mark]) -> [[CGPoint]] {
        let ends: [CGPoint] = marks.flatMap { [$0.from, $0.to] }
        let ticks: [[CGPoint]] = ends.map { end in [pt(end.x - 3, end.y + 3), pt(end.x + 3, end.y - 3)] }
        return marks.map { [$0.from, $0.to] } + ticks
    }

    /// From the drawing to the letters above and to the length lines below, each with the letters it serves:
    /// the line down the head is shared by the three lengths.
    static let extensions: [(letters: [String], line: [CGPoint])] = [
        (["R"], [pt(44.8, 52), pt(44.8, 30)]), (["B"], [pt(84, 58), pt(84, 30)]), (["S"], [pt(276, 60), pt(276, 30)]),
        (["N"], [pt(340, 69), pt(340, 30)]), (["D"], [pt(380, 71), pt(380, 30)]), (["P"], [pt(594, 80), pt(594, 30)]),
        (["H", "L", "OAL"], [pt(40, 142), pt(40, 208)]), (["H"], [pt(286, 134), pt(286, 160)]),
        (["L"], [pt(362.2, 124), pt(362.2, 184)]), (["OAL"], [pt(503.2, 100), pt(503.2, 208)]),
    ]

    /// The round's axis.
    static let axis = 96.0
    /// A straight case's bullet nearly fills its mouth; a bottleneck's sits in the narrower neck.
    var bulletRadius: Double { shape == .straight ? 31 : 23.7 }
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
    static let beltMark = Mark(letter: "G", from: pt(69, axis - belt.radius), to: pt(69, axis + belt.radius), label: pt(69, 26))

    /// The marks to draw, the rim's and the bullet's as wide as this round's.
    var shownMarks: [Mark] {
        let marks = Self.marks.filter { letters?.contains($0.letter) ?? true }.map { mark in
            switch mark.letter {
            case "R": Mark(letter: "R", from: pt(44.8, Self.axis - rimRadius), to: pt(44.8, Self.axis + rimRadius), label: mark.label)
            case "D": Mark(letter: "D", from: pt(380, Self.axis - bulletRadius), to: pt(380, Self.axis + bulletRadius), label: mark.label)
            default: mark
            }
        }
        return head == .belted ? marks + [Self.beltMark] : marks
    }
    var shownExtensions: [[CGPoint]] {
        let tops = ["R": Self.axis - rimRadius - 0.8, "D": Self.axis - bulletRadius - 1.3]
        let lines = Self.extensions.filter { ext in letters.map { !$0.isDisjoint(with: ext.letters) } ?? true }.map { ext in
            ext.letters.first.flatMap { tops[$0] }.map { [pt(ext.line[0].x, $0), ext.line[1]] } ?? ext.line
        }
        return head == .belted ? lines + [[pt(69, Self.axis - Self.belt.radius - 1), pt(69, 30)]] : lines
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
