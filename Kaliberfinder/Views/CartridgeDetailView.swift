import SwiftUI

/// Dimensions of one calibre and links to its real-size view and its dimensioned drawing.
struct CartridgeDetailView: View {
    let cartridge: Cartridge
    @AppStorage(LengthUnit.storageKey) private var unit: LengthUnit = .metric
    /// The hidden developer switch (`TrainingCapture`): with it on, a series of this calibre starts from here.
    @AppStorage(TrainingCapture.enabledKey) private var trainingCapture = false

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
                NavigationLink { TrueScaleView(cartridges: [cartridge], linksToDetails: false) } label: {
                    Label("In Originalgrösse anzeigen", systemImage: "ruler")
                }
                NavigationLink { MeasurementsView(cartridge: cartridge) } label: {
                    Label("Masszeichnung anzeigen", systemImage: "pencil.and.ruler")
                }
                if let group = CartridgeCatalog.lookalikeGroup(of: cartridge) {
                    // The lookalikes of calibre-data: the group page lists them all and compares them at 1:1.
                    NavigationLink { LookalikeGroupView(group: group) } label: {
                        LabeledContent("Ähnliche Kaliber", value: group.calibres.filter { $0 != cartridge.id }.joined(separator: ", "))
                    }
                }
                if trainingCapture {
                    NavigationLink { TrainingCaptureView(newSeriesFor: cartridge) } label: {
                        Label("Trainingsdaten aufnehmen", systemImage: "tray.and.arrow.down")
                    }
                }
            }
            Section("Masse") {
                LabeledContent("Gesamtlänge", value: unit.format(d.overallLength))
                if cartridge.hasCase {
                    LabeledContent(cartridge.kind == "shot" ? "Hülsenlänge (offen)".loc : "Hülsenlänge".loc, value: unit.format(d.caseLength))
                    LabeledContent("Randdurchmesser", value: unit.format(d.rim))
                    LabeledContent("Bodendurchmesser", value: unit.format(d.base))
                    if let shoulder = d.shoulder {
                        LabeledContent("Schulterdurchmesser", value: unit.format(shoulder))
                    }
                    if cartridge.kind != "shot" {
                        LabeledContent("Halsdurchmesser", value: unit.format(d.neck))
                    }
                }
                if cartridge.kind != "shot" && !cartridge.blank {
                    LabeledContent("Geschossdurchmesser", value: unit.format(d.bullet))
                }
                if let primer = cartridge.primer {
                    LabeledContent("Zündhütchen", value: "\(primer.title.loc), \(unit.format(primer.diameter))")
                } else if cartridge.kind == "rimfire" {
                    LabeledContent("Zündhütchen", value: "Randfeuer, ohne Zündhütchen".loc)
                }
            }
            Section {
                LabeledContent("Kategorie", value: cartridge.category.loc)
                LabeledContent("Bauart", value: Self.kindTitle(cartridge.kind).loc)
                if let country = cartridge.country {
                    LabeledContent("Herkunft") {
                        HStack(spacing: 6) {
                            Text(country.name.loc)
                            OriginMarks(cartridges: [cartridge], slot: 0).accessibilityHidden(true)
                        }
                    }
                }
                if cartridge.worldwide {
                    LabeledContent("Verbreitung", value: "Weltweit verbreitet".loc)  // the globe is in the row above
                }
                ForEach(CalibreTag.of(cartridge), id: \.self) { tag in
                    Label { Text(tag.explanation.loc).font(.footnote) } icon: {
                        TagIcon(tag: tag).frame(width: 16, height: 16).foregroundStyle(tag.color)
                    }
                }
                if !cartridge.displayAliases.isEmpty {
                    LabeledContent("Auch bekannt als", value: cartridge.displayAliases.joined(separator: ", "))
                }
                let twins = CartridgeCatalog.twins(of: cartridge)
                if !twins.isEmpty {
                    LabeledContent("Im Profil nicht unterscheidbar von", value: twins.map(\.name).joined(separator: ", "))
                }
            } footer: {
                Text("Masse sind gerundete Richtwerte (CIP/SAAMI), keine Wiederladedaten. Zündhütchen: Boxer-Grösse handelsüblicher Hülsen; Militärmunition kann Berdan-Zündhütchen anderer Grösse haben.")
            }
        }
        .readableWidth()
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
