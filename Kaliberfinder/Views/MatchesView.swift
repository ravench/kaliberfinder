import SwiftUI

/// Analyses a photo and lists the calibres it may show; each opens at real size for comparison.
struct MatchesView: View {
    let photo: UIImage
    /// Distance and focal length from the LiDAR camera, nil for other photos.
    var depth: DepthScale?
    /// The analysis that is ranked: the whole photo, or the picked cartridge when there are several.
    @State private var analysis: PhotoAnalysis?
    /// The first look at the whole photo; tells whether the user has to pick a cartridge.
    @State private var overview: PhotoAnalysis?
    /// Which of several cartridges the user picked.
    @State private var chosen: Int?
    /// The photo cut down to the detected cartridges, and which part of the photo that is.
    @State private var preview: (image: UIImage, region: CGRect)?
    /// Ranked against every calibre; the switches decide which are shown.
    @State private var ranked = HiddenMatches<Match>.none
    /// The user tapped «Einblenden»: hidden matching calibres are listed too, for this result only.
    @State private var revealed = false
    @AppStorage(LengthUnit.storageKey) private var unit: LengthUnit = .metric
    /// Set when the user taps the segment the app did not detect; applies to this photo only.
    @State private var override: ScanMode?
    @AppStorage(CartridgeCatalog.includeObsoleteKey) private var includeObsolete = false
    @AppStorage(CartridgeCatalog.includeRareKey) private var includeRare = false

