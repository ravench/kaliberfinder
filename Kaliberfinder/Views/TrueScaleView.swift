import SwiftUI

/// Sizes for the 1:1 screen, in points. The ruler and the cartridges share one base line:
/// both sit in a band as tall as the ruler, cartridges standing on its bottom edge.
struct TrueScaleLayout: Equatable {
    /// Ruler length in mm (whole cm or inch, at least the tallest cartridge plus 5 mm).
    let rulerMM: Double
    /// Height of the band above the base line, in points.
    let bandHeight: Double
    /// The ruler sits flush against the left edge of the screen.
    static let rulerLeadingInset = 0.0
    /// Ruler width plus its gap to the scrolling cartridges.
    static let rulerWidth = RulerView.width + 4
    /// With a single cartridge: space between the ruler and the cartridge, in mm.
    static let singleGapMM = 8.0

    /// With a single cartridge, the ruler and cartridge form one group, shifted by this many points
    /// so that the cartridge itself (not the group) is centred on screen.
    static func singleOffset(pointsPerMM: Double) -> Double {
        -(rulerWidth + singleGapMM * pointsPerMM) / 2
    }

    init(cartridges: [Cartridge], unit: LengthUnit, pointsPerMM: Double) {
        let tallest = cartridges.map(\.outline.height).max() ?? 0
        rulerMM = unit.rulerLength(tallestMM: tallest)
        bandHeight = rulerMM * pointsPerMM
    }

    /// Where the drawings (the band with the labels under it, `contentHeight` tall) start in the
    /// `availableHeight` under the badge. When they fit, they are centred: as much space above the
    /// bullet tips as below the labels. When they do not, their bottom is on the bottom edge and the
    /// start is negative: the bullet tips are cut off at the top, not the bases and the labels; the
    /// screen does not scroll vertically.
    static func contentTop(contentHeight: Double, availableHeight: Double) -> Double {
        contentHeight <= availableHeight ? (availableHeight - contentHeight) / 2 : availableHeight - contentHeight
    }
}

/// Gives its content the whole space and puts it where `TrueScaleLayout.contentTop` says: centred
/// when it fits, else flush with the bottom edge, sticking out at the top.
private struct CentredOrFlushBottom: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            let top = TrueScaleLayout.contentTop(contentHeight: height, availableHeight: bounds.height)
            subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY + top), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: height))
        }
    }
}

/// Cartridges side by side at real size, standing on a common base line next to a ruler.
/// The ruler stays put on the left while the cartridges scroll sideways; zooming is
/// deliberately not possible, since the drawing is at real size (1:1). The band is centred
/// vertically when it fits under the badge, else it stands on the bottom edge and the bullet
/// tips are cut off at the top (`TrueScaleLayout.contentTop`); there is no vertical scrolling.
/// Lay the real cartridge on the screen, base on the line, to compare.
struct TrueScaleView: View {
    let cartridges: [Cartridge]
    /// Calibres a photo was compared with as empty cases: their labels add the case length, and
    /// their drawings leave out the bullet when «Geschosse beim Vergleich mit leeren Hülsen zeigen» is off;
    /// then «L» is the case length.
    var emptyCases: Set<String> = []
    /// Why a photo's matches that fit well are listed, by calibre id (`MatchesView.goodMatches`): shown in green under the name.
    var goodMatches: [String: String] = [:]
    @EnvironmentObject private var scale: ScaleModel
    @AppStorage(LengthUnit.storageKey) private var unit: LengthUnit = .metric
    @AppStorage(Self.bulletsOnCasesKey) private var bulletsOnCases = true
    @State private var showZoomHint = false

    /// Settings switch, on by default: empty cases are compared with the bullet drawn.
    static let bulletsOnCasesKey = "showBulletsOnEmptyCases"

    /// E.g. "Hülse 51.2 mm", under each calibre compared as an empty case with its bullet drawn.
    static func caseLengthText(_ c: Cartridge, unit: LengthUnit) -> String {
        String(format: "Hülse %@".loc, unit.format(c.dimensions.caseLength))
    }

    /// "L …": the length of what is drawn, the case alone when `caseOnly`, else the whole cartridge.
    static func lengthText(_ c: Cartridge, caseOnly: Bool, unit: LengthUnit) -> String {
        "L " + unit.format(caseOnly ? c.dimensions.caseLength : c.dimensions.overallLength)
    }

