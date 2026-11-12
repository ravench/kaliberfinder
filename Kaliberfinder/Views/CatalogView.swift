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
            // The calibre itself, with its group as a tag; the group page is a row on the calibre's page
            // (TestFlight 1185, 2026-11-12: a search for the .223 Remington opened its group instead).
            NavigationLink { CartridgeDetailView(cartridge: c) } label: { CartridgeRow(cartridge: c, groupTag: .name) }
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
    /// How the row shows the calibre's one-size group (Raven, 2026-11-12). `.link`: the row stands for the
    /// group in the matches and opens its page, with the short «Gruppe» in the trailing slot on the group's
    /// namesake. `.name`: the row is the calibre itself (catalogue, search) and opens its page; the group's name
    /// is a tag under the name on every member. `.none`: members inside the group page and rows that select.
    enum GroupTag { case none, name, link }
    var groupTag: GroupTag = .none

    /// The tags the row shows: all of the calibre's, «Gruppe» only where the row stands for the group.
    static func tags(for cartridge: Cartridge, groupTag: GroupTag) -> [CalibreTag] {
        CalibreTag.of(cartridge).filter { $0 != .group || groupTag == .link }
    }

    /// The group's name as a tag under the calibre's name: on every member in the catalogue (`.name`), in the
    /// matches (`.link`) only on a member other than the namesake, which names the row and gets «Gruppe» instead.
    static func groupName(for cartridge: Cartridge, groupTag: GroupTag) -> String? {
        guard groupTag != .none, let group = CartridgeCatalog.sizeGroup(of: cartridge) else { return nil }
        return groupTag == .name || group.id != cartridge.id ? group.id : nil
    }

    var body: some View {
        let groupName = Self.groupName(for: cartridge, groupTag: groupTag)
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
                let chips = Self.tags(for: cartridge, groupTag: groupTag).filter { $0 != .group }.map { ($0, String?.none) }
                    + (groupName.map { [(CalibreTag.group, String?.some($0))] } ?? [])
                if !chips.isEmpty {
                    // Own line, so the tags never wrap into the detail text; three of them stack on a narrow
                    // screen rather than hyphenate (the 13 mini with «Selten», «Veraltet» and a group's name).
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 4) { ForEach(Array(chips.enumerated()), id: \.offset) { TagChip(tag: $0.element.0, text: $0.element.1) } }
                        VStack(alignment: .leading, spacing: 2) { ForEach(Array(chips.enumerated()), id: \.offset) { TagChip(tag: $0.element.0, text: $0.element.1) } }
                    }
                    .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
            // Trailing slot: the parent's «Gruppe», then the origin; rows without a flag or globe keep the same layout.
            HStack(spacing: 6) {
                if groupName == nil, Self.tags(for: cartridge, groupTag: groupTag).contains(.group) { TagChip(tag: .group) }
                OriginMarks(cartridges: [cartridge] + merged)
            }
        }
    }
}
