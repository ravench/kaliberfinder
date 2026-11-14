import SwiftUI

/// The switches meant for the developer (Raven, 2026-11-14), behind the last row of Settings so they
/// stay out of the users' way: the training capture, visible rather than hidden (App Store guideline 2.3.1).
struct DeveloperOptionsView: View {
    @AppStorage(TrainingCapture.enabledKey) private var trainingCapture = false

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
        }
        .readableWidth()
        .navigationTitle("Entwickleroptionen")
        .navigationBarTitleDisplayMode(.inline)
    }
}
