import SwiftUI

/// Dimensions of one calibre and a link to its real-size view.
struct CartridgeDetailView: View {
    let cartridge: Cartridge

    var body: some View {
        let d = cartridge.dimensions
        List {
            Section {
                HStack {
                    Spacer()
                    CartridgeThumbnail(cartridge: cartridge, size: CGSize(width: 90, height: 160))
                    Spacer()
                }
                .padding(.vertical, 8)
                NavigationLink { TrueScaleView(cartridges: [cartridge]) } label: {
                    Label("In Originalgrösse anzeigen", systemImage: "ruler")
                }
            }
            Section("Masse") {
                LabeledContent("Gesamtlänge", value: mm(d.overallLength))
                if cartridge.hasCase {
                    LabeledContent(cartridge.kind == "shot" ? "Hülsenlänge (offen)".loc : "Hülsenlänge".loc, value: mm(d.caseLength))
                    LabeledContent("Randdurchmesser", value: mm(d.rim))
                    LabeledContent("Bodendurchmesser", value: mm(d.base))
                    if let shoulder = d.shoulder {
                        LabeledContent("Schulterdurchmesser", value: mm(shoulder))
                    }
                    if cartridge.kind != "shot" {
                        LabeledContent("Halsdurchmesser", value: mm(d.neck))
                    }
                }
                if cartridge.kind != "shot" {
                    LabeledContent("Geschossdurchmesser", value: mm(d.bullet))
                }
            }
            Section {
                LabeledContent("Kategorie", value: cartridge.category.loc)
                LabeledContent("Bauart", value: Self.kindTitle(cartridge.kind).loc)
                if !cartridge.displayAliases.isEmpty {
                    LabeledContent("Auch bekannt als", value: cartridge.displayAliases.joined(separator: ", "))
                }
            } footer: {
                Text("Masse sind gerundete Richtwerte (CIP/SAAMI), keine Wiederladedaten.")
            }
        }
        .navigationTitle(Text(verbatim: cartridge.name))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// German title of a catalogue kind, used as localization key.
    static func kindTitle(_ kind: String) -> String {
        switch kind {
        case "rimless": "Randlos"
        case "rimmed": "Mit Rand"
        case "belted": "Gürtelhülse"
        case "rimfire": "Randfeuer"
        case "shot": "Schrotpatrone"
        case "ball": "Rundkugel"
        case "minie": "Minié-Geschoss"
        case "pellet": "Diabolo"
        default: "Andere"
        }
    }
}
