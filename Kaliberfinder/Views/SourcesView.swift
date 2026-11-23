import SwiftUI

/// Where a calibre's values come from (Raven, 2026-11-15): calibre-data's sources, grouped by the parts of the
/// calibre page they back, a book with its pages, a web page as a link. Opened from the calibre page and from
/// the dimensioned drawing.
struct SourcesView: View {
    let cartridge: Cartridge
    var works: [CartridgeCatalog.Work] = CartridgeCatalog.works

    var body: some View {
        List {
            ForEach(cartridge.sources, id: \.self) { group in
                Section {
                    ForEach(group.refs, id: \.self) { ref in
                        if works.indices.contains(ref.work) {
                            SourceRow(work: works[ref.work], pages: ref.pages ?? [])
                        }
                    }
                } header: {
                    Text(verbatim: Self.header(group))
                }
            }
        }
        .readableWidth()
        .navigationTitle("Quellen")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The group's parts, translated: «Schulterwinkel · Hülsenboden».
    static func header(_ group: Cartridge.SourceGroup) -> String {
        group.parts.map { Cartridge.SourceGroup.title($0).loc }.joined(separator: " · ")
    }

    /// The work's title; «Eigene Messung» for a caliper measurement.
    static func title(_ work: CartridgeCatalog.Work) -> String {
        work.measured != nil ? "Eigene Messung".loc : work.title ?? ""
    }

    /// The line under the title: authors or host, year and pages («W. Todd Woodard · 2026 · S. 573»), or a
    /// measurement's day.
    static func detail(_ work: CartridgeCatalog.Work, pages: [String]) -> String {
        if let measured = work.measured {
            return day(measured)
        }
        let page = pages.isEmpty ? nil : String(format: "S. %@".loc, pages.joined(separator: ", "))
        return [work.detail, work.year.map { String($0) }, page].compactMap { $0 }.joined(separator: " · ")
    }

    /// "2026-11-08" in the user's date format, the same day in every time zone.
    private static func day(_ iso: String) -> String {
        let utc = TimeZone(identifier: "UTC") ?? .current
        guard let date = try? Date(iso, strategy: Date.ISO8601FormatStyle(timeZone: utc).year().month().day()) else { return iso }
        var style = Date.FormatStyle(date: .numeric, time: .omitted)
        style.timeZone = utc
        return date.formatted(style)
    }
}

/// One work: its title over its detail line; a web page opens in the browser.
private struct SourceRow: View {
    let work: CartridgeCatalog.Work
    let pages: [String]

    var body: some View {
        let detail = SourcesView.detail(work, pages: pages)
        let text = VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: SourcesView.title(work))
            if !detail.isEmpty {
                Text(verbatim: detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        if let url = work.url {
            Link(destination: url) {
                HStack {
                    text
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHint(Text("Öffnet die Website"))
        } else {
            text.accessibilityElement(children: .combine)
        }
    }
}
