import SwiftUI

/// The settings page's sections, top to bottom. The recognition switches stay on the home screen.
enum SettingsSection: CaseIterable {
    case units, compare, photo, info, training
}

/// Settings opened as a sheet by the home screen's gear button (tidied up with Raven, 2026-11-10): units,
/// the 1:1 comparison (with the screen's real size), the photo, and the app's version, calibre data and licence line.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var scale: ScaleModel
    @AppStorage(LengthUnit.storageKey) private var unit: LengthUnit = .metric
    @AppStorage(TrueScaleView.bulletsOnCasesKey) private var bulletsOnCases = true
    @AppStorage(CompareLength.key) private var compareLength: CompareLength = .caseLength
    /// Only phones with a LiDAR scanner measure the photo, so only they get the switch (`MatchesView.compareByFitKey`).
    @AppStorage(MatchesView.compareByFitKey) private var compareByFit = true
    /// The training capture's switch at the bottom, off by default (`TrainingCapture`).
    @AppStorage(TrainingCapture.enabledKey) private var trainingCapture = false
    /// The photo's outline coloured by detection (`ShapeContour.partColoursKey`); for everyone since 2026-11-08.
    @AppStorage(ShapeContour.partColoursKey) private var partColours = false

    var body: some View {
        List {
            ForEach(SettingsSection.allCases, id: \.self) { section in
                switch section {
                case .units: units
                case .compare: compare
                case .photo: photo
                case .info: info
                case .training: training
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

    private var units: some View {
        Section("Einheiten") {
            UnitPicker(unit: $unit)
        }
    }

    /// Everything about the 1:1 comparison in one place: the screen's size, the order, the LiDAR phones' switch, the bullets.
    private var compare: some View {
        Section {
            NavigationLink { CalibrationView() } label: {
                LabeledContent {
                    Text(verbatim: unit.scaleText(pointsPerMM: scale.pointsPerMM))
                } label: {
                    Text("Bildschirm")
                    Text(scale.resolution.source.title.loc)
                }
            }
            Picker("Sortieren nach", selection: $compareLength) {
                ForEach(CompareLength.allCases) { Text($0.title.loc).tag($0) }
            }
            if LiDARCamera.isAvailable {
                Toggle("Mit LiDAR nach Trefferqualität sortieren", isOn: $compareByFit)
            }
            Toggle("Geschosse bei leeren Hülsen zeigen", isOn: $bulletsOnCases)
        } header: {
            Text("1:1-Vergleich")
        } footer: {
            if LiDARCamera.isAvailable {
                Text("Prüfe die Grösse einmal mit einer Bankkarte.") + Text(verbatim: " ")
                    + Text("Nach einem Foto mit LiDAR-Grösse: bester Treffer zuerst statt kürzeste Patrone.")
            } else {
                Text("Prüfe die Grösse einmal mit einer Bankkarte.")
            }
        }
    }

    private var photo: some View {
        Section {
            Toggle("Erkennung farbig zeigen", isOn: $partColours)
        } header: {
            Text("Fotoerkennung")
        } footer: {
            Text("Grün Spitze und Boden, violett Geschoss, orange Hals und Schulter, hellblau Körper.")
        }
    }

    private var info: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.versionText)
            if let source = CartridgeCatalog.source {
                LabeledContent("Kaliberdaten", value: source.text)
            }
            Text("© 2026 Simon Giotta")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Info")
        }
    }

    /// The training capture (Raven, 2026-11-11): a visible switch, off by default, instead of the
    /// five hidden taps, so the App Store version has no hidden feature (guideline 2.3.1).
    private var training: some View {
        Section {
            Toggle(isOn: $trainingCapture) {
                Label { Text("Trainingsdaten") } icon: { Image(systemName: "tray.and.arrow.down") }
            }
            if trainingCapture {
                NavigationLink { TrainingCaptureView() } label: {
                    Label("Trainingsdaten aufnehmen", systemImage: "camera")
                }
            }
        } footer: {
            Text("Speichert Fotoserien bekannter Patronen mit den Messwerten der App auf dem Gerät, als Testdaten für die Erkennung.")
        }
    }
}
