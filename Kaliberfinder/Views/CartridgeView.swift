import SwiftUI

/// Draws a cartridge outline at `pointsPerMM` (real size when it comes from `ScaleModel`).
struct CartridgeView: View {
    let cartridge: Cartridge
    let pointsPerMM: Double

    static let brass = Color(red: 0.89, green: 0.76, blue: 0.44)
    static let copper = Color(red: 0.72, green: 0.45, blue: 0.20)
    static let lead = Color(red: 0.54, green: 0.55, blue: 0.57)
    static let shotShell = Color(red: 0.75, green: 0.22, blue: 0.17)

    var body: some View {
        let o = cartridge.outline
        let lineWidth = max(0.3, min(0.8, pointsPerMM * 0.08))
        ZStack(alignment: .topLeading) {
            part(o.case, fill: cartridge.kind == "shot" ? Self.shotShell : Self.brass, lineWidth: lineWidth)
            part(o.head, fill: Self.brass, lineWidth: lineWidth)
            part(o.bullet, fill: cartridge.hasCase ? Self.copper : Self.lead, lineWidth: lineWidth)
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

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for poly in polygons {
            guard let first = poly.first else { continue }
            path.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
            for p in poly.dropFirst() { path.addLine(to: CGPoint(x: p.x * scale, y: p.y * scale)) }
            path.closeSubpath()
        }
        return path
    }
}
