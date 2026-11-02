import SwiftUI

/// Sizes for the 1:1 screen, in points. The ruler and the cartridges share one base line:
/// both sit in a band as tall as the ruler, cartridges standing on its bottom edge.
struct TrueScaleLayout: Equatable {
    /// Ruler length in mm (whole cm or inch, at least the tallest cartridge plus 5 mm).
    let rulerMM: Double
    /// Height of the band above the base line, in points.
    let bandHeight: Double

    init(cartridges: [Cartridge], unit: LengthUnit, pointsPerMM: Double) {
        let tallest = cartridges.map(\.outline.height).max() ?? 0
        rulerMM = unit.rulerLength(tallestMM: tallest)
        bandHeight = rulerMM * pointsPerMM
    }
}

/// Cartridges side by side at real size, standing on a common base line next to a ruler.
/// The ruler stays put on the left while the cartridges scroll sideways; zooming is
/// deliberately not possible, since the drawing is at real size (1:1).
/// Lay the real cartridge on the screen, base on the line, to compare.
struct TrueScaleView: View {
    let cartridges: [Cartridge]
    @EnvironmentObject private var scale: ScaleModel
    @AppStorage(LengthUnit.storageKey) private var unit: LengthUnit = .metric
    @State private var showZoomHint = false

    var body: some View {
        let ppmm = scale.pointsPerMM
        let layout = TrueScaleLayout(cartridges: cartridges, unit: unit, pointsPerMM: ppmm)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                OneToOneBadge()
                if scale.resolution.source == .estimate {
                    Label("Bildschirm nicht kalibriert: Grösse kann leicht abweichen.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                HStack(alignment: .top, spacing: 0) {
                    // Outside the horizontal scroll view, so it stays on screen.
                    RulerView(lengthMM: layout.rulerMM, pointsPerMM: ppmm, unit: unit)
                        .frame(height: layout.bandHeight, alignment: .bottom)
                        .padding(.trailing, 4)
                        .background(Color(.systemBackground))
                        .zIndex(1)
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 8 * ppmm) {
                            ForEach(cartridges) { c in
                                VStack(spacing: 6) {
                                    CartridgeView(cartridge: c, pointsPerMM: ppmm)
                                        .frame(height: layout.bandHeight, alignment: .bottom)
                                    label(for: c)
                                    CaseBaseView(cartridge: c, pointsPerMM: ppmm)
                                }
                            }
                        }
                        .padding(.horizontal, 8 * ppmm)
                        .overlay(alignment: .topLeading) {
                            // The base line the cartridges stand on, continuing the ruler's zero.
                            Rectangle()
                                .fill(Color.primary.opacity(0.35))
                                .frame(height: 0.5)
                                .offset(y: layout.bandHeight)
                        }
                    }
                    .scrollIndicators(.visible)
                }
            }
            .padding()
        }
        .simultaneousGesture(MagnifyGesture().onChanged { _ in showZoomHint = true })
        .overlay(alignment: .bottom) {
            if showZoomHint {
                Label("1:1 – Zoomen ist abgeschaltet, damit die Grösse stimmt.", systemImage: "lock")
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { showZoomHint = false }
                    }
            }
        }
        .animation(.default, value: showZoomHint)
        .navigationTitle("1:1")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(for c: Cartridge) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: c.name).font(.caption.bold())
            Text(verbatim: "L \(unit.format(c.dimensions.overallLength))").font(.caption2)
            Text(verbatim: "Ø \(unit.format(max(c.dimensions.rim, c.dimensions.base)))").font(.caption2)
        }
        .multilineTextAlignment(.center)
        .frame(width: max(70, c.outline.width * scale.pointsPerMM))
        .foregroundStyle(.secondary)
    }
}

/// Says that the drawing is at real size, which is why it can't be zoomed.
struct OneToOneBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: "1:1")
                .font(.caption.weight(.heavy).monospacedDigit())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white)
            Text("Originalgrösse: nicht zoombar, damit die Masse stimmen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A vertical ruler, zero at the bottom: centimetres or inches (see `LengthUnit.rulerTicks`).
struct RulerView: View {
    let lengthMM: Double
    let pointsPerMM: Double
    var unit: LengthUnit = .metric

    /// Tick length in points by level.
    private static let tickLengths: [Double] = [4, 6, 9, 11, 14]

    var body: some View {
        Canvas { context, size in
            for tick in unit.rulerTicks(lengthMM: lengthMM) {
                let y = size.height - tick.mm * pointsPerMM
                let length = Self.tickLengths[min(max(tick.level, 0), Self.tickLengths.count - 1)]
                var line = Path()
                line.move(to: CGPoint(x: size.width - length, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.primary), lineWidth: 0.5)
                if let label = tick.label {
                    let text = Text(verbatim: label).font(.system(size: 9)).foregroundStyle(.secondary)
                    context.draw(text, at: CGPoint(x: size.width - 22, y: y), anchor: .center)
                }
            }
            var axis = Path()
            axis.move(to: CGPoint(x: size.width, y: 0))
            axis.addLine(to: CGPoint(x: size.width, y: size.height))
            context.stroke(axis, with: .color(.primary), lineWidth: 0.5)
        }
        .frame(width: 32, height: lengthMM * pointsPerMM)
        .accessibilityLabel(unit == .metric ? "Lineal in Zentimetern".loc : "Lineal in Zoll".loc)
    }
}
