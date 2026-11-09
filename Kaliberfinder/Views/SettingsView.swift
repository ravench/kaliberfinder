import SwiftUI

/// The settings page's sections, top to bottom. The recognition switches stay on the home screen.
enum SettingsSection: CaseIterable {
    case units, realSize, copyright
}

/// Settings opened as a sheet by the home screen's gear button: units, screen size, empty cases at 1:1, the coloured
/// outline, and the app version, calibre-data commit and licence line.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var scale: ScaleModel
    @AppStorage(LengthUnit.storageKey) private var unit: LengthUnit = .metric
    @AppStorage(TrueScaleView.bulletsOnCasesKey) private var bulletsOnCases = true
    /// Only phones with a LiDAR scanner measure the photo, so only they get the switch (`MatchesView.compareByFitKey`).
    @AppStorage(MatchesView.compareByFitKey) private var compareByFit = true
    /// Hidden developer switch: five taps on the copyright line (`TrainingCapture`).
    @AppStorage(TrainingCapture.enabledKey) private var trainingCapture = false
    /// The photo's outline coloured by detection (`ShapeContour.partColoursKey`); for everyone since 2026-11-08.
    @AppStorage(ShapeContour.partColoursKey) private var partColours = false

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
                Section {
                    Toggle("Geschosse beim Vergleich mit leeren Hülsen zeigen", isOn: $bulletsOnCases)
                }
                Section {
                    Toggle("Erkennung farbig zeigen", isOn: $partColours)
                } footer: {
                    Text("Umriss auf dem Foto: grün Spitze und Boden, violett Geschoss, orange Hals und Schulter, hellblau Verjüngung des Körpers.")
                }
                if LiDARCamera.isAvailable {
                    Section {
                        Toggle("1:1-Vergleich nach Trefferqualität sortieren", isOn: $compareByFit)
                    } footer: {
                        Text("Gilt für den Vergleich aller Treffer nach einem Foto mit LiDAR-Grösse: bester Treffer zuerst statt kürzeste Patrone zuerst.")
                    }
                }
                case .copyright:
                if trainingCapture {
                    Section {
                        NavigationLink { TrainingCaptureView() } label: {
                            Label { Text("Trainingsdaten aufnehmen") } icon: { Image(systemName: "tray.and.arrow.down") }
                        }
                    } footer: {
                        Text("Entwicklerfunktion. Fünfmal auf die Copyright-Zeile tippen blendet sie wieder aus.")
                    }
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.versionText)
                    if let source = CartridgeCatalog.source {
                        LabeledContent("Kaliberdaten", value: source.text)
                    }
                    Text("© 2026 Simon Giotta · Lizenz: PolyForm Noncommercial 1.0.0")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .onTapGesture(count: 5) { trainingCapture.toggle() }
                }
                }
            }
        }
        .readableWidth()
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") { dismiss() }
            }
        }
    }
}
