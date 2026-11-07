import SwiftUI

/// The «Selten» and «Veraltet» tags of a calibre, in display order.
enum CalibreTag: CaseIterable {
    case rare, obsolete

    static func of(_ c: Cartridge) -> [CalibreTag] {
        allCases.filter { $0.applies(to: c) }
    }

    func applies(to c: Cartridge) -> Bool {
        switch self {
        case .rare: c.rare
        case .obsolete: c.obsolete
        }
    }

    /// German chip text, used as localization key.
    var title: String {
        switch self {
        case .rare: "Selten"
        case .obsolete: "Veraltet"
        }
    }

    /// German explanation for the detail view, used as localization key.
    var explanation: String {
        switch self {
        case .rare: "Selten: wird kaum je gefunden. Ein Treffer ist eher eine ähnliche Patrone, also genau nachmessen."
        case .obsolete: "Veraltet: wird nicht mehr regulär hergestellt."
        }
    }

    var color: Color {
        switch self {
        case .rare: .orange
        case .obsolete: .secondary
        }
    }
}

/// A small capsule with the tag's icon and word, e.g. «Selten».
struct TagChip: View {
    let tag: CalibreTag
    @ScaledMetric(relativeTo: .caption2) private var iconSize: CGFloat = 11

    var body: some View {
        HStack(spacing: 3) {
            TagIcon(tag: tag).frame(width: iconSize, height: iconSize)
            Text(tag.title.loc)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tag.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(tag.color.opacity(0.15), in: Capsule())
    }
}

/// Magnifier with a question mark for rare (check it again), crossed-out factory for obsolete
/// (no longer made). Drawn on a 16 × 16 grid in the current foreground colour.
struct TagIcon: View {
    let tag: CalibreTag

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 16
            switch tag {
            case .rare: investigate(s)
            case .obsolete: factoryOff(s)
            }
        }
        .accessibilityHidden(true)
    }

    private func investigate(_ s: CGFloat) -> some View {
        ZStack {
            Path { p in p.addEllipse(in: CGRect(x: 1.6 * s, y: 1.6 * s, width: 10 * s, height: 10 * s)) }
                .stroke(style: StrokeStyle(lineWidth: 1.8 * s))
            Path { p in p.move(to: CGPoint(x: 10.3 * s, y: 10.3 * s)); p.addLine(to: CGPoint(x: 14.3 * s, y: 14.3 * s)) }
                .stroke(style: StrokeStyle(lineWidth: 2.3 * s, lineCap: .round))
            Path { p in
                p.addArc(center: CGPoint(x: 6.65 * s, y: 5.3 * s), radius: 1.65 * s,
                         startAngle: .degrees(180), endAngle: .degrees(60), clockwise: false)
                p.addLine(to: CGPoint(x: 6.6 * s, y: 8 * s))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round))
            Path { p in p.addEllipse(in: CGRect(x: 5.7 * s, y: 8.7 * s, width: 1.8 * s, height: 1.8 * s)) }
        }
    }

    private func factoryOff(_ s: CGFloat) -> some View {
        let slash = Path { p in p.move(to: CGPoint(x: 1.5 * s, y: 2 * s)); p.addLine(to: CGPoint(x: 14.5 * s, y: 14.5 * s)) }
        return ZStack {
            Path { p in
                p.addLines([CGPoint(x: 2, y: 14), CGPoint(x: 2, y: 7.5), CGPoint(x: 5.5, y: 9.7), CGPoint(x: 5.5, y: 7.5),
                            CGPoint(x: 9, y: 9.7), CGPoint(x: 9, y: 3.5), CGPoint(x: 12.5, y: 3.5), CGPoint(x: 12.5, y: 14)]
                    .map { CGPoint(x: $0.x * s, y: $0.y * s) })
                p.closeSubpath()
            }
            .stroke(style: StrokeStyle(lineWidth: 1.7 * s, lineJoin: .round))
            // Gap around the slash, so it reads as crossed out.
            slash.stroke(style: StrokeStyle(lineWidth: 4 * s)).blendMode(.destinationOut)
            slash.stroke(style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round))
        }
        .compositingGroup()
    }
}

