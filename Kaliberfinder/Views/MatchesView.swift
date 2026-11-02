import SwiftUI

/// Analyses a photo and lists the calibres it may show; each opens at real size for comparison.
struct MatchesView: View {
    let photo: UIImage
    /// Distance and focal length from the LiDAR camera, nil for other photos.
    var depth: DepthScale?
    @State private var analysis: PhotoAnalysis?
    @State private var matches: [Match] = []
    @AppStorage(LengthUnit.storageKey) private var unit: LengthUnit = .metric

    var body: some View {
        List {
            Section {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if let analysis {
                    ForEach(Self.notes(for: analysis, depth: depth, unit: unit), id: \.self) { note in
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        ProgressView()
                        Text("Foto wird ausgewertet …").foregroundStyle(.secondary)
                    }
                }
            }
            if analysis != nil {
                if matches.isEmpty {
                    Section {
                        Text("Keine passenden Kaliber gefunden.")
                        NavigationLink("Alle Kaliber durchsuchen") { CatalogView() }
                    }
                } else {
                    Section {
                        NavigationLink {
                            TrueScaleView(cartridges: matches.prefix(3).map(\.cartridge))
                        } label: {
                            Label("Die besten drei 1:1 vergleichen", systemImage: "ruler")
                        }
                    }
                    Section {
                        ForEach(matches) { m in
                            NavigationLink { TrueScaleView(cartridges: [m.cartridge]) } label: {
                                CartridgeRow(cartridge: m.cartridge, detail: Self.reason(for: m))
                            }
                        }
                    } header: {
                        Text("Mögliche Kaliber")
                    } footer: {
                        Text("Lege die Patrone auf den Bildschirm, Boden auf die Nulllinie, und vergleiche.")
                    }
                }
            }
        }
        .navigationTitle("Treffer")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let result = await PhotoAnalyzer.analyze(photo)
            let size = try? result.size(depth: depth).get()
            matches = Matcher.rank(shape: result.shape, hits: HeadstampReader.hits(in: result.texts), size: size)
            analysis = result
        }
    }

    /// Why a calibre is listed, e.g. "Aufschrift «308 WIN» · Form passt gut".
    static func reason(for m: Match) -> String {
        var parts: [String] = []
        if let hit = m.headstamp { parts.append(String(format: "Aufschrift «%@»".loc, hit.text)) }
        switch m.shapeFit {
        case .good: parts.append("Form passt gut".loc)
        case .rough: parts.append("Form passt ungefähr".loc)
        case .poor: parts.append("Form passt wenig".loc)
        case nil: break
        }
        switch m.sizeFit {
        case .good: parts.append("Grösse passt gut".loc)
        case .rough: parts.append("Grösse passt ungefähr".loc)
        case .poor: parts.append("Grösse passt wenig".loc)
        case nil: break
        }
        return parts.joined(separator: " · ")
    }

    /// "Gemessen: L ≈ 71 mm, Ø ≈ 12 mm", rounded to what the measurement can tell.
    static func measuredText(_ size: MeasuredSize, unit: LengthUnit) -> String {
        let step: Double = unit == .metric ? 0.5 : LengthUnit.mmPerInch / 200
        func rounded(_ mm: Double) -> String { unit.format((mm / step).rounded() * step) }
        return String(format: "Gemessen: L ≈ %1$@, Ø ≈ %2$@".loc, rounded(size.length), rounded(size.diameter))
    }

    /// Hints about what the analysis could use, and the size measured with LiDAR.
    static func notes(for a: PhotoAnalysis, depth: DepthScale? = nil, unit: LengthUnit = .metric) -> [String] {
        var notes: [String] = []
        if depth != nil {
            switch a.size(depth: depth) {
            case .success(let size): notes.append(measuredText(size, unit: unit))
            case .failure(.outOfRange): notes.append("Abstand ausserhalb 12–45 cm: Grösse nicht gemessen, Treffer nur nach Form und Aufschrift.".loc)
            case .failure: notes.append("Grösse nicht messbar: Treffer nur nach Form und Aufschrift.".loc)
            }
        }
        if let shape = a.shape {
            if shape.isEndView { notes.append("Rund im Bild: Boden oder Spitze einer Patrone, oder eine Rundkugel. Bei Patronen zählt nur die Aufschrift.".loc) }
        } else {
            notes.append("Keine Patrone im Bild erkannt.".loc)
        }
        if a.shape == nil || a.shape?.isEndView == true {
            notes.append("Tipp: Patrone seitlich auf einen hellen, einfarbigen Untergrund legen und senkrecht von oben fotografieren.".loc)
        }
        return notes
    }
}
