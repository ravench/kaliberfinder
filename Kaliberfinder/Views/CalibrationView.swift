import SwiftUI

/// Calibrates the real-size drawing: the user lays a bank card on the screen and
/// adjusts the outline until it is exactly as tall as the card's long side.
struct CalibrationView: View {
    @EnvironmentObject private var scale: ScaleModel
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double = 6
    @AppStorage(LengthUnit.storageKey) private var unit: LengthUnit = .metric

    var body: some View {
        let card = ScreenScale.cardSize
        ScrollView {
            VStack(spacing: 16) {
                Text("Lege eine Bankkarte (oder ID, Führerausweis) hochkant auf das Rechteck, oben bündig, und verschiebe den Regler, bis das Rechteck genau so lang ist wie die Karte.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RoundedRectangle(cornerRadius: 3.18 * value)
                    .stroke(Color.accentColor, lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 3.18 * value).fill(Color.accentColor.opacity(0.08)))
                    .frame(width: card.height * value, height: card.width * value)
                VStack {
                    Slider(value: $value, in: 4...8)
                    HStack {
                        Button { value -= 0.005 } label: { Image(systemName: "minus.circle") }
                            .accessibilityLabel("Kleiner")
                        Spacer()
                        Text(verbatim: unit.scaleText(pointsPerMM: value, precise: true))
                            .font(.footnote.monospacedDigit())
                        Spacer()
                        Button { value += 0.005 } label: { Image(systemName: "plus.circle") }
                            .accessibilityLabel("Grösser")
                    }
                    .font(.title2)
                }
                HStack {
                    Button("Zurücksetzen") {
                        scale.resetCalibration()
                        value = scale.pointsPerMM
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Speichern") {
                        if let v = ScreenScale.calibrated(points: card.width * value, millimetres: card.width) {
                            scale.calibrate(pointsPerMM: v)
                        }
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationTitle("Bildschirm kalibrieren")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { value = scale.pointsPerMM }
    }
}

extension ScreenScale.Source {
    /// German title, used as localization key.
    var title: String {
        switch self {
        case .calibrated: "Kalibriert"
        case .model: "Vom Gerätemodell"
        case .estimate: "Geschätzt, bitte kalibrieren"
        }
    }
}
