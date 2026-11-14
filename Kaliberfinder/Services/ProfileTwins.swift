import Foundation

/// Calibres of one lookalike group (calibre-data `LOOKALIKES`) with identical measurements, e.g. .308 Win
/// and 7.62 NATO, .223 Rem, 5.56 NATO and GP 90, or the rimfire Vetterli and its centrefire: a photo or a
/// calliper cannot tell them apart, so the results list them as one suggestion, tagged «Gruppe» (Raven,
/// 2026-11-11: the groups from calibre-data, once per size).
extension CartridgeCatalog {
    /// In the same one-size lookalike group (`LookalikeGroup.sameSize`): calibre-data says their cases are of one
    /// size, so a few hundredths in the sheets (the 9 mm Glisenti next to the 9x19 mm) do not split them (Raven, 2026-11-13).
    static func sameProfile(_ a: Cartridge, _ b: Cartridge) -> Bool {
        sizeGroup(of: a)?.calibres.contains(b.id) ?? false
    }

    /// Puts items whose calibres look the same from the side into one group, in the order of each
    /// group's first item; a group stands in its lookalike group's order, the parent first (.223 Remington
    /// before the 5.56 NATO and the GP 90). A row of results picks its lead from that order (`TwinGroup`).
    static func groupedByProfile<Item>(_ items: [Item], cartridge: (Item) -> Cartridge,
                                       merged: Bool = groupsSizeGroups) -> [[Item]] {
        guard merged else { return items.map { [$0] } }
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

/// One row of suggestions: a calibre, plus the calibres that look exactly the same from the side; the row draws,
/// names and rates its lead (`LookalikeGroup.shownName`) and opens the group (Raven, 2026-11-11).
struct TwinGroup<Item: Identifiable>: Identifiable where Item.ID == String {
    let items: [Item]

    var id: String { items[0].id }
    var lead: Item { items[0] }
    var others: [Item] { Array(items.dropFirst()) }

    /// The row of `matches`, which stand in their group's order. Its lead is the first of them, so the parent where
    /// it is listed, unless that one does not fit (`fits`) where another does, or is farther from what was measured
    /// than the nearest by more than `margin`: then the first that fits and is within the margin. A group's sheets
    /// are not there to tell its members apart, so less leaves the row its parent's; but measured exactly, a
    /// .32 S&W Long Wadcutter came up as the .32 S&W Long, 9 mm off, and a 7.62x25 mm Tokarev as the .30 Borchardt,
    /// which the 1:1 button then left out (review 2026-11-13).
    init(_ matches: [Item], margin: Double, distance: (Item) -> Double, fits: (Item) -> Bool = { _ in true }) {
        let fitting = matches.filter(fits)
        let among = fitting.isEmpty ? matches : fitting
        let nearest = among.map(distance).min() ?? 0
        let lead = among.first { distance($0) <= nearest + margin }
        items = lead.map { lead in [lead] + matches.filter { $0.id != lead.id } } ?? matches
    }
}

extension Matcher {
    /// How much farther from the photo than its group's nearest calibre a row's lead may be (`TwinGroup`), as a
    /// `distance`: a third of a fit's width. On the catalogue's own outlines the members of a group told apart by
    /// load are at most 0.11 apart (6 mm BR), a flush wadcutter and its parent 0.5 (2026-11-14). Side views only: no
    /// group holds a round thing, which is all an end view is compared with.
    static let groupMargin = 0.1

    /// Ranked matches with identical-looking calibres in one row. The margin alone picks a row's lead: every row
    /// goes to the 1:1 screen (`MatchesView.toCompare`), so none has a fit to lose there.
    static func grouped(_ matches: [Match]) -> [TwinGroup<Match>] {
        CartridgeCatalog.groupedByProfile(matches, cartridge: \.cartridge)
            .map { row in TwinGroup(row, margin: groupMargin, distance: { -$0.score }) }
    }
}

extension DimensionMatcher {
    /// How much farther off than its group's nearest calibre a row's lead may be (`TwinGroup`), in mm of the deviation
    /// a row shows (`maxDeviation`). calibre-data calls cases up to 0.5 mm apart in length one size; the 9x19 mm and
    /// the 9 mm Glisenti are 0.48 mm apart in overall length, the .30 Borchardt and the 7.62x25 mm Tokarev 1.16 mm.
    static let groupMargin = 0.5

    /// Ranked dimension matches with the calibres of a one-size group in one row, whatever their sheets say. A row
    /// fits where one of its calibres does, so the 1:1 button takes it (`toCompare`).
    static func grouped(_ matches: [DimensionMatch]) -> [TwinGroup<DimensionMatch>] {
        CartridgeCatalog.groupedByProfile(matches, cartridge: \.cartridge)
            .map { row in TwinGroup(row, margin: groupMargin, distance: { $0.maxDeviation }, fits: { $0.fit != .poor }) }
    }
}