    var body: some View {
        List {
            Section {
                let frames = Self.frames(overview: overview, measured: analysis, picking: needsPick, mode: mode)
                CandidatePhotoView(photo: preview?.image ?? photo, candidates: frames.candidates, measured: frames.measured, parts: frames.parts,
                                   mouthLine: Self.mouthLine(measured: analysis, picking: needsPick, mode: mode),
                                   region: preview?.region ?? CGRect(x: 0, y: 0, width: 1, height: 1),
                                   maxHeight: needsPick ? 420 : 220) { choose($0) }
                if needsPick {
                    Label(Self.severalObjectsText, systemImage: "hand.tap")
                        .foregroundStyle(.orange)
                    Text(Self.severalObjectsHint).font(.footnote).foregroundStyle(.secondary)
                } else {
                    if chosen != nil {
                        Button {
                            chosen = nil
                            analysis = nil
                            override = nil
                            ranked = .none
                        } label: {
                            Label("Andere Patrone wählen", systemImage: "hand.tap")
                        }
                    }
                    if let analysis {
                        // Highlights what the app detected; tapping the other segment overrides it.
                        if let shape = analysis.shape, !shape.isEndView {
                            let detected = ScanMode.detected(in: shape)
                            Picker("Was liegt im Bild?", selection: Binding { override ?? detected } set: { override = $0 }) {
                                ForEach(ScanMode.choices) { Text($0.title.loc).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
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
            }
            if analysis != nil { results }
        }
        .readableWidth()
        .safeAreaInset(edge: .bottom) {
            // A prominent button pinned to the bottom, like on the measure screen, so it is not missed.
            if analysis != nil, !matches.isEmpty {
                CompareButton(title: Self.compareTitle(matches), cartridges: Self.toCompare(matches), emptyCases: Self.emptyCases(matches))
            }
        }
        .navigationTitle("Treffer")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let result = await PhotoAnalyzer.analyze(photo)
            if let region = Self.previewRegion(around: Self.detectedBoxes(result), imageSize: photo.size) {
                preview = (PhotoAnalyzer.cropped(photo, to: region), region)
            }
            overview = result
            if !result.hasSeveralObjects {
                analysis = result
                rank()
            }
        }
        .onChange(of: override) { rank() }
        .onChange(of: includeObsolete) { rank() }
        .onChange(of: includeRare) { rank() }
    }

    /// What the photo is compared with: the detection, unless the user overrode it.
    private var mode: ScanMode { override ?? .auto }

    /// The calibres listed: the ones the switches let through, plus the hidden ones once revealed.
    private var matches: [Match] { ranked.list(revealing: revealed) }

    /// The hint to measure by hand when the photo gives no sure answer, and the calibres found.
    @ViewBuilder private var results: some View {
        if let hint = Self.manualEntryHint(matches) {
            Section {
                Text(hint)
                NavigationLink { MeasureView() } label: {
                    Label("Masse von Hand eingeben", systemImage: "ruler")
                }
                if matches.isEmpty { NavigationLink("Alle Kaliber durchsuchen") { CatalogView() } }
            }
        }
        if !matches.isEmpty || ranked.summary != nil {
            Section {
                // Calibres that look exactly the same from the side share one row.
                ForEach(Matcher.grouped(matches)) { g in
                    NavigationLink { TrueScaleView(cartridges: [g.lead.cartridge], emptyCases: Self.emptyCases(g.items)) } label: {
                        CartridgeRow(cartridge: g.lead.cartridge, detail: Self.reason(for: g.lead),
                                     highlighted: g.lead.fitsWell, merged: g.others.map(\.cartridge))
                    }
                }
                if let summary = ranked.summary { HiddenMatchesRow(summary: summary, revealed: $revealed) }
            } header: {
                Text("Mögliche Kaliber")
            } footer: {
                Text("Lege die Patrone auf den Bildschirm, Boden auf die Nulllinie, und vergleiche.")
            }
        }
    }

    /// Frames on the photo: the competing cartridges while the user picks one; afterwards, or when
    /// there is only one, the outline of the silhouette that was measured (its box if there's none),
    /// with what found each of its edges.
    /// An empty case (as `mode` reads the photo) has no bullet: its outline ends at the mouth.
    static func frames(overview: PhotoAnalysis?, measured: PhotoAnalysis?, picking: Bool,
                       mode: ScanMode = .auto) -> (candidates: [CGRect], measured: [CGPoint]?, parts: [ShapeContour.Part]) {
        if picking { return (overview?.candidates ?? [], nil, []) }
        guard let measured, let shape = measured.shape else { return ([], nil, []) }
        if let contour = measured.contour {
            let shown = mode.part(for: shape) == .emptyCase ? contour.withoutBullet() : contour
            return ([], shown.points, shown.parts)
        }
        return ([], measured.outline, [])
    }

    /// The line across the case at its mouth, drawn with the developer switch: on a cartridge whose
    /// colours show where its bullet meets the case, not on an empty case or while the user picks.
    static func mouthLine(measured: PhotoAnalysis?, picking: Bool, mode: ScanMode = .auto) -> [CGPoint]? {
        guard !picking, let measured, let shape = measured.shape, mode.part(for: shape) != .emptyCase else { return nil }
        return measured.contour?.mouthLine
    }

    /// Boxes around everything detected in the whole photo, for cropping the preview.
    static func detectedBoxes(_ analysis: PhotoAnalysis) -> [CGRect] {
        if analysis.hasSeveralObjects { return analysis.candidates }
        guard analysis.shape != nil, let outline = analysis.outline, !outline.isEmpty else { return [] }
        let xs = outline.map(\.x), ys = outline.map(\.y)
        return [CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 0) - (xs.min() ?? 0),
                       height: (ys.max() ?? 0) - (ys.min() ?? 0))]
    }

    /// The part of the photo the preview shows: every detected cartridge with a margin of half
    /// their larger extent (at least a tenth of the photo's long side) all round, inside the photo.
    /// Nil when nothing was detected, so the whole photo is shown.
    static func previewRegion(around frames: [CGRect], imageSize: CGSize) -> CGRect? {
        guard let first = frames.first, imageSize.width > 0, imageSize.height > 0 else { return nil }
        let union = frames.dropFirst().reduce(first) { $0.union($1) }
        let w = union.width * imageSize.width, h = union.height * imageSize.height
        let margin = max(max(w, h) / 2, max(imageSize.width, imageSize.height) / 10)
        return union.insetBy(dx: -margin / imageSize.width, dy: -margin / imageSize.height)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Several cartridges compete and the user hasn't picked one yet.
    private var needsPick: Bool { overview?.hasSeveralObjects == true && chosen == nil }

    /// Measures only the picked cartridge.
    private func choose(_ index: Int) {
        guard let overview, overview.candidates.indices.contains(index), chosen == nil else { return }
        chosen = index
        analysis = nil
        Task {
            let result = await PhotoAnalyzer.analyze(photo, focusingOn: overview.candidates[index])
            guard chosen == index else { return }
            analysis = result
            rank()
        }
    }

    private func rank() {
        revealed = false
        guard let analysis else { ranked = .none; return }
        ranked = Matcher.rankHiding(HiddenTag.hidden(includeObsolete: includeObsolete, includeRare: includeRare), shape: analysis.shape,
                                    size: analysis.rawSize(depth: depth), perspective: analysis.perspective(depth: depth),
                                    mouth: analysis.contour?.mouth, mode: mode, brass: analysis.isBrass)
    }

    /// Points the user to measuring by hand when the photo found nothing or only weak shapes. A
    /// good shape match is checked on the 1:1 screen instead, with or without LiDAR.
    static func manualEntryHint(_ matches: [Match]) -> String? {
        if matches.isEmpty {
            return "Keine passenden Kaliber gefunden. Miss die Patrone mit einer Schieblehre und gib die Masse ein.".loc
        }
        if matches.contains(where: { $0.shapeFit == .good }) { return nil }
        return "Kein sicherer Treffer. Miss die Patrone mit einer Schieblehre und gib die Masse ein.".loc
    }

    /// Shown instead of matches when several cartridges compete, until the user picks one.
    static var severalObjectsText: String { "Mehrere Patronen im Bild erkannt.".loc }
    static var severalObjectsHint: String {
        "Tippe auf die Patrone, die bestimmt werden soll.".loc
    }

    /// Every listed row goes to the 1:1 screen; it scrolls sideways. The user holds the cartridge
    /// against all of them anyway, so they stand by length, shortest first, then by the Ø shown
    /// under each (rank order where both are equal); the list above keeps its rank order.
    /// Calibres that look exactly the same from the side are shown once.
    static func toCompare(_ matches: [Match]) -> [Cartridge] {
        // `sorted` is stable, so ties keep their rank order.
        Matcher.grouped(matches).map(\.lead)
            .sorted { (comparedLength($0), $0.cartridge.headDiameter) < (comparedLength($1), $1.cartridge.headDiameter) }
            .map(\.cartridge)
    }

    /// The length the photo was compared with: the case for an empty case, else the whole cartridge.
    static func comparedLength(_ m: Match) -> Double {
        m.part == .emptyCase ? m.cartridge.dimensions.caseLength : m.cartridge.dimensions.overallLength
    }

    /// The calibres the photo was compared with as empty cases; balls and blanks are always compared whole.
    static func emptyCases(_ matches: [Match]) -> Set<String> {
        Set(matches.filter { $0.part == .emptyCase }.map(\.cartridge.id))
    }

    /// E.g. "Alle passenden 1:1 vergleichen (5)", counting identical-looking calibres once.
    static func compareTitle(_ matches: [Match]) -> String {
        String(format: "Alle passenden 1:1 vergleichen (%lld)".loc, toCompare(matches).count)
    }

    /// Why a calibre is listed, e.g. "Form passt gut · Grösse passt ungefähr".
    static func reason(for m: Match) -> String {
        var parts: [String] = []
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
        // A loaded round shows its neck where the shoulder steps down to it (SHAPE-06).
        if part == .emptyCase {
            parts.append(f.hasNeck ? "Flaschenhals".loc : "gerade Hülse".loc)
        } else if shape.neck != nil {
            parts.append("Flaschenhals".loc)
        }
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
            switch a.size(depth: depth, mode: mode) {
            case .success(let size): notes.append(measuredText(size, unit: unit))
            case .failure(.outOfRange): notes.append("Abstand ausserhalb 12–45 cm: Grösse nicht gemessen, Treffer nur nach Form.".loc)
            case .failure: notes.append("Grösse nicht messbar: Treffer nur nach Form.".loc)
            }
        }
        if let shape = a.shape {
            if shape.isEndView { notes.append("Rund im Bild: Boden oder Spitze einer Patrone, oder eine Rundkugel. Patronen werden nur von der Seite erkannt.".loc) }
        } else {
            notes.append("Keine Patrone im Bild erkannt.".loc)
        }
        if a.shape == nil || a.shape?.isEndView == true {
            notes.append("Tipp: Patrone seitlich auf einen hellen, einfarbigen Untergrund legen und senkrecht von oben fotografieren.".loc)
        }
        return notes
    }
}
