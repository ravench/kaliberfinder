import SwiftUI

/// Find calibres from dimensions measured by hand: each result opens its page, the fitting ones compare 1:1,
/// as after a photo (Raven, 2026-11-13).
struct MeasureView: View {
    // For the PR screens tour only: `-screenTourLength 29.7 -screenTourBullet 9.0` fill the fields past the number pad.
    @State private var overallLength = UserDefaults.standard.string(forKey: "screenTourLength") ?? ""
    @State private var caseLength = ""
    @State private var rim = ""
    @State private var bullet = UserDefaults.standard.string(forKey: "screenTourBullet") ?? ""
    @State private var shape: CaseShape = .any
    @AppStorage(LengthUnit.storageKey) private var unit: LengthUnit = .metric
    @AppStorage(CartridgeCatalog.includeObsoleteKey) private var includeObsolete = false
    @AppStorage(CartridgeCatalog.includeRareKey) private var includeRare = false
    /// The user tapped «Einblenden»: hidden matching calibres are listed too, until the input changes.
    @State private var revealed = false

    private var measured: MeasuredDimensions {
        MeasuredDimensions(overallLength: unit.parse(overallLength),
                           caseLength: unit.parse(caseLength),
                           rim: unit.parse(rim),
                           bullet: unit.parse(bullet),
                           shape: shape)
    }

    var body: some View {
        let ranked = DimensionMatcher.rankHiding(HiddenTag.hidden(includeObsolete: includeObsolete, includeRare: includeRare), measured)
        let matches = ranked.list(revealing: revealed)
        List {
            Section {
                UnitPicker(unit: $unit)
                Picker("Form", selection: $shape) {
                    ForEach(CaseShape.allCases) { Text($0.title.loc).tag($0) }
                }
                .pickerStyle(.menu)
                field("Gesamtlänge", text: $overallLength)
                field("Hülsenlänge", text: $caseLength)
                field("Randdurchmesser", text: $rim)
                field("Geschossdurchmesser", text: $bullet)
            } header: {
                if unit == .metric { Text("Gemessen in mm") } else { Text("Gemessen in Zoll") }
            } footer: {
                Text("Was du messen kannst; eine Länge und ein Durchmesser reichen oft.")
            }
            if !matches.isEmpty || ranked.summary != nil {
                Section {
                    // A one-size group is one row (Raven, 2026-11-13), its best calibre leading.
                    ForEach(DimensionMatcher.grouped(matches)) { g in
                        ResultLink(cartridge: g.lead.cartridge, detail: Self.detail(for: g.lead, unit: unit))
                    }
                    if let summary = ranked.summary { HiddenMatchesRow(summary: summary, revealed: $revealed) }
                } header: {
                    Text("Mögliche Kaliber")
                } footer: {
                    Text("Patrone auf dem Bildschirm vergleichen.")
                }
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
            for text in [$overallLength, $caseLength, $rim, $bullet] {
                text.wrappedValue = LengthUnit.convert(text.wrappedValue, from: old, to: new)
            }
        }
        .onChange(of: measured) { _, _ in revealed = false }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(unit.symbol, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
        }
    }

    /// The compare button: all that fit, else the best three.
    static func compareTitle(matches: [DimensionMatch]) -> String {
        let fitting = DimensionMatcher.grouped(matches).filter { $0.lead.fit != .poor }.count
        return fitting > 0 ? String(format: "Alle passenden 1:1 vergleichen (%lld)".loc, fitting) : "Die besten drei 1:1 vergleichen".loc
    }

    /// E.g. "Abweichung bis 0.2 mm" (or in inches).
    static func detail(for m: DimensionMatch, unit: LengthUnit = .metric) -> String {
        m.fit == .good ? "Passt genau".loc : String(format: "Abweichung bis %@".loc, unit.format(m.maxDeviation))
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
