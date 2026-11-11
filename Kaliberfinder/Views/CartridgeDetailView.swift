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
            if !cartridge.colourCodes.isEmpty {
                Section {
                    ForEach(cartridge.colourCodes, id: \.self) { ColourCodeRow(code: $0) }
                } header: {
                    Text("Farbcodes")
                } footer: {
                    Text("Militärische Laborierungen. Spitze: die Farben von der Spitze abwärts.")
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

/// One colour code of a calibre: the painted tip or base, what it means, where it sits, the loads and the countries.
struct ColourCodeRow: View {
    let code: Cartridge.ColourCode

    var body: some View {
        HStack(spacing: 12) {
            ColourSwatch(part: code.part, colours: code.colours)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: code.meaning.map { Cartridge.ColourCode.title($0).loc }.joined(separator: " · "))
                Text(verbatim: ([Self.partTitle(code.part).loc] + [code.description].compactMap { $0 })
                    .joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) { ForEach(code.countries, id: \.code) { CountryFlag(country: $0) } }
        }
    }

    /// German name of where the paint is, used as localization key.
    static func partTitle(_ part: String) -> String {
        switch part {
        case "base": "Hülsenboden"
        case "annulus": "Zündhütchenring"
        case "tip": "Geschossspitze"
        default: part
        }
    }
}

/// A painted bullet tip (the colour bands from the tip down, in a small capsule), a painted case
/// base (a disc, as the case is seen from below) or a primer ring (a ring around a brass primer).
struct ColourSwatch: View {
    let part: String
    let colours: [String]
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 30

    /// The colour of each calibre-data colour name; a test keeps it complete.
    static let colours: [String: Color] = [
        "black": .black, "white": .white, "grey": .gray, "silver": Color(white: 0.78), "red": .red, "orange": .orange,
        "yellow": .yellow, "green": .green, "blue": .blue, "purple": .purple, "brown": .brown,
    ]

    var body: some View {
        Group {
            if part == "annulus" {
                Circle().fill(CartridgeView.brass)
                    .overlay(Circle().stroke(Self.colours[colours.first ?? ""] ?? .clear, lineWidth: height * 0.12))
                    .overlay(Circle().stroke(.secondary.opacity(0.4), lineWidth: 0.5))
                    .frame(width: height * 0.6, height: height * 0.6)
            } else if part == "base" {
                Circle().fill(Self.colours[colours.first ?? ""] ?? .clear)
                    .overlay(Circle().stroke(.secondary.opacity(0.4), lineWidth: 0.5))
                    .frame(width: height * 0.8, height: height * 0.8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(colours.enumerated()), id: \.offset) { _, name in
                        (Self.colours[name] ?? .clear).frame(maxHeight: .infinity)
                    }
                }
                .frame(width: height / 2, height: height)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.secondary.opacity(0.4), lineWidth: 0.5))
            }
        }
        .frame(width: height * 0.8, height: height)
        .accessibilityElement()
        .accessibilityLabel(Text(colours.map { Cartridge.ColourCode.colourName($0).loc }.joined(separator: ", ")))
    }
}
