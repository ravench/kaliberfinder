import SwiftUI

/// All catalogue calibres by category, with search. In selection mode several can be compared 1:1.
struct CatalogView: View {
    @State private var query = ""
    @State private var selecting: Bool
    @State private var selection: [Cartridge] = []

    /// `selecting`: start in selection mode, to pick calibres for a side-by-side comparison.
    init(selecting: Bool = false) {
        _selecting = State(initialValue: selecting)
    }

    var body: some View {
        let results = CartridgeCatalog.search(query)
        List {
            if selecting {
                Section {
                    if selection.isEmpty {
                        Text("Wähle die Kaliber aus, die du nebeneinander sehen willst.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(selection) { c in
                        Button { toggle(c) } label: {
                            Label { Text(verbatim: c.name) } icon: { Image(systemName: "xmark.circle.fill") }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Ausgewählt")
                }
            }
            ForEach(CartridgeCatalog.grouped(results), id: \.category) { group in
                Section(group.category.loc) {
                    ForEach(group.cartridges) { c in row(c) }
                }
            }
        }
        .overlay {
            if results.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .readableWidth()
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
                CompareButton(title: String(format: "1:1 vergleichen (%lld)".loc, selection.count), cartridges: selection)
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
            NavigationLink { CalibrePage(cartridge: c) } label: { CartridgeRow(cartridge: c, linksToGroup: true) }
        }
    }

    private func toggle(_ c: Cartridge) {
        selection = selection.toggling(c)
    }
}

struct CartridgeRow: View {
    let cartridge: Cartridge
    var detail: String?
    /// Shows the detail in green, for a calibre that fits well.
    var highlighted = false
    /// Calibres that look exactly like `cartridge` from the side, in the same row: the row names only
    /// `cartridge` (their group's parent) and the «Gruppe» tag says so; the group page lists them
    /// (Raven, 2026-11-11: the «Im Profil nicht unterscheidbar» note is obsolete with the tag).
    var merged: [Cartridge] = []
    /// The row opens the calibre's group page (`CalibrePage`), so the «Gruppe» tag says where it leads;
    /// members inside the group page and rows that only select show no such tag (Raven, PR 188).
    var linksToGroup = false

    /// The tags the row shows: all of the calibre's, the group tag only where the row leads to the group.
    static func tags(for cartridge: Cartridge, linksToGroup: Bool) -> [CalibreTag] {
        CalibreTag.of(cartridge).filter { $0 != .group || linksToGroup }
    }

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
                    Text(verbatim: detail).font(.caption)
                        .fontWeight(highlighted ? .semibold : nil)
                        .foregroundStyle(highlighted ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                }
                let tags = Self.tags(for: cartridge, linksToGroup: linksToGroup)
                if !tags.isEmpty {
                    // Own line, so the tags never wrap into the detail text; three of them stack on a narrow
                    // screen rather than hyphenate (the 13 mini with «Selten», «Veraltet» and «Gruppe»).
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 4) { ForEach(tags, id: \.self) { TagChip(tag: $0) } }
                        VStack(alignment: .leading, spacing: 2) { ForEach(tags, id: \.self) { TagChip(tag: $0) } }
                    }
                    .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
            // Trailing slot: rows without a flag or globe keep the same layout.
            OriginMarks(cartridges: [cartridge] + merged)
        }
    }
}