    var body: some View {
        let ppmm = scale.pointsPerMM
        let layout = TrueScaleLayout(cartridges: cartridges, unit: unit, pointsPerMM: ppmm)
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                OneToOneBadge()
                if scale.resolution.source == .estimate {
                    Label("Bildschirm nicht kalibriert: Grösse kann leicht abweichen.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .padding([.horizontal, .top])
            CentredOrFlushBottom {
                if let single = cartridges.first, cartridges.count == 1 {
                    singleView(single, layout: layout, ppmm: ppmm)
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        // Outside the horizontal scroll view, so it stays on screen, flush with the
                        // left edge and with its zero on the cartridges' base line.
                        RulerView(lengthMM: layout.rulerMM, pointsPerMM: ppmm, unit: unit)
                            .frame(height: layout.bandHeight, alignment: .bottom)
                            .padding(.trailing, 4)
                            .background(Color(.systemBackground))
                            .zIndex(1)
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 8 * ppmm) {
                                ForEach(cartridges) { c in
                                    VStack(spacing: 6) {
                                        drawing(of: c, ppmm: ppmm)
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
                    .padding(.leading, TrueScaleLayout.rulerLeadingInset)
                }
            }
            // Cuts off what sticks out at the top when the band does not fit.
            .clipped()
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

    /// One cartridge, centred, with the ruler a fixed distance to its left and no sideways scrolling.
    private func singleView(_ c: Cartridge, layout: TrueScaleLayout, ppmm: Double) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: TrueScaleLayout.singleGapMM * ppmm) {
                RulerView(lengthMM: layout.rulerMM, pointsPerMM: ppmm, unit: unit)
                    .padding(.trailing, 4)
                drawing(of: c, ppmm: ppmm)
            }
            .frame(height: layout.bandHeight, alignment: .bottom)
            .overlay(alignment: .bottom) {
                // The base line the cartridge stands on, continuing the ruler's zero.
                Rectangle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(height: 0.5)
            }
            .offset(x: TrueScaleLayout.singleOffset(pointsPerMM: ppmm))
            label(for: c)
            CaseBaseView(cartridge: c, pointsPerMM: ppmm)
        }
        .frame(maxWidth: .infinity)
    }

    /// Drawn without its bullet: compared as an empty case, with the bullets switched off.
    private func caseOnly(_ c: Cartridge) -> Bool {
        !bulletsOnCases && emptyCases.contains(c.id)
    }

    private func drawing(of c: Cartridge, ppmm: Double) -> some View {
        CartridgeView(cartridge: c, pointsPerMM: ppmm, caseOnly: caseOnly(c))
    }

    private func label(for c: Cartridge) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: c.name).font(.caption.bold())
            // Calibres with the same measurements look exactly like this one.
            ForEach(CartridgeCatalog.twins(of: c)) { twin in
                Text(verbatim: "= \(twin.name)").font(.caption2).foregroundStyle(.secondary)
            }
            if let why = goodMatches[c.id] {
                Text(verbatim: why).font(.caption2.weight(.semibold)).foregroundStyle(.green)
            }
            // Without the bullet, «L» below already is the case length.
            if emptyCases.contains(c.id) && !caseOnly(c) {
                // One line like «L» and «Ø», shrunk to fit the column rather than wrapped.
                Text(verbatim: Self.caseLengthText(c, unit: unit)).font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(verbatim: Self.lengthText(c, caseOnly: caseOnly(c), unit: unit)).font(.caption2)
            Text(verbatim: "Ø \(unit.format(max(c.dimensions.rim, c.dimensions.base)))").font(.caption2)
        }
        .multilineTextAlignment(.center)
        // Takes the height it needs, so a long name wraps instead of being cut short.
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: max(70, c.outline.width * scale.pointsPerMM))
        .foregroundStyle(.secondary)
    }
}

/// Says that the drawing is at real size (Raven, 2026-11-08: the word alone; no need to say why it can't be zoomed).
struct OneToOneBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: "1:1")
                .font(.caption.weight(.heavy).monospacedDigit())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white)
            Text("Originalgrösse")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
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

    static let width = 32.0
    /// Room above the top and below the zero tick, so their numbers are not cut in half.
    /// The ruler still takes up only its length in the layout, so zero stays on the base line.
    static let labelOverhang = 8.0

    /// Tick length in points by level.
    private static let tickLengths: [Double] = [4, 6, 9, 11, 14]

    /// Vertical position of a tick, measured up from the bottom edge (the base line).
    static func y(forMM mm: Double, height: Double, pointsPerMM: Double) -> Double {
        height - mm * pointsPerMM
    }

    var body: some View {
        Canvas { context, size in
            let height = size.height - 2 * Self.labelOverhang
            for tick in unit.rulerTicks(lengthMM: lengthMM) {
                let y = Self.labelOverhang + Self.y(forMM: tick.mm, height: height, pointsPerMM: pointsPerMM)
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
            axis.move(to: CGPoint(x: size.width, y: Self.labelOverhang))
            axis.addLine(to: CGPoint(x: size.width, y: Self.labelOverhang + height))
            context.stroke(axis, with: .color(.primary), lineWidth: 0.5)
        }
        .frame(width: Self.width, height: lengthMM * pointsPerMM + 2 * Self.labelOverhang)
        .padding(.vertical, -Self.labelOverhang)
        .accessibilityLabel(unit == .metric ? "Lineal in Zentimetern".loc : "Lineal in Zoll".loc)
    }
}
