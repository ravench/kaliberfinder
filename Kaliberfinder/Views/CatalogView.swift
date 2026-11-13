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

/// A row of the photo or measurement results: a one-size group's row opens the group page, a calibre's row the
/// calibre's page, as «Alle Kaliber» shows it, whose 1:1 link draws this calibre alone (Raven, 2026-11-08) and
/// which links the group (Raven, 2026-11-13).
struct ResultLink: View {
    let cartridge: Cartridge
    var detail: String?
    var highlighted = false

    var body: some View {
        let row = CartridgeRow(cartridge: cartridge, detail: detail, highlighted: highlighted, groupTag: .group)
        if let group = CartridgeCatalog.sizeGroup(of: cartridge) {
            NavigationLink { LookalikeGroupView(group: group) } label: { row }
        } else {
            NavigationLink { CartridgeDetailView(cartridge: cartridge) } label: { row }
        }
    }
}

struct CartridgeRow: View {
    let cartridge: Cartridge
    var detail: String?
    /// Shows the detail in green, for a calibre that fits well.
    var highlighted = false
    /// How the row shows the calibre's one-size group. `.group`: the row is the group (photo and measurement results;
    /// Raven, 2026-11-13): the group's name and the «Gruppe» chip, no aliases, flags, «Selten» or «Veraltet», which
    /// its members carry; a calibre without such a group is a plain row. `.name`: the row is the calibre (catalogue,
    /// search) with the group's name as a tag under its name, on every member (Raven, 2026-11-12). `.none`: members
    /// inside the group page and rows that select. A row that names a calibre opens that calibre, which links the group.
    enum GroupTag { case none, name, group }
    var groupTag: GroupTag = .none

    /// The group the row stands for, with `.group`.
    static func shownGroup(for cartridge: Cartridge, groupTag: GroupTag) -> LookalikeGroup? {
        groupTag == .group ? CartridgeCatalog.sizeGroup(of: cartridge) : nil
    }

    /// The tags the row shows: «Gruppe» alone on a group's row, else the calibre's own without it.
    static func tags(for cartridge: Cartridge, groupTag: GroupTag) -> [CalibreTag] {
        shownGroup(for: cartridge, groupTag: groupTag) != nil ? [.group] : CalibreTag.of(cartridge).filter { $0 != .group }
    }

    /// The group's name as a tag under the calibre's name, in the catalogue (`.name`).
    static func groupName(for cartridge: Cartridge, groupTag: GroupTag) -> String? {
        groupTag == .name ? CartridgeCatalog.sizeGroup(of: cartridge)?.id : nil
    }

    var body: some View {
        let group = Self.shownGroup(for: cartridge, groupTag: groupTag)
        let groupName = Self.groupName(for: cartridge, groupTag: groupTag)
        HStack(spacing: 12) {
            // A group's row draws its parent.
            CartridgeThumbnail(cartridge: group.flatMap { CartridgeCatalog.cartridge(id: $0.id) } ?? cartridge)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: group?.id ?? cartridge.name)
                let aliases = group == nil ? cartridge.displayAliases.joined(separator: ", ") : ""
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
            // Trailing slot: a group's «Gruppe», a calibre's origin; rows without a flag or globe keep the same layout.
            if group != nil { TagChip(tag: .group) } else { OriginMarks(cartridges: [cartridge]) }
        }
    }
}
