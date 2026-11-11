import Foundation

/// The present-day countries (ISO 3166-1, two letters), named in the user's language, with their flag, and
/// the former states a round may come from: the country of a training series (Raven 2026-11-09: the
/// catalogue's countries were too few; 2026-11-11: historical countries too).
enum Countries {
    struct Country: Identifiable, Hashable {
        let code: String
        let name: String
        /// A former state (`Countries.former`): no flag emoji exists for it, its title is the name alone.
        var former = false
        var id: String { code }
        /// The regional indicator pair of the code, e.g. 🇨🇭.
        var flag: String { Self.flag(of: code) }
        /// E.g. "🇨🇭 Schweiz", as the pickers and the series screen show a country.
        var title: String { former ? name : flag + " " + name }

        static func flag(of code: String) -> String {
            String(code.uppercased().unicodeScalars.compactMap { UnicodeScalar(0x1F1E6 + $0.value - 65).map(Character.init) })
        }
    }

    /// Codes that are not countries: unions, the unknown region and the reserved test codes.
    private static let notCountries: Set<String> = ["EU", "EZ", "UN", "QO", "ZZ", "XA", "XB"]

    /// Former states, with calibre-data's codes where it has them (`DrawnFlag`), else the retired ISO code.
    static let former = [
        Country(code: "AH", name: "Österreich-Ungarn".loc, former: true),
        Country(code: "CS", name: "Tschechoslowakei".loc, former: true),
        Country(code: "DD", name: "DDR".loc, former: true),
        Country(code: "RUE", name: "Russisches Kaiserreich".loc, former: true),
        Country(code: "SU", name: "Sowjetunion".loc, former: true),
        Country(code: "YU", name: "Jugoslawien".loc, former: true),
    ]

    static let current = list()

    /// The present-day countries and the former states, by name.
    static func list(locale: Locale = .current) -> [Country] {
        (all(locale: locale) + former).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The present-day countries, in no order.
    static func all(locale: Locale = .current) -> [Country] {
        Locale.Region.isoRegions.compactMap { region -> Country? in
            let code = region.identifier
            guard code.count == 2, region.subRegions.isEmpty, !notCountries.contains(code),
                  let name = locale.localizedString(forRegionCode: code) else { return nil }
            return Country(code: code, name: name)
        }
    }

    /// The countries whose name contains `query`, or whose code is it; all of them for an empty query.
    static func matching(_ query: String, in list: [Country] = current) -> [Country] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(needle) || $0.code.caseInsensitiveCompare(needle) == .orderedSame }
    }

    /// E.g. "🇨🇭 Schweiz" for "CH", "Sowjetunion" for "SU"; the code itself when neither the system nor
    /// `former` knows it.
    static func title(of code: String, locale: Locale = .current) -> String {
        former.first { $0.code == code }?.title
            ?? Country(code: code, name: locale.localizedString(forRegionCode: code) ?? code).title
    }
}
