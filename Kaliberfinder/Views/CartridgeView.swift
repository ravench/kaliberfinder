import SwiftUI

/// Draws a cartridge outline at `pointsPerMM` (real size when it comes from `ScaleModel`).
struct CartridgeView: View {
    let cartridge: Cartridge
    let pointsPerMM: Double
    /// Draws the case alone, without the bullet, to compare an empty case.
    var caseOnly = false
    @AppStorage(showOriginalKey) private var original = false

    static let brass = Color(red: 0.89, green: 0.76, blue: 0.44)
    static let copper = Color(red: 0.72, green: 0.45, blue: 0.20)
    static let lead = Color(red: 0.54, green: 0.55, blue: 0.57)
    static let shotShell = Color(red: 0.75, green: 0.22, blue: 0.17)
    static let steel = Color(red: 0.65, green: 0.68, blue: 0.71)
    static let paper = Color(red: 0.95, green: 0.93, blue: 0.88)
    static let lacqueredSteel = Color(red: 0.42, green: 0.42, blue: 0.33)
    static let nickel = Color(red: 0.78, green: 0.80, blue: 0.81)
    static let aluminium = Color(red: 0.66, green: 0.68, blue: 0.69)
    /// Plastic tip (V-Max, ELD, FTX, Ballistic Tip): most makers use red.
    static let polymer = Color(red: 0.80, green: 0.10, blue: 0.14)
    /// Airsoft BB: most are white plastic.
    static let plastic = Color(red: 0.97, green: 0.97, blue: 0.96)

    /// UserDefaults key of the Developer Options switch «Originalfarben zeigen», off by default: on, bullet and case
    /// are drawn as first issued (the posters' way); off, as most commonly found today (Raven, 2026-11-22).
    static let showOriginalKey = "showOriginalMaterials"

    /// Fill of the bullet: steel cap (GP 1890), steel jacket (7.65x53 mm Argentine) or steel BB, bare lead,
    /// plastic airsoft BB, the silver cupronickel jacket of early service rounds (the 6 mm Lee Navy), or copper
    /// jacket; other balls and pellets are lead. Today's jacket unless `original`: the GP 11 is copper today.
    static func bulletFill(for cartridge: Cartridge,
                           original: Bool = UserDefaults.standard.bool(forKey: showOriginalKey)) -> Color {
        let o = cartridge.outline
        return switch original ? o.bulletMaterial : o.todayBulletMaterial ?? o.bulletMaterial {
        case "copper": copper
        case "steel": steel
        case "cupronickel": nickel
        case "lead": lead
        case "plastic": plastic
        default: cartridge.hasCase ? copper : lead
        }
    }

    /// Fill of the case: brass unless the outline names another material; shot shells are plastic. Today's case
    /// unless `original`: the 7.62x54 mm R is mostly steel today, its first cases were brass.
    static func caseFill(for cartridge: Cartridge,
                         original: Bool = UserDefaults.standard.bool(forKey: showOriginalKey)) -> Color {
        if cartridge.kind == "shot" { return shotShell }
        let o = cartridge.outline
        switch original ? o.caseMaterial : o.todayCaseMaterial ?? o.caseMaterial {
        case "copper": return copper
        case "steel": return lacqueredSteel
        case "nickel": return nickel
        case "aluminium": return aluminium
        case "paper": return paper
        default: return brass
        }
    }

    /// Fill of the case head, in the side view and seen from below: a separate head part is brass
    /// (shot shell) or steel (hybrid case); without one, the case's own material reaches the rim.
    static func headFill(for cartridge: Cartridge,
                         original: Bool = UserDefaults.standard.bool(forKey: showOriginalKey)) -> Color {
        guard cartridge.outline.head != nil else { return caseFill(for: cartridge, original: original) }
        return cartridge.outline.headMaterial == "steel" ? steel : brass
    }

    /// Width of the outline of every part.
    static func lineWidth(pointsPerMM: Double) -> Double { max(0.3, min(0.8, pointsPerMM * 0.08)) }

    /// A hollow point's cavity is shaded and its hidden line is bolder than the outline, with short dashes, so that
    /// a cavity of 2 to 3 mm reads at the size of the detail page (Raven, 2026-11-17: thin dashes were too fine).
    static let cavityShade = Color.black.opacity(0.35)
    static func cavityStroke(pointsPerMM: Double) -> StrokeStyle {
        StrokeStyle(lineWidth: max(0.6, min(1.4, pointsPerMM * 0.15)),
                    dash: [max(1.5, pointsPerMM * 0.4), max(1, pointsPerMM * 0.25)])
    }

    var body: some View {
        let o = cartridge.outline
        let lineWidth = Self.lineWidth(pointsPerMM: pointsPerMM)
        ZStack(alignment: .topLeading) {
            part(o.case, fill: Self.caseFill(for: cartridge, original: original), lineWidth: lineWidth)
            part(o.head, fill: Self.headFill(for: cartridge, original: original), lineWidth: lineWidth)
            if !caseOnly {
                part(o.bullet, fill: Self.bulletFill(for: cartridge, original: original), lineWidth: lineWidth)
                part(o.patch, fill: Self.paper, lineWidth: lineWidth)
                part(o.tip, fill: o.tipMaterial == "polymer" ? Self.polymer : Self.lead, lineWidth: lineWidth)
                if let cavity = o.cavity {
                    let shape = PolygonShape(polygons: OutlineGeometry.parse(cavity), scale: pointsPerMM)
                    // Stroked open: the mouth lies on the bullet's front edge, which the outline already draws.
                    shape.fill(Self.cavityShade)
                        .overlay(PolygonShape(polygons: shape.polygons, scale: pointsPerMM, closed: false)
                            .stroke(Color.black.opacity(0.7), style: Self.cavityStroke(pointsPerMM: pointsPerMM)))
                }
            }
        }
        .frame(width: o.width * pointsPerMM, height: o.height * pointsPerMM, alignment: .topLeading)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: cartridge.name))
    }

    @ViewBuilder
    private func part(_ d: String?, fill: Color, lineWidth: Double) -> some View {
        if let d {
            let shape = PolygonShape(polygons: OutlineGeometry.parse(d), scale: pointsPerMM)
            shape.fill(fill).overlay(shape.stroke(Color.black.opacity(0.7), lineWidth: lineWidth))
        }
    }
}

/// A cartridge outline scaled to fit `size`, for list rows.
struct CartridgeThumbnail: View {
    let cartridge: Cartridge
    var size = CGSize(width: 28, height: 44)

    var body: some View {
        let o = cartridge.outline
        let s = min(Double(size.width) / o.width, Double(size.height) / o.height)
        CartridgeView(cartridge: cartridge, pointsPerMM: s)
            .frame(width: size.width, height: size.height, alignment: .bottom)
    }
}

/// Closed polygons in millimetres, drawn at `scale` points per millimetre.
struct PolygonShape: Shape {
    let polygons: [[Point]]
    let scale: Double
    /// False leaves each polygon open from its last point back to its first (a hollow point's mouth).
    var closed = true

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for poly in polygons {
            guard let first = poly.first else { continue }
            path.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
            for p in poly.dropFirst() { path.addLine(to: CGPoint(x: p.x * scale, y: p.y * scale)) }
            if closed { path.closeSubpath() }
        }
        return path
    }
}
