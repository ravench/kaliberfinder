import SwiftUI

/// Find calibres from dimensions measured by hand; pick results and compare them 1:1.
struct MeasureView: View {
    @State private var overallLength = ""
    @State private var caseLength = ""
    @State private var rim = ""
    @State private var bullet = ""
    @State private var shape: CaseShape = .any
    @State private var selection: [Cartridge] = []
    @AppStorage(LengthUnit.storageKey) private var unit: LengthUnit = .metric

    private var measured: MeasuredDimensions {
        MeasuredDimensions(overallLength: unit.parse(overallLength),
                           caseLength: unit.parse(caseLength),
                           rim: unit.parse(rim),
                           bullet: unit.parse(bullet),
                           shape: shape)
    }

    var body: some View {
        let matches = DimensionMatcher.rank(measured)
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
                Text("Fülle aus, was du messen kannst. Schon eine Länge und ein Durchmesser grenzen die Auswahl stark ein.")
            }
            if !matches.isEmpty {
                Section {
                    ForEach(matches) { m in
                        Button { toggle(m.cartridge) } label: {
                            HStack {
                                CartridgeRow(cartridge: m.cartridge, detail: Self.detail(for: m, unit: unit))
                                Spacer()
                                Image(systemName: selection.contains(m.cartridge) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection.contains(m.cartridge) ? Color.accentColor : .secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Mögliche Kaliber")
                } footer: {
                    Text("Wähle Kaliber aus, um sie in Originalgrösse nebeneinander zu vergleichen.")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Masse eingeben")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            let compare = selection.isEmpty ? DimensionMatcher.toCompare(matches) : selection
            if !compare.isEmpty {
                NavigationLink { TrueScaleView(cartridges: compare) } label: {
                    Label(Self.compareTitle(matches: matches, selected: selection.count), systemImage: "ruler")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
        .onChange(of: unit) { old, new in
            for text in [$overallLength, $caseLength, $rim, $bullet] {
                text.wrappedValue = LengthUnit.convert(text.wrappedValue, from: old, to: new)
            }
        }
        .onChange(of: measured) { _, _ in
            let ids = Set(matches.map(\.id))
            selection.removeAll { !ids.contains($0.id) }
        }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(unit.symbol, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
        }
    }

    private func toggle(_ c: Cartridge) {
        if let i = selection.firstIndex(of: c) { selection.remove(at: i) } else { selection.append(c) }
    }

    /// The compare button: the picked calibres, else all that fit, else the best three.
    static func compareTitle(matches: [DimensionMatch], selected: Int) -> String {
        if selected > 0 { return String(format: "1:1 vergleichen (%lld)".loc, selected) }
        let fitting = matches.filter { $0.fit != .poor }.count
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
