import Foundation

/// The built-in calibre catalogue (a copy of the Schiesstagebuch data).
enum CartridgeCatalog {
    /// Catalogue categories. Raw values are the German names stored in the data.
    enum Category: String, CaseIterable {
        case rimfire = "Randfeuer"
        case handgun = "Kurzwaffe"
        case rifle = "Langwaffe"
        case blackPowder = "Schwarzpulver"
        case shotgun = "Flinte"
        case air = "Luftdruck"
    }

    private struct File: Decodable {
        let version: Int
        let cartridges: [Cartridge]
    }

    static let all: [Cartridge] = load(from: Bundle.main)

    static func load(from bundle: Bundle) -> [Cartridge] {
        guard let url = bundle.url(forResource: "Cartridges", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return decode(data)
    }

    static func decode(_ data: Data) -> [Cartridge] {
        (try? JSONDecoder().decode(File.self, from: data))?.cartridges ?? []
    }

    private static let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    static func cartridge(id: String) -> Cartridge? { byID[id] }

    /// UserDefaults key of the «Veraltete Kaliber berücksichtigen» switch. Off by default.
    static let includeObsoleteKey = "includeObsoleteCalibres"

    /// The calibres photo and dimension matching compare against: obsolete ones only when asked,
    /// rare ones never yet (their switch comes next). The catalogue list and search always show
    /// every calibre.
    static func matchable(includeObsolete: Bool, in cartridges: [Cartridge] = all) -> [Cartridge] {
        cartridges.filter { !$0.rare && (includeObsolete || !$0.obsolete) }
    }

    /// Calibres still in regular production: what matching uses with the switch off (the default).
    static let current: [Cartridge] = matchable(includeObsolete: false)

    /// Normalises a name for comparison: case, spaces, dots and "mm" don't matter, "×" is "x", "," is ".".
    static func normalized(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: ",", with: ".")
            .filter { !$0.isWhitespace }
            .replacingOccurrences(of: "mm", with: "")
            .replacingOccurrences(of: ".", with: "")
    }

    /// Catalogue entries whose name or any alias contains `query`, in catalogue order.
    static func search(_ query: String, in cartridges: [Cartridge] = all) -> [Cartridge] {
        let key = normalized(query)
        guard !key.isEmpty else { return cartridges }
        return cartridges.filter { c in c.allNames.contains { normalized($0).contains(key) } }
    }

    /// Cartridges grouped by category, in the order of `Category.allCases`.
    static func grouped(_ cartridges: [Cartridge]) -> [(category: String, cartridges: [Cartridge])] {
        let order = Category.allCases.map(\.rawValue)
        let groups = Dictionary(grouping: cartridges, by: \.category)
        return groups.keys
            .sorted { (order.firstIndex(of: $0) ?? order.count, $0) < (order.firstIndex(of: $1) ?? order.count, $1) }
            .map { ($0, groups[$0] ?? []) }
    }
}
