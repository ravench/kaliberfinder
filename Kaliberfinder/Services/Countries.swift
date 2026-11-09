import Foundation

/// The present-day countries (ISO 3166-1, two letters), named in the user's language, with their flag:
/// where training photos are taken (Raven 2026-11-09: the catalogue's countries were too few).
enum Countries {
    struct Country: Identifiable, Hashable {
        let code: String
        let name: String
        var id: String { code }
        /// The regional indicator pair of the code, e.g. 🇨🇭.
        var flag: String { Self.flag(of: code) }

        static func flag(of code: String) -> String {
            String(code.uppercased().unicodeScalars.compactMap { UnicodeScalar(0x1F1E6 + $0.value - 65).map(Character.init) })
        }
    }

    /// Codes that are not countries: unions, the unknown region and the reserved test codes.
    private static let notCountries: Set<String> = ["EU", "EZ", "UN", "QO", "ZZ", "XA", "XB"]

    static let current = all()

    static func all(locale: Locale = .current) -> [Country] {
        Locale.Region.isoRegions.compactMap { region -> Country? in
            let code = region.identifier
            guard code.count == 2, region.subRegions.isEmpty, !notCountries.contains(code),
                  let name = locale.localizedString(forRegionCode: code) else { return nil }
            return Country(code: code, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The countries whose name contains `query`, or whose code is it; all of them for an empty query.
    static func matching(_ query: String, in list: [Country] = current) -> [Country] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(needle) || $0.code.caseInsensitiveCompare(needle) == .orderedSame }
    }

    /// E.g. "🇨🇭 Schweiz" for "CH"; the code itself when the system does not know it.
    static func title(of code: String, locale: Locale = .current) -> String {
        "\(Country.flag(of: code)) \(locale.localizedString(forRegionCode: code) ?? code)"
    }
}
