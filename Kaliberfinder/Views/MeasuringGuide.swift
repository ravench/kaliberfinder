import SwiftUI

/// Where the calliper values of a training series are taken, as on the «Where to measure» drawing of
/// the old-ammunition page (Raven 2026-11-10): a rimmed bottleneck round from the side and from its
/// head, each measurement marked with the letter its field carries. The same sketch for every calibre,
/// drawn in the units of `box` and scaled to the width it gets.
struct MeasuringGuide: View {
    /// A dimension line from `from` to `to`, its letter centred above `label`.
    struct Mark {
        let letter: String
        let from: CGPoint
        let to: CGPoint
        let label: CGPoint
    }

    static let box = CGRect(x: 30, y: 4, width: 615, height: 208)
    /// Height of the letters.
    static let letterSize = 22.0

    static let marks = [
        // Diameters across the side view, the primer's across the head; their letters above.
        Mark(letter: "R", from: pt(44.8, 52.8), to: pt(44.8, 139.2), label: pt(44.8, 26)),
        Mark(letter: "B", from: pt(84, 59.2), to: pt(84, 132.8), label: pt(84, 26)),
        Mark(letter: "S", from: pt(276, 61.2), to: pt(276, 130.8), label: pt(276, 26)),
        Mark(letter: "D", from: pt(380, 72.3), to: pt(380, 119.7), label: pt(380, 26)),
        Mark(letter: "P", from: pt(578, 96), to: pt(610, 96), label: pt(594, 26)),
        // Lengths from the head, below; H ends where the shoulder starts.
        Mark(letter: "H", from: pt(40, 156), to: pt(286, 156), label: pt(163, 151)),
        Mark(letter: "L", from: pt(40, 180), to: pt(362.2, 180), label: pt(201, 175)),
        Mark(letter: "OAL", from: pt(40, 204), to: pt(503.2, 204), label: pt(272, 199)),
    ]

    /// From the drawing to the letters above and to the length lines below.
    static let extensions = [
        [pt(44.8, 52), pt(44.8, 30)], [pt(84, 58), pt(84, 30)], [pt(276, 60), pt(276, 30)],
        [pt(380, 71), pt(380, 30)], [pt(594, 80), pt(594, 30)],
        [pt(40, 142), pt(40, 208)], [pt(286, 134), pt(286, 160)],
        [pt(362.2, 124), pt(362.2, 184)], [pt(503.2, 100), pt(503.2, 208)],
    ]

    static let caseOutline = Path { p in
        p.addLines([pt(40, 52.8), pt(49.6, 52.8), pt(49.6, 58.9), pt(286, 61.2), pt(310, 70.5),
                    pt(362.2, 70.5), pt(362.2, 121.5), pt(310, 121.5), pt(286, 130.8),
                    pt(49.6, 133.1), pt(49.6, 139.2), pt(40, 139.2)])
        p.closeSubpath()
    }

    static let bullet = Path { p in
        p.move(to: pt(356, 72.3))
        p.addLine(to: pt(392, 72.3))
        p.addCurve(to: pt(503.2, 96), control1: pt(440, 72.3), control2: pt(488, 84))
        p.addCurve(to: pt(392, 119.7), control1: pt(488, 108), control2: pt(440, 119.7))
        p.addLine(to: pt(356, 119.7))
        p.closeSubpath()
    }

    var body: some View {
        Canvas { context, size in
            let s = size.width / Self.box.width
            context.scaleBy(x: s, y: s)
            context.translateBy(x: -Self.box.minX, y: -Self.box.minY)
            let ink = GraphicsContext.Shading.style(.primary)
            let head = CGPoint(x: 594, y: 96)
            func circle(_ r: Double) -> Path {
                Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: 2 * r, height: 2 * r))
            }
            for (shape, fill) in [(Self.bullet, CartridgeView.copper), (Self.caseOutline, CartridgeView.brass),
                                  (circle(43.2), CartridgeView.brass), (circle(16), CartridgeView.copper)] {
                context.fill(shape, with: .color(fill))
                context.stroke(shape, with: ink, lineWidth: 1.4)
            }
            // The body's edge, behind the rim.
            context.stroke(circle(37.1), with: ink, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            context.stroke(Self.lines(Self.extensions), with: .style(.secondary), lineWidth: 1)
            // Dimension lines with a slash at each end.
            let ticks = Self.marks.flatMap { [$0.from, $0.to] }.map { [CGPoint(x: $0.x - 3, y: $0.y + 3), CGPoint(x: $0.x + 3, y: $0.y - 3)] }
            context.stroke(Self.lines(Self.marks.map { [$0.from, $0.to] } + ticks), with: ink, lineWidth: 1.3)
            for mark in Self.marks {
                let letter = Text(verbatim: mark.letter).font(.system(size: Self.letterSize, weight: .bold)).foregroundStyle(Color.accentColor)
                context.draw(letter, at: mark.label, anchor: .bottom)
            }
        }
        .aspectRatio(Self.box.width / Self.box.height, contentMode: .fit)
        .accessibilityHidden(true)  // the fields carry the names
    }

    private static func lines(_ lines: [[CGPoint]]) -> Path {
        Path { p in lines.forEach { p.addLines($0) } }
    }
}

private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
