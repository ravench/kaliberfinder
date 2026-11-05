import Foundation

/// Calibres whose catalogue measurements are identical (e.g. .308 Win and 7.62 NATO, or
/// .223 Rem, 5.56 NATO and GP 90) look exactly the same from the side. A photo or a calliper
/// cannot tell them apart, so the results list them as one suggestion and say so.
extension CartridgeCatalog {
    /// Same kind, same dimensions and the same silhouette: indistinguishable in the side view.
    /// Colours (bullet tip, case material) do not count, so .308 Win (soft point) and 7.62 NATO stay twins.
    static func sameProfile(_ a: Cartridge, _ b: Cartridge) -> Bool {
        a.kind == b.kind && a.dimensions == b.dimensions && silhouette(a.outline) == silhouette(b.outline)
    }

    private static func silhouette(_ o: Cartridge.Outline) -> [String?] {
        [String(o.width), String(o.height), o.case, o.head, o.bullet]
    }

    /// The other catalogue calibres that look exactly like `c` from the side, in catalogue order.
    static func twins(of c: Cartridge, in cartridges: [Cartridge] = all) -> [Cartridge] {
        cartridges.filter { $0.id != c.id && sameProfile($0, c) }
    }

    /// Puts items whose calibres look the same from the side into one group, in the order of each
    /// group's first item.
    static func groupedByProfile<Item>(_ items: [Item], cartridge: (Item) -> Cartridge) -> [[Item]] {
        var groups: [[Item]] = []
        for item in items {
            let c = cartridge(item)
            if let i = groups.firstIndex(where: { g in sameProfile(cartridge(g[0]), c) }) {
                groups[i].append(item)
            } else {
                groups.append([item])
            }
        }
        return groups
    }

    /// The note under a suggestion: "Im Profil nicht unterscheidbar" when the row holds several
    /// calibres, "Im Profil nicht unterscheidbar von …" when its twins are elsewhere, else nil.
    static func profileNote(for c: Cartridge, merged: [Cartridge] = [], in cartridges: [Cartridge] = all) -> String? {
        if !merged.isEmpty { return "Im Profil nicht unterscheidbar".loc }
        let names = twins(of: c, in: cartridges).map(\.name)
        guard !names.isEmpty else { return nil }
        return String(format: "Im Profil nicht unterscheidbar von %@".loc, names.joined(separator: ", "))
    }
}

/// One row of suggestions: a calibre, plus the calibres that look exactly the same from the side.
struct TwinGroup<Item: Identifiable>: Identifiable where Item.ID == String {
    let items: [Item]

    var id: String { items[0].id }
    var lead: Item { items[0] }
    var others: [Item] { Array(items.dropFirst()) }
}

extension Matcher {
    /// Ranked matches with identical-looking calibres in one row.
    static func grouped(_ matches: [Match]) -> [TwinGroup<Match>] {
        CartridgeCatalog.groupedByProfile(matches, cartridge: \.cartridge)
            .map { TwinGroup(items: $0) }
    }
}

extension DimensionMatcher {
    /// Ranked dimension matches with identical calibres in one row (their deviations are equal anyway).
    static func grouped(_ matches: [DimensionMatch]) -> [TwinGroup<DimensionMatch>] {
        CartridgeCatalog.groupedByProfile(matches, cartridge: \.cartridge).map { TwinGroup(items: $0) }
    }
}
