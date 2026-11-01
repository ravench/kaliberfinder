import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var scale: ScaleModel

    var body: some View {
        List {
            Section {
                NavigationLink { CatalogView() } label: {
                    Label("Alle Kaliber", systemImage: "list.bullet")
                }
            }
            Section {
                NavigationLink { CalibrationView() } label: {
                    LabeledContent {
                        Text(verbatim: scale.pointsPerMM.formatted(.number.precision(.fractionLength(2))) + " pt/mm")
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
                Text(verbatim: "© 2026 Simon Giotta · PolyForm Noncommercial 1.0.0")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Kaliberfinder")
    }
}
