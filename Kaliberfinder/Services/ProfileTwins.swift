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
    /// group's first item; a group stands with its current calibres first (`Cartridge.isCurrent`), each in its
    /// lookalike group's order, the parent first (.223 Remington before the 5.56 NATO and the GP 90; the 6 mm BR
    /// Norma before its rare, obsolete parent). Where nothing was measured, the first is what the group is drawn as
    /// (the 1:1 screen, the group page); a row of results picks its lead by the match (`TwinGroup`).
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
            func place(_ item: Item) -> (Int, Int) { (cartridge(item).isCurrent ? 0 : 1, order.firstIndex(of: cartridge(item).id) ?? .max) }
            return g.sorted { place($0) < place($1) }
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

    /// The row of `matches`, which stand in their group's order. Its lead is the best match: the nearest to what was
    /// measured, among those that fit (`fits`) where any does. A rare or obsolete calibre (not `current`) leads only
    /// where it is nearer than every current one by more than `margin`: a group's sheets are not there to tell its
    /// members apart, so within the margin they match alike, and the row is a current calibre's (a 9x19 mm, not a
    /// 9 mm Glisenti 0.3 mm nearer; an empty 6 mm BR case the Norma, not its obsolete parent). Not the first of
    /// the group: a 7.62x25 mm Tokarev measured exactly came up as the 7.63x25 mm Mauser, 0.4 mm off (Raven,
    /// 2026-11-22), and before that as the .30 Borchardt, which the 1:1 button then left out (review 2026-11-13).
    init(_ matches: [Item], margin: Double, distance: (Item) -> Double, fits: (Item) -> Bool = { _ in true },
         current: (Item) -> Bool) {
        let fitting = matches.filter(fits)
        let among = fitting.isEmpty ? matches : fitting
        let nearest = among.map(distance).min() ?? 0
        // Exactly the margin counts, though 0.18 + 0.5 comes out below 0.68 in floating point (review 2026-11-20).
        let alike = among.filter { distance($0) <= nearest + margin + 1e-9 }
        let preferred = alike.contains(where: current) ? alike.filter(current) : alike
        // The first of equals: `matches` stand in their group's order.
        let lead = preferred.min { distance($0) < distance($1) }
        items = lead.map { lead in [lead] + matches.filter { $0.id != lead.id } } ?? matches
    }
}

extension Matcher {
    /// How much nearer to the photo than every current calibre of its group a rare or obsolete one has to be to lead
    /// its row (`TwinGroup`), as a `distance`: a third of a fit's width. On the catalogue's own outlines the members
    /// of most groups are at most 0.07 apart, so they match alike. Three pairs are farther apart: a flush wadcutter
    /// and its parent (0.5), the 6 mm BR Norma, loaded 6 mm longer than its parent (0.27), and the two .44 Henry
    /// (0.15). Measured 2026-11-14 on calibre-data #151. Side views only: no group holds a round thing, which is
    /// all an end view is compared with.
    static let groupMargin = 0.1

    /// Ranked matches with identical-looking calibres in one row. The margin alone picks a row's lead: every row
    /// goes to the 1:1 screen (`MatchesView.toCompare`), so none has a fit to lose there.
    static func grouped(_ matches: [Match]) -> [TwinGroup<Match>] {
        CartridgeCatalog.groupedByProfile(matches, cartridge: \.cartridge)
            .map { row in TwinGroup(row, margin: groupMargin, distance: { -$0.score }, current: \.cartridge.isCurrent) }
    }
}

extension DimensionMatcher {
    /// How much nearer than every current calibre of its group a rare or obsolete one has to be to lead its row
    /// (`TwinGroup`), in mm of the deviation a row shows (`maxDeviation`). calibre-data calls cases up to 0.5 mm apart
    /// in length one size; the 9x19 mm and the 9 mm Glisenti are 0.48 mm apart in overall length, the .30 Borchardt
    /// and the 7.62x25 mm Tokarev 1.16 mm.
    static let groupMargin = 0.5

    /// Ranked dimension matches with the calibres of a one-size group in one row, whatever their sheets say. A row
    /// fits where one of its calibres does, so the 1:1 button takes it (`toCompare`).
    static func grouped(_ matches: [DimensionMatch]) -> [TwinGroup<DimensionMatch>] {
        CartridgeCatalog.groupedByProfile(matches, cartridge: \.cartridge)
            .map { row in
                TwinGroup(row, margin: groupMargin, distance: { $0.maxDeviation }, fits: { $0.fit != .poor }, current: \.cartridge.isCurrent)
            }
    }
}
