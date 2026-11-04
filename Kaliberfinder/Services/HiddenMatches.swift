import Foundation

/// A tag that an «Erkennung» switch can leave out of the photo and dimension results.
/// A switch for rare calibres becomes a second case here.
enum HiddenTag: CaseIterable {
    case obsolete

    func applies(to c: Cartridge) -> Bool {
        switch self {
        case .obsolete: c.obsolete
        }
    }

    /// E.g. "1 veralteter" or "3 veraltete", the part of «3 weitere Treffer: …».
    func countText(_ n: Int) -> String {
        switch self {
        case .obsolete: n == 1 ? "1 veralteter".loc : String(format: "%lld veraltete".loc, n)
        }
    }

    /// The tags the switches on the home screen hide right now.
    static func hidden(includeObsolete: Bool) -> Set<HiddenTag> {
        includeObsolete ? [] : [.obsolete]
    }
}

/// A ranked result for one calibre: a photo match or a dimension match.
protocol CalibreResult {
    var cartridge: Cartridge { get }
}

extension Match: CalibreResult {}
extension DimensionMatch: CalibreResult {}

/// Results ranked against every calibre, split into the ones the switches let through and the
/// matching ones they hide. The hidden ones can be shown in place, just for this result.
struct HiddenMatches<Item: CalibreResult> {
    /// What the list shows: up to `limit` calibres the switches let through, in rank order.
    let shown: [Item]
    /// Hidden calibres that rank among the first `limit` of all, in rank order.
    let hidden: [Item]
    /// Shown and hidden together, in rank order: the list after «Einblenden».
    let revealed: [Item]
    /// How many hidden calibres each tag accounts for, in `HiddenTag` order. A calibre with two
    /// hidden tags counts once, under the first.
    let counts: [(tag: HiddenTag, count: Int)]

    init(_ ranked: [Item], hiding tags: Set<HiddenTag>, limit: Int) {
        func tag(of item: Item) -> HiddenTag? {
            HiddenTag.allCases.first { tags.contains($0) && $0.applies(to: item.cartridge) }
        }
        let shown = Array(ranked.filter { tag(of: $0) == nil }.prefix(limit))
        let hidden = ranked.prefix(limit).filter { tag(of: $0) != nil }
        let shownIDs = Set(shown.map(\.cartridge.id)), hiddenIDs = Set(hidden.map(\.cartridge.id))
        self.shown = shown
        self.hidden = hidden
        revealed = ranked.filter { shownIDs.contains($0.cartridge.id) || hiddenIDs.contains($0.cartridge.id) }
        counts = HiddenTag.allCases.compactMap { t -> (tag: HiddenTag, count: Int)? in
            let n = hidden.filter { tag(of: $0) == t }.count
            return n > 0 ? (t, n) : nil
        }
    }

    /// Nothing ranked yet.
    static var none: Self { Self([], hiding: [], limit: 0) }

    /// The list to show: with the hidden ones once the user tapped «Einblenden».
    func list(revealing: Bool) -> [Item] { revealing ? revealed : shown }

    /// "3 weitere Treffer: 3 veraltete", or nil when nothing is hidden.
    var summary: String? {
        guard !hidden.isEmpty else { return nil }
        let total = hidden.count == 1 ? "1 weiterer Treffer".loc : String(format: "%lld weitere Treffer".loc, hidden.count)
        let parts = counts.map { $0.tag.countText($0.count) }.joined(separator: ", ")
        return "\(total): \(parts)"
    }
}

extension Matcher {
    /// How many photo matches the list shows.
    static let shownLimit = 12

    /// Ranks against every calibre, then hides the tags whose switch is off.
    static func rankHiding(_ tags: Set<HiddenTag>, shape: ShapeMeasurement?, size: MeasuredSize? = nil,
                           mode: ScanMode = .auto, brass: Bool = false,
                           cartridges: [Cartridge] = CartridgeCatalog.all) -> HiddenMatches<Match> {
        HiddenMatches(rank(shape: shape, size: size, mode: mode, cartridges: cartridges, brass: brass, limit: .max),
                      hiding: tags, limit: shownLimit)
    }
}

extension DimensionMatcher {
    /// How many dimension matches the list shows.
    static let shownLimit = 15

    /// Ranks against every calibre, then hides the tags whose switch is off.
    static func rankHiding(_ tags: Set<HiddenTag>, _ measured: MeasuredDimensions,
                           cartridges: [Cartridge] = CartridgeCatalog.all) -> HiddenMatches<DimensionMatch> {
        HiddenMatches(rank(measured, cartridges: cartridges, limit: .max), hiding: tags, limit: shownLimit)
    }
}
