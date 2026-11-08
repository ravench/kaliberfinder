import SwiftUI

/// What changed in this build (`Changelog`): a sheet over the home screen, the first time the build is opened.
struct WhatsNewView: View {
    let bullets: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                        Text(verbatim: bullet)
                    }
                } footer: {
                    let info = Bundle.main.infoDictionary ?? [:]
                    let versionText = "\(info["CFBundleShortVersionString"] ?? "?") (\(info["CFBundleVersion"] ?? "?"))"
                    Text("Version \(versionText)")
                }
            }
            .readableWidth()
            .navigationTitle("Neu in dieser Version")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
