import SwiftUI

/// All catalogue calibres by category, with search. In selection mode several can be compared 1:1.
struct CatalogView: View {
    @State private var query = ""
    @State private var selecting = false
    @State private var selection: [Cartridge] = []

    var body: some View {
        let results = CartridgeCatalog.search(query)
        List {
            ForEach(CartridgeCatalog.grouped(results), id: \.category) { group in
                Section(group.category.loc) {
                    ForEach(group.cartridges) { c in row(c) }
                }
            }
        }
        .overlay {
            if results.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, prompt: "Kaliber, z. B. 9 mm Luger")
        .navigationTitle("Kaliber")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "Fertig".loc : "Auswählen".loc) {
                    selecting.toggle()
                    if !selecting { selection = [] }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting && !selection.isEmpty {
                NavigationLink {
                    TrueScaleView(cartridges: selection)
                } label: {
                    Label("1:1 vergleichen (\(selection.count))", systemImage: "ruler")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
    }

    @ViewBuilder
    private func row(_ c: Cartridge) -> some View {
        if selecting {
            Button { toggle(c) } label: {
                HStack {
                    CartridgeRow(cartridge: c)
                    Spacer()
                    Image(systemName: selection.contains(c) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection.contains(c) ? Color.accentColor : .secondary)
                }
            }
            .foregroundStyle(.primary)
        } else {
            NavigationLink { CartridgeDetailView(cartridge: c) } label: { CartridgeRow(cartridge: c) }
        }
    }

    private func toggle(_ c: Cartridge) {
        if let i = selection.firstIndex(of: c) { selection.remove(at: i) } else { selection.append(c) }
    }
}

struct CartridgeRow: View {
    let cartridge: Cartridge
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            CartridgeThumbnail(cartridge: cartridge)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: cartridge.name)
                let aliases = cartridge.displayAliases.joined(separator: ", ")
                if !aliases.isEmpty {
                    Text(verbatim: aliases).font(.caption).foregroundStyle(.secondary)
                }
                if let detail {
                    Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
