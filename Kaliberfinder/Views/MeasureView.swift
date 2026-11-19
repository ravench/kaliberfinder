import SwiftUI

/// Find calibres from dimensions measured by hand: each result opens its page, the fitting ones compare 1:1,
/// as after a photo (Raven, 2026-11-13).
struct MeasureView: View {
    // For the PR screens tour only: `-screenTourLength 29.7 -screenTourBullet 9.0` fill the fields past the number pad.
    @State private var overallLength = UserDefaults.standard.string(forKey: "screenTourLength") ?? ""
    @State private var caseLength = ""
    @State private var rim = ""
    @State private var belt = ""
    @State private var bullet = UserDefaults.standard.string(forKey: "screenTourBullet") ?? ""
    @State private var shape: CaseShape = .any
    @State private var head: RimKind = .any
    @AppStorage(LengthUnit.storageKey) private var unit: LengthUnit = .metric
    @AppStorage(CartridgeCatalog.includeObsoleteKey) private var includeObsolete = false
    @AppStorage(CartridgeCatalog.includeRareKey) private var includeRare = false
    /// The user tapped «Einblenden»: hidden matching calibres are listed too, until the input changes.
    @State private var revealed = false

    private var measured: MeasuredDimensions {
        MeasuredDimensions(overallLength: unit.parse(overallLength),
                           caseLength: unit.parse(caseLength),
                           rim: unit.parse(rim),
                           belt: head == .belted ? unit.parse(belt) : nil,  // the field shows for a belted head only
                           bullet: unit.parse(bullet),
                           shape: shape,
                           head: head)
    }

    var body: some View {
        let ranked = DimensionMatcher.rankHiding(HiddenTag.hidden(includeObsolete: includeObsolete, includeRare: includeRare), measured,
                                                 cartridges: CartridgeCatalog.visible())
        let matches = ranked.list(revealing: revealed)
        List {
            Section {
                UnitPicker(unit: $unit)
                // The outlines the series screen draws beside the same choices (tester, 2026-11-17); the row names the
                // Hülse, the choices do not repeat it (Raven 2026-11-19).
                Picker("Hülsenform", selection: $shape) {
                    ForEach(CaseShape.allCases) { choice($0.title, token: $0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                Picker("Randform", selection: $head) {
                    ForEach(RimKind.allCases) { choice($0.title, token: $0.token).tag($0) }
                }
                .pickerStyle(.menu)
                // Where each value is taken, as on the training screen, in its order (TestFlight 2026-11-16).
                MeasuringGuide(letters: Self.letters, shape: shape, head: head)
                    .padding(.vertical, 4)
                // Diameters from the rim to the tip, then lengths, as on the training screen (Raven 2026-11-19).
                field("Randdurchmesser", letter: "R", text: $rim)
                if head == .belted { field("Gürteldurchmesser", letter: "G", text: $belt) }  // the sketch draws the belt then
                field("Geschossdurchmesser", letter: "D", text: $bullet)
                field("Hülsenlänge", letter: "L", text: $caseLength)
                field("Gesamtlänge", letter: "OAL", text: $overallLength)
            } header: {
                if unit == .metric { Text("Gemessen in mm") } else { Text("Gemessen in Zoll") }
            } footer: {
                Text("Eine Länge und ein Durchmesser reichen oft.")
            }
            if !matches.isEmpty || ranked.summary != nil {
                Section {
                    // A one-size group is one row (Raven, 2026-11-13), drawn and rated as its lead (`TwinGroup`).
                    ForEach(DimensionMatcher.grouped(matches)) { g in
                        ResultLink(cartridge: g.lead.cartridge, detail: Self.detail(for: g.lead, unit: unit))
                    }
                    if let summary = ranked.summary { HiddenMatchesRow(summary: summary, revealed: $revealed) }
                } header: {
                    Text("Mögliche Kaliber")
                } footer: {
                    SafetyNote()
                }
            } else if !measured.isEmpty {
                Section { Text("Keine passenden Kaliber gefunden") }  // nothing within `DimensionMatcher.maxDeviation`
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .readableWidth()
        .navigationTitle("Masse eingeben")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !matches.isEmpty {
                CompareButton(title: Self.compareTitle(matches: matches), cartridges: DimensionMatcher.toCompare(matches))
            }
        }
        .onChange(of: unit) { old, new in
            for text in [$overallLength, $caseLength, $rim, $belt, $bullet] {
                text.wrappedValue = LengthUnit.convert(text.wrappedValue, from: old, to: new)
            }
        }
        .onChange(of: measured) { _, _ in revealed = false }
    }

    /// The letters of the form's fields on the sketch; the belt's G comes with a belted head.
    static let letters: Set<String> = ["D", "R", "L", "OAL"]

    /// A dropdown choice with its outline, where `CaseIcon` has one for the token.
    private func choice(_ title: String, token: String) -> some View {
        Label { Text(title.loc) } icon: { CaseIcon.image(token).map { Image(uiImage: $0) } }
    }

    private func field(_ title: LocalizedStringKey, letter: String?, text: Binding<String>) -> some View {
        LabeledContent {
            TextField(unit.symbol, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: letter ?? "")
                    .font(.footnote.bold())
                    .foregroundStyle(Color.accentColor)
                    .frame(minWidth: 30, alignment: .leading)
                    .accessibilityHidden(true)
                // Shrinks rather than cut off «Geschossdurchmesser» beside the letter, as the training rows do.
                Text(title).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    /// The compare button: all that fit, else the best three.
    static func compareTitle(matches: [DimensionMatch]) -> String {
        let fitting = DimensionMatcher.grouped(matches).filter { $0.lead.fit != .poor }.count
        return fitting > 0 ? String(format: "Alle passenden 1:1 vergleichen (%lld)".loc, fitting) : "Die besten drei 1:1 vergleichen".loc
    }

    /// "Passt genau" where every value lies within the tolerance, else the largest difference, tolerance included,
    /// e.g. "Abweichung bis 0.4 mm" (or in inches). Not by `fit`, which allows 0.3 mm beyond the tolerance: for a
    /// .30-30's values the .32 Winchester Special read «Passt genau» too, its bullet 0.38 mm wider (review 2026-11-18).
    static func detail(for m: DimensionMatch, unit: LengthUnit = .metric) -> String {
        m.maxDeviation == 0 ? "Passt genau".loc
            : String(format: "Abweichung bis %@".loc, unit.format(m.maxDeviation + DimensionMatcher.tolerance))
    }
}

/// Metric or imperial, as a segmented control. Writes the shared setting.
struct UnitPicker: View {
    @Binding var unit: LengthUnit

    var body: some View {
        Picker("Einheiten", selection: $unit) {
            ForEach(LengthUnit.allCases) { Text($0.title.loc).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}