/// The calibre's country flag: the emoji, or a drawn flag for former states.
struct CountryFlag: View {
    let country: Cartridge.Country
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 12

    var body: some View {
        Group {
            if let flag = country.flag {
                Text(verbatim: flag).font(.body)
            } else {
                DrawnFlag(code: country.code)
                    .frame(width: height * 1.5, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(.black.opacity(0.25), lineWidth: 0.5))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(country.name.loc))
    }
}

/// Globe for a calibre in common use worldwide, shown next to the flag of the state that introduced it.
struct WorldwideMark: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 14

    var body: some View {
        Image(systemName: "globe")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Weltweit verbreitet"))
    }
}

/// A globe when one of a row's calibres is in use worldwide, then the flags of the calibres (the lead
/// and the look-alikes merged into it, each country once; Raven 2026-11-07: globe left of the flag).
/// `slot` is the least width, trailing-aligned, so catalogue rows without marks keep their layout;
/// wider content grows the slot instead of overlapping the text to its left. The detail view passes 0.
struct OriginMarks: View {
    enum Mark: Hashable {
        case worldwide
        case country(Cartridge.Country)
    }

    let cartridges: [Cartridge]
    @ScaledMetric private var slot: CGFloat  // relative to .body, set in init

    init(cartridges: [Cartridge], slot: CGFloat = 42) {
        self.cartridges = cartridges
        _slot = ScaledMetric(wrappedValue: slot, relativeTo: .body)
    }

    /// The marks in display order: the globe first, then each country once in row order.
    static func marks(of cartridges: [Cartridge]) -> [Mark] {
        var marks: [Mark] = cartridges.contains(where: \.worldwide) ? [.worldwide] : []
        for country in cartridges.compactMap(\.country) where !marks.contains(.country(country)) {
            marks.append(.country(country))
        }
        return marks
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.marks(of: cartridges), id: \.self) { mark in
                switch mark {
                case .worldwide: WorldwideMark()
                case .country(let country): CountryFlag(country: country)
                }
            }
        }
        .fixedSize()
        .frame(minWidth: slot, alignment: .trailing)
    }
}

/// Simple flags for former states, which have no flag emoji (calibre-data COUNTRIES without one).
struct DrawnFlag: View {
    let code: String

    /// Codes this view can draw; generate_data.py DRAWN_FLAGS must match.
    static let codes: Set<String> = ["RUE", "AH", "SU", "CS"]

    var body: some View {
        switch code {
        case "RUE": stripes([.black, Color(red: 0.95, green: 0.76, blue: 0), .white])
        case "AH": stripes([.black, Color(red: 0.95, green: 0.76, blue: 0)])
        case "SU":
            Color(red: 0.8, green: 0, blue: 0).overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    Image(systemName: "star.fill")
                        .resizable()
                        .foregroundStyle(Color(red: 1, green: 0.84, blue: 0))
                        .frame(width: geo.size.height * 0.35, height: geo.size.height * 0.35)
                        .offset(x: geo.size.height * 0.15, y: geo.size.height * 0.1)
                }
            }
        case "CS":
            stripes([.white, Color(red: 0.84, green: 0.08, blue: 0.1)]).overlay {
                GeometryReader { geo in
                    Path { p in
                        p.addLines([.zero, CGPoint(x: geo.size.width / 2, y: geo.size.height / 2), CGPoint(x: 0, y: geo.size.height)])
                    }
                    .fill(Color(red: 0.07, green: 0.27, blue: 0.49))
                }
            }
        default: Color.gray
        }
    }

    private func stripes(_ colors: [Color]) -> some View {
        VStack(spacing: 0) { ForEach(colors.indices, id: \.self) { colors[$0] } }
    }
}
