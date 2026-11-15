import SwiftUI

/// The switches meant for the developer (Raven, 2026-11-14), behind the last row of Settings so they
/// stay out of the users' way: the training capture, visible rather than hidden (App Store guideline 2.3.1).
struct DeveloperOptionsView: View {
    @AppStorage(TrainingCapture.enabledKey) private var trainingCapture = false
    @AppStorage(CartridgeCatalog.showUnsourcedKey) private var showUnsourced = false
    @AppStorage(CartridgeCatalog.showCannonKey) private var showCannon = false

    var body: some View {
        List {
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
            Section {
                Toggle(isOn: $showUnsourced) {
                    Label { Text("Unbelegte Kaliber zeigen") } icon: { Image(systemName: "questionmark.square.dashed") }
                }
            } footer: {
                Text("Kaliber, deren Masse in calibre-data nicht gut belegt sind: Teile ihrer Zeichnung sind geschätzt. Sonst weder in Listen, Suche noch Treffern.")
            }
            Section {
                Toggle(isOn: $showCannon) {
                    Label { Text("Kanonenkaliber zeigen") } icon: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                }
            } footer: {
                Text("Munition von 20 bis 57 mm, in calibre-data erst unvollständig erfasst: ohne Zeichnung, und zu gross für den Bildschirm. Nur in Listen und Suche, nie in den Treffern.")
            }
        }
        .readableWidth()
        .navigationTitle("Entwickleroptionen")
        .navigationBarTitleDisplayMode(.inline)
    }
}
