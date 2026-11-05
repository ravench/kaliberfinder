import SwiftUI

/// The settings page's sections, top to bottom. The recognition switches stay on the home screen.
enum SettingsSection: CaseIterable {
    case units, realSize, copyright
}

/// Settings opened from the last row of the home screen: units, screen size and the licence line.
struct SettingsView: View {
    @EnvironmentObject private var scale: ScaleModel
    @AppStorage(LengthUnit.storageKey) private var unit: LengthUnit = .metric
    /// Hidden developer switch: five taps on the copyright line (`TrainingCapture`).
    @AppStorage(TrainingCapture.enabledKey) private var trainingCapture = false

    /// Second line of the home screen's settings row, e.g. "Metrisch (mm) · Vom iPhone-Modell".
    static func summary(unit: LengthUnit, source: ScreenScale.Source) -> String {
        unit.title.loc + " · " + source.title.loc
    }

    var body: some View {
        List {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                switch section {
                case .units:
                Section("Einheiten") {
                    UnitPicker(unit: $unit)
                }
                case .realSize:
                Section {
                    NavigationLink { CalibrationView() } label: {
                        LabeledContent {
                            Text(verbatim: unit.scaleText(pointsPerMM: scale.pointsPerMM))
                        } label: {
                            Text("Bildschirm")
                            Text(scale.resolution.source.title.loc)
                        }
                    }
                } header: {
                    Text("Originalgrösse")
                } footer: {
                    Text("Bildschirmzoom und Kalibrierung werden berücksichtigt. Prüfe die Grösse einmal mit einer Bankkarte.")
                }
                case .copyright:
                if trainingCapture {
                    Section {
                        NavigationLink { TrainingCaptureView() } label: {
                            Label { Text(verbatim: "Trainingsdaten aufnehmen") } icon: { Image(systemName: "tray.and.arrow.down") }
                        }
                    } footer: {
                        Text(verbatim: "Entwicklerfunktion. Fünfmal auf die Copyright-Zeile tippen blendet sie wieder aus.")
                    }
                }
                Section {
                    Text(verbatim: "© 2026 Simon Giotta · PolyForm Noncommercial 1.0.0")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .onTapGesture(count: 5) { trainingCapture.toggle() }
                }
                }
            }
        }
        .navigationTitle("Einstellungen")
    }
}
