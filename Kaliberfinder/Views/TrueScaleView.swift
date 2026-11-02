import SwiftUI

extension VerticalAlignment {
    private enum CartridgeBase: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[.bottom] }
    }

    /// The base line all cartridges (and the ruler's zero) stand on.
    static let cartridgeBase = VerticalAlignment(CartridgeBase.self)
}

/// Cartridges side by side at real size, standing on a common base line next to a millimetre ruler.
/// Lay the real cartridge on the screen, base on the line, to compare.
struct TrueScaleView: View {
    let cartridges: [Cartridge]
    @EnvironmentObject private var scale: ScaleModel

    var body: some View {
        let ppmm = scale.pointsPerMM
        let tallest = cartridges.map(\.outline.height).max() ?? 0
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 12) {
                if scale.resolution.source == .estimate {
                    Label("Bildschirm nicht kalibriert: Grösse kann leicht abweichen.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                HStack(alignment: .cartridgeBase, spacing: 8 * ppmm) {
                    RulerView(lengthMM: ceil((tallest + 5) / 10) * 10, pointsPerMM: ppmm)
                        .alignmentGuide(.cartridgeBase) { $0[.bottom] }
                    ForEach(cartridges) { c in
                        VStack(spacing: 6) {
                            CartridgeView(cartridge: c, pointsPerMM: ppmm)
                                .alignmentGuide(.cartridgeBase) { $0[.bottom] }
                            label(for: c)
                            CaseBaseView(cartridge: c, pointsPerMM: ppmm)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("1:1")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(for c: Cartridge) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: c.name).font(.caption.bold())
            Text(verbatim: "L \(mm(c.dimensions.overallLength))").font(.caption2)
            Text(verbatim: "Ø \(mm(max(c.dimensions.rim, c.dimensions.base)))").font(.caption2)
        }
        .multilineTextAlignment(.center)
        .frame(width: max(70, c.outline.width * scale.pointsPerMM))
        .foregroundStyle(.secondary)
    }
}

/// A vertical millimetre ruler, zero at the bottom: ticks every mm, longer every 5, numbers every 10.
struct RulerView: View {
    let lengthMM: Double
    let pointsPerMM: Double

    var body: some View {
        Canvas { context, size in
            let total = Int(lengthMM)
            for i in 0...total {
                let y = size.height - Double(i) * pointsPerMM
                let tick: Double = i % 10 == 0 ? 14 : (i % 5 == 0 ? 9 : 5)
                var line = Path()
                line.move(to: CGPoint(x: size.width - tick, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.primary), lineWidth: 0.5)
                if i % 10 == 0 {
                    let text = Text(verbatim: "\(i / 10)").font(.system(size: 9)).foregroundStyle(.secondary)
                    context.draw(text, at: CGPoint(x: size.width - 22, y: y), anchor: .center)
                }
            }
            var axis = Path()
            axis.move(to: CGPoint(x: size.width, y: 0))
            axis.addLine(to: CGPoint(x: size.width, y: size.height))
            context.stroke(axis, with: .color(.primary), lineWidth: 0.5)
        }
        .frame(width: 32, height: lengthMM * pointsPerMM)
        .accessibilityLabel("Lineal in Zentimetern")
    }
}
