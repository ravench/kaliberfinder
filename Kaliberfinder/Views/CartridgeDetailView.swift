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
                        Label {
                            LabeledContent("Ähnliche Kaliber", value: group.calibres.filter { $0 != cartridge.id }.joined(separator: ", "))
                        } icon: {
                            Image(systemName: "square.on.square")
                        }
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
            if !cartridge.tipColours.isEmpty {
                Section {
                    ForEach(cartridge.tipColours, id: \.self) { TipColourRow(tip: $0) }
                } header: {
                    Text("Farbcodes der Geschossspitze")
                } footer: {
                    Text("Militärische Laborierungen, die Farben von der Spitze abwärts.")
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
            } footer: {
                Text("Gerundete Richtwerte nach CIP/SAAMI, keine Wiederladedaten. Zündhütchen: Boxer; Militärhülsen können Berdan haben.")
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

/// One tip colour code of a calibre: the painted tip, what it means, the loads and the countries.
struct TipColourRow: View {
    let tip: Cartridge.TipColour

    var body: some View {
        HStack(spacing: 12) {
            TipSwatch(colours: tip.colours)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: tip.meaning.map { Cartridge.TipColour.title($0).loc }.joined(separator: " · "))
                if let description = tip.description {
                    Text(verbatim: description).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) { ForEach(tip.countries, id: \.code) { CountryFlag(country: $0) } }
        }
    }
}

/// A painted bullet tip: the colour bands from the tip down, in a small capsule.
struct TipSwatch: View {
    let colours: [String]
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 30

    /// The colour of each calibre-data colour name; a test keeps it complete.
    static let colours: [String: Color] = [
        "black": .black, "white": .white, "grey": .gray, "silver": Color(white: 0.78), "red": .red, "orange": .orange,
        "yellow": .yellow, "green": .green, "blue": .blue, "purple": .purple, "brown": .brown,
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(colours.enumerated()), id: \.offset) { _, name in
                (Self.colours[name] ?? .clear).frame(maxHeight: .infinity)
            }
        }
        .frame(width: height / 2, height: height)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(.secondary.opacity(0.4), lineWidth: 0.5))
        .accessibilityElement()
        .accessibilityLabel(Text(colours.map { Cartridge.TipColour.colourName($0).loc }.joined(separator: ", ")))
    }
}
