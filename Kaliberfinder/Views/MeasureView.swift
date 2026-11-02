import SwiftUI

/// Find calibres from dimensions measured by hand; pick results and compare them 1:1.
struct MeasureView: View {
    @State private var overallLength = ""
    @State private var caseLength = ""
    @State private var rim = ""
    @State private var bullet = ""
    @State private var selection: [Cartridge] = []

    private var measured: MeasuredDimensions {
        MeasuredDimensions(overallLength: DimensionMatcher.number(overallLength),
                           caseLength: DimensionMatcher.number(caseLength),
                           rim: DimensionMatcher.number(rim),
                           bullet: DimensionMatcher.number(bullet))
    }

    var body: some View {
        let matches = DimensionMatcher.rank(measured)
        List {
            Section {
                field("Gesamtlänge", text: $overallLength)
                field("Hülsenlänge", text: $caseLength)
                field("Randdurchmesser", text: $rim)
                field("Geschossdurchmesser", text: $bullet)
            } header: {
                Text("Gemessen in mm")
            } footer: {
                Text("Fülle aus, was du messen kannst. Schon eine Länge und ein Durchmesser grenzen die Auswahl stark ein.")
            }
            if !matches.isEmpty {
                Section {
                    ForEach(matches) { m in
                        Button { toggle(m.cartridge) } label: {
                            HStack {
                                CartridgeRow(cartridge: m.cartridge, detail: Self.detail(for: m))
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
            let compare = selection.isEmpty ? Array(matches.prefix(3).map(\.cartridge)) : selection
            if !compare.isEmpty {
                NavigationLink { TrueScaleView(cartridges: compare) } label: {
                    Label(selection.isEmpty ? "Die besten drei 1:1 vergleichen".loc : String(format: "1:1 vergleichen (%lld)".loc, selection.count),
                          systemImage: "ruler")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
        .onChange(of: measured) { _, _ in
            let ids = Set(matches.map(\.id))
            selection.removeAll { !ids.contains($0.id) }
        }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("mm", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
        }
    }

    private func toggle(_ c: Cartridge) {
        if let i = selection.firstIndex(of: c) { selection.remove(at: i) } else { selection.append(c) }
    }

    /// E.g. "Abweichung bis 0.2 mm".
    static func detail(for m: DimensionMatch) -> String {
        m.fit == .good ? "Passt genau".loc : String(format: "Abweichung bis %@".loc, mm(m.maxDeviation))
    }
}
