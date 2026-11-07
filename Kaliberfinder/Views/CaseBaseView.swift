import SwiftUI

/// The case head seen from below at `pointsPerMM`: rim, and the primer in the centre, in the head's
/// colour in the side view. Rimfire cases show the folded rim instead of a primer. Nothing for balls and pellets.
struct CaseBaseView: View {
    let cartridge: Cartridge
    let pointsPerMM: Double

    var body: some View {
        if cartridge.hasCase {
            let d = cartridge.headDiameter * pointsPerMM
            let line = max(0.3, min(0.8, pointsPerMM * 0.08))
            ZStack {
                Circle().fill(CartridgeView.headFill(for: cartridge))
                Circle().stroke(Color.black.opacity(0.7), lineWidth: line)
                // Edge of the head face (chamfer, or the step to the body on rimmed cases).
                Circle()
                    .stroke(Color.black.opacity(0.25), lineWidth: line)
                    .frame(width: Self.faceDiameter(cartridge) * pointsPerMM)
                if let primer = cartridge.primer {
                    let p = primer.diameter * pointsPerMM
                    Circle().fill(Self.primerColor).frame(width: p, height: p)
                    Circle().stroke(Color.black.opacity(0.6), lineWidth: line).frame(width: p, height: p)
                }
            }
            .frame(width: d, height: d)
            .accessibilityElement()
            .accessibilityLabel(Text(Self.accessibilityText(cartridge)))
        }
    }

    static let primerColor = Color(red: 0.78, green: 0.78, blue: 0.80)

    /// Diameter of the flat head face inside the rim's chamfer or fold, in mm.
    static func faceDiameter(_ c: Cartridge) -> Double {
        switch c.kind {
        case "rimmed", "rimfire": c.dimensions.base
        default: c.headDiameter * 0.9
        }
    }

    static func accessibilityText(_ c: Cartridge) -> String {
        guard let primer = c.primer else { return "Randfeuer, ohne Zündhütchen".loc }
        return String(format: "Boden mit Zündhütchen %@".loc, primer.title.loc)
    }
}
