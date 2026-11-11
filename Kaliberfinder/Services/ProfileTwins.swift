import Foundation

/// Calibres of one lookalike group (calibre-data `LOOKALIKES`) with identical measurements, e.g. .308 Win
/// and 7.62 NATO, .223 Rem, 5.56 NATO and GP 90, or the rimfire Vetterli and its centrefire: a photo or a
/// calliper cannot tell them apart, so the results list them as one suggestion, tagged «Gruppe» (Raven,
/// 2026-11-11: the groups from calibre-data, once per size).
extension CartridgeCatalog {
    /// In the same one-size lookalike group (`LookalikeGroup.sameSize`) and of the same dimensions; a member
    /// of another size (the shorter Glisenti next to the 9x19 mm) stays a row of its own.
    static func sameProfile(_ a: Cartridge, _ b: Cartridge) -> Bool {
        guard let group = sizeGroup(of: a) else { return false }
        return group.calibres.contains(b.id) && a.dimensions == b.dimensions
    }

    /// The other catalogue calibres that look exactly like `c` from the side, in catalogue order.
    static func twins(of c: Cartridge, in cartridges: [Cartridge] = all) -> [Cartridge] {
        cartridges.filter { $0.id != c.id && sameProfile($0, c) }
    }

    /// Puts items whose calibres look the same from the side into one group, in the order of each
    /// group's first item; within a group the lookalike group's parent leads (.223 Remington before the
    /// 5.56 NATO and the GP 90), as the row names it.
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
        return groups.map { g in
            guard g.count > 1, let order = lookalikeGroup(of: cartridge(g[0]))?.calibres else { return g }
            return g.sorted { (order.firstIndex(of: cartridge($0).id) ?? .max) < (order.firstIndex(of: cartridge($1).id) ?? .max) }
        }
    }
}

/// One row of suggestions: a calibre (its lookalike group's parent), plus the calibres that look exactly
/// the same from the side; the row names the parent and opens the group (Raven, 2026-11-11).
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
