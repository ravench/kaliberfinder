import PhotosUI
import SwiftUI

/// Analyses a photo and lists the calibres it may show; each opens at real size for comparison.
struct MatchesView: View {
    let photo: UIImage
    /// Distance and focal length from the LiDAR camera, nil for other photos.
    var depth: DepthScale?
    @State private var analysis: PhotoAnalysis?
    @State private var matches: [Match] = []
    /// The optional second photo of the case head; only its text is read.
    @State private var basePhoto: UIImage?
    @State private var baseTexts: [String]?
    @State private var showBaseCamera = false
    @State private var baseItem: PhotosPickerItem?
    @AppStorage(LengthUnit.storageKey) private var unit: LengthUnit = .metric
    @AppStorage(ScanMode.storageKey) private var mode: ScanMode = .auto

    var body: some View {
        List {
            Section {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if let analysis, analysis.hasSeveralObjects {
                    Label(Self.severalObjectsText, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(Self.severalObjectsHint).font(.footnote).foregroundStyle(.secondary)
                } else if let analysis {
                    Picker("Was liegt im Bild?", selection: $mode) {
                        ForEach(ScanMode.allCases) { Text($0.title.loc).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    ForEach(Self.notes(for: analysis, depth: depth, unit: unit, mode: mode), id: \.self) { note in
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        ProgressView()
                        Text("Foto wird ausgewertet …").foregroundStyle(.secondary)
                    }
                }
            }
            if let analysis, !analysis.hasSeveralObjects {
                baseSection
                if matches.isEmpty {
                    Section {
                        Text("Keine passenden Kaliber gefunden.")
                        NavigationLink("Alle Kaliber durchsuchen") { CatalogView() }
                    }
                } else {
                    Section {
                        ForEach(matches) { m in
                            NavigationLink { TrueScaleView(cartridges: [m.cartridge]) } label: {
                                CartridgeRow(cartridge: m.cartridge, detail: Self.reason(for: m), highlighted: m.fitsWell)
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
        .safeAreaInset(edge: .bottom) {
            // A prominent button pinned to the bottom, like on the measure screen, so it is not missed.
            if analysis != nil, !matches.isEmpty {
                NavigationLink { TrueScaleView(cartridges: Self.toCompare(matches)) } label: {
                    Label(Self.compareTitle(matches), systemImage: Self.compareSymbol)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
        .navigationTitle("Treffer")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let result = await PhotoAnalyzer.analyze(photo, kind: .side)
            analysis = result
            rank()
        }
        .onChange(of: mode) { rank() }
        .fullScreenCover(isPresented: $showBaseCamera) {
            CameraPicker { setBasePhoto($0) }
                .ignoresSafeArea()
        }
        .onChange(of: baseItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    setBasePhoto(image)
                }
                baseItem = nil
            }
        }
    }

    /// Second photo of the case head, read for the headstamp.
    private var baseSection: some View {
        Section {
            if let basePhoto {
                HStack(spacing: 12) {
                    Image(uiImage: basePhoto)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    if let baseTexts {
                        Text(Self.baseNote(baseTexts)).font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                        Text("Aufschrift wird gelesen …").foregroundStyle(.secondary)
                    }
                }
            }
            if CameraPicker.isAvailable {
                Button { showBaseCamera = true } label: {
                    if basePhoto == nil {
                        Label("Boden fotografieren", systemImage: "camera.metering.center.weighted")
                    } else {
                        Label("Boden neu fotografieren", systemImage: "camera.metering.center.weighted")
                    }
                }
            }
            PhotosPicker(selection: $baseItem, matching: .images) {
                Label("Bodenfoto auswählen", systemImage: "photo")
            }
        } header: {
            Text("Aufschrift")
        } footer: {
            Text("Die Aufschrift wird nur auf dem Bodenfoto gelesen. Boden formatfüllend, scharf und von vorne fotografieren.")
        }
    }

    private func setBasePhoto(_ image: UIImage) {
        basePhoto = image
        baseTexts = nil
        Task {
            baseTexts = await PhotoAnalyzer.analyze(image, kind: .base).texts
            rank()
        }
    }

    private func rank() {
        guard let analysis, !analysis.hasSeveralObjects else { matches = []; return }
        let size = try? analysis.size(depth: depth).get()
        matches = Matcher.rank(shape: analysis.shape, hits: Self.hits(side: analysis, baseTexts: baseTexts), size: size, mode: mode)
    }

    /// Error shown instead of matches when the photo holds more than one cartridge.
    static var severalObjectsText: String { "Mehrere Patronen im Bild erkannt.".loc }
    static var severalObjectsHint: String {
        "Bitte nur eine Patrone pro Foto: die anderen beiseitelegen und neu fotografieren.".loc
    }

    /// Headstamp hits from the base photo, plus the first photo's text when that one showed a base anyway.
    static func hits(side: PhotoAnalysis, baseTexts: [String]?) -> [HeadstampReader.Hit] {
        HeadstampReader.hits(in: side.texts + (baseTexts ?? []))
    }

    /// "Aufschrift erkannt: «WIN 308»" or a hint that nothing was legible.
    static func baseNote(_ texts: [String]) -> String {
        var seen = Set<String>()
        let lines = texts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !lines.isEmpty else { return "Keine Aufschrift erkannt.".loc }
        return String(format: "Aufschrift erkannt: «%@»".loc, lines.prefix(3).joined(separator: " / "))
    }

    /// Symbol of the 1:1 compare buttons: two items side by side.
    static let compareSymbol = "square.and.line.vertical.and.square"

    /// Every listed calibre goes to the 1:1 screen, in rank order; it scrolls sideways.
    static func toCompare(_ matches: [Match]) -> [Cartridge] {
        matches.map(\.cartridge)
    }

    /// E.g. "Alle passenden 1:1 vergleichen (5)".
    static func compareTitle(_ matches: [Match]) -> String {
        String(format: "Alle passenden 1:1 vergleichen (%lld)".loc, matches.count)
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

    /// What the photo shows, e.g. "Erkannt: leere Hülse · Flaschenhals · ohne Rand" (SCAN-03).
    /// Nil for silhouettes built without slice widths.
    static func featuresText(_ shape: ShapeMeasurement, mode: ScanMode) -> String? {
        let part = mode.part(for: shape)
        guard let f = (part == .emptyCase ? shape.mouthFirst() : shape).features else { return nil }
        var parts: [String] = [part == .emptyCase ? "leere Hülse".loc : "Patrone".loc]
        if part == .emptyCase { parts.append(f.hasNeck ? "Flaschenhals".loc : "gerade Hülse".loc) }
        parts.append(f.isRimmed ? "mit Rand".loc : "ohne Rand".loc)
        return String(format: "Erkannt: %@".loc, parts.joined(separator: " · "))
    }

    /// "Gemessen: L ≈ 71 mm, Ø ≈ 12 mm", rounded to what the measurement can tell.
    static func measuredText(_ size: MeasuredSize, unit: LengthUnit) -> String {
        let step: Double = unit == .metric ? 0.5 : LengthUnit.mmPerInch / 200
        func rounded(_ mm: Double) -> String { unit.format((mm / step).rounded() * step) }
        return String(format: "Gemessen: L ≈ %1$@, Ø ≈ %2$@".loc, rounded(size.length), rounded(size.diameter))
    }

    /// Hints about what the analysis could use, and the size measured with LiDAR.
    static func notes(for a: PhotoAnalysis, depth: DepthScale? = nil, unit: LengthUnit = .metric, mode: ScanMode = .auto) -> [String] {
        var notes: [String] = []
        if let shape = a.shape, !shape.isEndView, let text = featuresText(shape, mode: mode) { notes.append(text) }
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
