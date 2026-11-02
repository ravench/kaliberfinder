import SwiftUI

/// Dimensions of one calibre and a link to its real-size view.
struct CartridgeDetailView: View {
    let cartridge: Cartridge

    var body: some View {
        let d = cartridge.dimensions
        List {
            Section {
                HStack(alignment: .bottom, spacing: 24) {
                    Spacer()
                    CartridgeThumbnail(cartridge: cartridge, size: CGSize(width: 90, height: 160))
                    // Same scale as the side view, so the head's size reads correctly next to it.
                    CaseBaseView(cartridge: cartridge, pointsPerMM: thumbnailScale)
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
                if let primer = cartridge.primer {
                    LabeledContent("Zündhütchen", value: "\(primer.title.loc), \(mm(primer.diameter))")
                } else if cartridge.kind == "rimfire" {
                    LabeledContent("Zündhütchen", value: "Randfeuer, ohne Zündhütchen".loc)
                }
            }
            Section {
                LabeledContent("Kategorie", value: cartridge.category.loc)
                LabeledContent("Bauart", value: Self.kindTitle(cartridge.kind).loc)
                if !cartridge.displayAliases.isEmpty {
                    LabeledContent("Auch bekannt als", value: cartridge.displayAliases.joined(separator: ", "))
                }
            } footer: {
                Text("Masse sind gerundete Richtwerte (CIP/SAAMI), keine Wiederladedaten. Zündhütchen: Boxer-Grösse handelsüblicher Hülsen; Militärmunition kann Berdan-Zündhütchen anderer Grösse haben.")
            }
        }
        .navigationTitle(Text(verbatim: cartridge.name))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Points per mm of the 90 × 160 pt thumbnail.
    private var thumbnailScale: Double {
        min(90 / cartridge.outline.width, 160 / cartridge.outline.height)
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
