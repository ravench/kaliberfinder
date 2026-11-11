import AVFoundation
import PhotosUI
import SwiftUI

// Hidden developer screens for recording training data (see `TrainingCapture`). Reached by
// tapping the copyright line in Settings five times; translated like the rest of the app.

/// The saved series and a button for a new one.
struct TrainingCaptureView: View {
    @State private var captures: [SavedCapture] = []
    @State private var showNew: Bool
    @State private var opened: SavedCapture?
    private let store = CaptureStore.standard
    /// The calibre a new series starts with, from its detail page: the sheet opens at once.
    private let preselected: Cartridge?

    init(newSeriesFor calibre: Cartridge? = nil) {
        preselected = calibre
        _showNew = State(initialValue: calibre != nil)
    }

    var body: some View {
        List {
            Section {
                Button { showNew = true } label: {
                    Label { Text("Neue Aufnahmeserie") } icon: { Image(systemName: "plus.circle") }
                }
            } footer: {
                Text("Wähle das Kaliber, das du fotografierst, und mache mehrere Fotos davon. Gespeichert werden das Foto, die LiDAR-Tiefe, die Kameradaten und die Vision-Maske. Teile die Serie als ZIP, sie kommt in die Tests.")
            }
            if !captures.isEmpty {
                Section {
                    ForEach(captures) { capture in
                        // A link with its view, as elsewhere in the app: a value link with navigationDestination(for:)
                        // did nothing when tapped here (the screen is itself pushed by such a link on the settings sheet).
                        NavigationLink { TrainingPackageView(capture: capture) } label: { TrainingCaptureRow(capture: capture) }
                    }
                    .onDelete { offsets in
                        for i in offsets { try? store.delete(captures[i]) }
                        reload()
                    }
                } header: {
                    Text("Gespeichert")
                }
            }
        }
        .navigationTitle("Trainingsdaten")
        .navigationDestination(item: $opened) { TrainingPackageView(capture: $0) }
        .sheet(isPresented: $showNew) {
            NavigationStack {
                NewTrainingSeriesView(calibre: preselected) { package in
                    showNew = false
                    if let url = try? store.create(package) {
                        reload()
                        opened = SavedCapture(url: url, package: package)
                    }
                }
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() { captures = store.packages() }
}

private struct TrainingCaptureRow: View {
    let capture: SavedCapture

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: capture.package.calibreName)
            if capture.package.isUnlisted {
                Label("Nicht in der Liste", systemImage: "questionmark.circle").font(.footnote).foregroundStyle(.orange)
            }
            let partName = (capture.package.scanMode == .emptyCase ? "Leere Hülse" : "Patrone").loc
            let dateText = capture.package.created.formatted(date: .abbreviated, time: .shortened)
            let sizeText = capture.bytes.formatted(.byteCount(style: .file))
            Text("\(partName) · \(capture.shotCount) Fotos · \(sizeText) · \(dateText)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Calibre, part and a note for a new series. A round the catalogue lacks gets a name instead.
private struct NewTrainingSeriesView: View {
    let onStart: (CapturePackage) -> Void
    @State private var calibre: TrainingCalibre?
    @State private var name = ""
    @State private var mode: ScanMode = .cartridge
    @State private var note = ""
    @Environment(\.dismiss) private var dismiss

    /// `calibre`: a catalogue calibre to start with, from its detail page.
    init(calibre: Cartridge? = nil, onStart: @escaping (CapturePackage) -> Void) {
        self.onStart = onStart
        _calibre = State(initialValue: calibre.map(TrainingCalibre.listed))
    }

    private var package: CapturePackage? {
        switch calibre {
        case .listed(let c): TrainingRecorder.package(calibre: c.id, mode: mode, note: note)
        case .unlisted where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            TrainingRecorder.package(calibre: name, unlisted: true, mode: mode, note: note)
        default: nil
        }
    }

    var body: some View {
        Form {
            Section {
                NavigationLink { TrainingCalibrePicker(selection: $calibre, name: $name) } label: {
                    LabeledContent {
                        switch calibre {
                        case .listed(let c): Text(verbatim: c.name)
                        case .unlisted: Text("Nicht in der Liste")
                        case nil: Text("Wählen")
                        }
                    } label: {
                        Text("Fotografiertes Kaliber")
                    }
                }
                if calibre == .unlisted {
                    TextField("Name", text: $name, prompt: Text("z. B. Bodenprägung oder eigener Name"))
                }
                Picker(selection: $mode) {
                    ForEach(TrainingCapture.parts) { part in
                        Text(part == .emptyCase ? "Leere Hülse".loc : "Patrone".loc).tag(part)
                    }
                } label: {
                    Text("Im Bild")
                }
                .pickerStyle(.segmented)
                TextField("Notiz", text: $note, prompt: Text("z. B. Holztisch, Tageslicht"))
            } footer: {
                Text("Alle Fotos dieser Serie zeigen dieses Kaliber.")
            }
        }
        .navigationTitle("Neue Serie")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    if let package { onStart(package) }
                } label: {
                    Text("Starten")
                }
                .disabled(package == nil)
            }
        }
    }
}

/// What a new series shows: a catalogue calibre, or a round the catalogue lacks.
private enum TrainingCalibre: Equatable {
    case listed(Cartridge)
    case unlisted
}

/// Searchable list of all calibres, shown and searched like «Alle Kaliber», and «Nicht in der Liste»
/// for a round the catalogue lacks (named after the search unless it has a name); picking goes back.
private struct TrainingCalibrePicker: View {
    @Binding var selection: TrainingCalibre?
    @Binding var name: String
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Button {
                    selection = .unlisted
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = query }
                    dismiss()
                } label: {
                    HStack {
                        Label("Nicht in der Liste", systemImage: "questionmark.circle")
                        Spacer()
                        if selection == .unlisted { Image(systemName: "checkmark") }
                    }
                }
            } footer: {
                Text("Für Patronen, die die App nicht kennt: eigener Name, von der Auswertung ausgenommen.")
            }
            ForEach(CartridgeCatalog.search(query)) { c in
                Button {
                    selection = .listed(c)
                    dismiss()
                } label: {
                    // With its other names, so a calibre found by one of them shows why.
                    HStack {
                        CartridgeRow(cartridge: c)
                        if selection == .listed(c) { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .searchable(text: $query, prompt: "Kaliber, z. B. 9 mm Luger")
        .navigationTitle("Kaliber")
    }
}

/// One series: its photos, the camera, library import and sharing.
struct TrainingPackageView: View {
    let capture: SavedCapture
    @State private var shots: [SavedShot] = []
    @State private var showCamera = false
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var shared: SharedFile?
    @State private var status: String?
    /// The package as edited here (note, atypical bullet, measurements); written on every change.
    @State private var package: CapturePackage

    init(capture: SavedCapture) {
        self.capture = capture
        _package = State(initialValue: capture.package)
    }

    private var measurements: Binding<Measurements> {
        Binding { package.measurements ?? Measurements() } set: { package.measurements = $0.isEmpty ? nil : $0 }
    }

    private var atypicalBullet: Binding<Bool> {
        Binding { package.atypicalBullet == true } set: { package.atypicalBullet = $0 ? true : nil }
    }

    private var headstamp: Binding<String> {
        Binding { package.headstamp ?? "" } set: { package.headstamp = $0.isEmpty ? nil : $0 }
    }

    var body: some View {
        List {
            Section {
                if LiDARCamera.canCapture {
                    Button { showCamera = true } label: {
                        Label {
                            if LiDARCamera.isAvailable { Text("Fotografieren") } else { Text("Fotografieren (ohne Tiefe)") }
                        } icon: {
                            Image(systemName: "camera")
                        }
                    }
                }
                PhotosPicker(selection: $libraryItems, matching: .images, preferredItemEncoding: .current) {
                    Label { Text("Aus Fotos hinzufügen (ohne Tiefe)") } icon: { Image(systemName: "photo") }
                }
                Button(action: share) {
                    Label { Text("Als ZIP teilen") } icon: { Image(systemName: "square.and.arrow.up") }
                }
                .disabled(shots.isEmpty)
                if let status { Text(verbatim: status).font(.footnote).foregroundStyle(.secondary) }
            } header: {
                Text(verbatim: capture.package.calibreName)
            } footer: {
                VStack(alignment: .leading) {
                    ForEach(capture.package.cameras ?? [], id: \.type) { Text(verbatim: $0.summary) }
                }
            }
            Section {
                TextField("Notiz", text: $package.note, prompt: Text("z. B. Holztisch, Tageslicht"), axis: .vertical)
                // Every present-day country and the former states, searchable (Raven, 2026-11-09 and 2026-11-11).
                NavigationLink {
                    CountryPickerView(selection: $package.country)
                } label: {
                    LabeledContent("Land", value: package.country.map { Countries.title(of: $0) } ?? "–")
                }
                // What the round is, as the old-ammunition table records it (Raven 2026-11-11).
                TextField("Bodenstempel", text: headstamp)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                choice("Zündart", selection: $package.ignition, options: RoundFacts.ignition)
                choice("Randform", selection: $package.head, options: RoundFacts.head)
                choice("Hülsenform", selection: $package.shape, options: RoundFacts.shape)
                choice("Hülsenmaterial", selection: $package.caseMaterial, options: RoundFacts.caseMaterial)
                choice("Geschoss", selection: $package.bullet, options: RoundFacts.bullet)
                // A bullet the calibre does not usually carry, so tuning the matcher knows to be careful with this series.
                Toggle("Atypisches Geschoss", isOn: atypicalBullet)
            } header: {
                Text("Serie")
            }
            Section {
                // Where each value is taken, as on the old-ammunition page (Raven 2026-11-10).
                MeasuringGuide()
                    .padding(.vertical, 4)
                ForEach(Self.calliperFields, id: \.letter) { measured($0) }
            } header: {
                Text("Mit der Schieblehre gemessen")
            }
            Section {
                ForEach(shots) { entry in
                    Text(verbatim: Self.summary(entry.url.lastPathComponent, entry.shot, pixels: CaptureStore.photoPixels(of: entry.shot, at: entry.url)))
                        .font(.footnote.monospaced())
                }
            } header: {
                Text("\(shots.count) Fotos")
            }
        }
        .navigationTitle(Text(verbatim: capture.url.lastPathComponent))
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: reload)
        .onChange(of: package) { _, new in
            // Written as typed, also back to the value the screen opened with (review 2026-11-10); nothing
            // measured and no atypical bullet leave their keys out of package.json.
            do { try CaptureStore.update(new, at: capture.url) } catch { status = error.localizedDescription }
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: reload) {
            TrainingCameraView(capture: capture)
        }
        .sheet(item: $shared) { ShareSheet(url: $0.url) }
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var saved = 0
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       (try? await TrainingRecorder.save(libraryPhoto: data, mode: capture.package.scanMode, in: capture.url)) != nil {
                        saved += 1
                    }
                }
                status = String(format: "%lld von %lld Fotos hinzugefügt".loc, saved, items.count)
                libraryItems = []
                reload()
            }
        }
    }

    /// E.g. "03  LiDAR 251 mm  48 MP  3.02  9x19 mm", or "04  Telephoto  ohne Tiefe  48 MP  3.02  9x19 mm" from
    /// another camera; the megapixels say whether the phone took the sensor's full resolution.
    static func summary(_ name: String, _ shot: CaptureShot, pixels: (width: Int, height: Int)? = nil) -> String {
        let depth = shot.scale.map { String(format: "LiDAR %.0f mm".loc, $0.tableDistance) } ?? (shot.depth == nil ? "ohne Tiefe".loc : "Tiefe relativ".loc)
        // The camera and how it ran, for shots not from the LiDAR camera as the app uses it: "Telephoto ×2 23°".
        let camera = shot.camera.map { $0 == "LiDARDepth" ? "" : "\($0)\(shot.zoom.map { String(format: " ×%g", $0) } ?? "")\(shot.fieldOfView.map { String(format: " %.0f°", $0) } ?? "")  " } ?? ""
        let size = pixels.map { String(format: "%.0f MP", Double($0.width * $0.height) / 1e6) } ?? "–"
        let aspect = shot.analysis?.aspect.map { String(format: "%.2f", $0) } ?? "–"
        return "\(name)  \(camera)\(depth)  \(size)  \(aspect)  \(shot.analysis?.matches.first ?? "kein Treffer".loc)"
    }

    private func reload() { shots = capture.shots }

    /// A picker over `options` (`RoundFacts`), «–» for none; stores the token.
    private func choice(_ title: LocalizedStringKey, selection: Binding<String?>, options: [RoundFacts.Option]) -> some View {
        Picker(title, selection: selection) {
            Text(verbatim: "–").tag(String?.none)
            ForEach(options, id: \.token) { Text($0.title.loc).tag(String?.some($0.token)) }
        }
    }

    /// A calliper field: its letter on the sketch (`MeasuringGuide`), its name and what it says about the round.
    struct CalliperField {
        let letter: String
        let title: LocalizedStringKey
        let value: WritableKeyPath<Measurements, Double?>
    }

    /// In the order of the old-ammunition table's legend.
    static let calliperFields = [
        CalliperField(letter: "D", title: "Geschossdurchmesser", value: \.bullet),
        CalliperField(letter: "N", title: "Halsdurchmesser", value: \.neck),
        CalliperField(letter: "S", title: "Schulterdurchmesser", value: \.shoulder),
        CalliperField(letter: "B", title: "Bodendurchmesser", value: \.base),
        CalliperField(letter: "R", title: "Randdurchmesser", value: \.rim),
        CalliperField(letter: "P", title: "Zündhütchen-Durchmesser", value: \.primerDiameter),
        CalliperField(letter: "H", title: "Schulterlänge", value: \.shoulderLength),
        CalliperField(letter: "L", title: "Hülsenlänge", value: \.caseLength),
        CalliperField(letter: "OAL", title: "Gesamtlänge", value: \.overallLength),
    ]

    /// A calliper value with its unit, «9.95 mm»; a dash until measured.
    private func measured(_ field: CalliperField) -> some View {
        LabeledContent {
            HStack(spacing: 4) {
                TextField("–", value: measurements[dynamicMember: field.value], format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
                Text(verbatim: LengthUnit.metric.symbol).foregroundStyle(.secondary)
            }
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: field.letter)
                    .font(.footnote.bold())
                    .foregroundStyle(Color.accentColor)
                    .frame(minWidth: 30, alignment: .leading)
                    .accessibilityHidden(true)
                // Shrinks rather than cut off «Zündhütchen-Durchmesser» beside the letter; the row doesn't grow for a second line.
                Text(field.title).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private func share() {
        do {
            shared = SharedFile(url: try CaptureStore.zip(capture.url))
        } catch {
            status = String(format: "ZIP fehlgeschlagen: %@".loc, error.localizedDescription)
        }
    }
}

/// The camera for a series: every photo is saved straight away, the screen stays open. Where the
/// device has a telephoto or ultra wide camera, a picker switches to it; those take no depth.
private struct TrainingCameraView: View {
    let capture: SavedCapture
    @State private var choice: CameraChoice = LiDARCamera.choices.first ?? .lidar
    @State private var saved = 0

    var body: some View {
        // A new camera object per choice: the session is configured once, for one device, format and zoom.
        TrainingCameraSession(capture: capture, choice: choice, saved: $saved)
            .id(choice)
            .overlay(alignment: .top) {
                if LiDARCamera.choices.count > 1 {
                    // Side by side, as before the menu (Raven 2026-11-09); a menu only when they would not fit.
                    Group {
                        if LiDARCamera.choices.count <= 3 {
                            cameraPicker.pickerStyle(.segmented)
                        } else {
                            cameraPicker.pickerStyle(.menu)
                        }
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 72)
                    .padding(.horizontal, 24)
                }
            }
    }

    private var cameraPicker: some View {
        Picker(selection: $choice) {
            ForEach(LiDARCamera.choices) { Text($0.title.loc).tag($0) }
        } label: {
            Text("Kamera")
        }
    }
}

private struct TrainingCameraSession: View {
    let capture: SavedCapture
    @StateObject private var camera: LiDARCamera
    @Binding private var saved: Int
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var failure: String?

    init(capture: SavedCapture, choice: CameraChoice, saved: Binding<Int>) {
        self.capture = capture
        _camera = StateObject(wrappedValue: LiDARCamera(choice: choice))
        _saved = saved
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(camera: camera, gravity: .resizeAspect).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("\(capture.package.calibreName) · \(saved) neue Fotos")
                    .font(.headline)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                if let failure { Text(verbatim: failure).font(.footnote).foregroundStyle(.red) }
                if camera.accessDenied {
                    CameraDeniedHint().font(.footnote).padding(10).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                Spacer()
                // Without depth the camera cannot say how far it is: its closest focus tells how close to go (Raven 2026-11-09).
                if !camera.hasDepth, let mm = camera.minimumFocusDistance {
                    Text(String(format: "Scharf ab %lld cm".loc, Int((Double(mm) / 10).rounded(.up))))
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                // The distance guide with every camera, «Keine Tiefe gemessen» included (Raven, PR 183).
                Label(camera.guidance.title.loc, systemImage: camera.guidance == .ready ? "checkmark.circle.fill" : "ruler")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(camera.guidance == .ready ? Color.green.opacity(0.85) : Color.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
                HStack {
                    Button { dismiss() } label: { Text("Fertig").cameraPill() }
                    Spacer()
                    Button(action: shoot) {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 72, height: 72)
                            .overlay(Circle().fill(saving ? Color.gray : Color.white).padding(8))
                    }
                    .disabled(saving || !camera.isRunning)
                    Spacer()
                    Text("Fertig").cameraPill().hidden()
                }
                .padding(.horizontal, 24)
            }
            .padding()
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private func shoot() {
        saving = true
        camera.captureRaw { photo, moment in
            Task { @MainActor in
                do {
                    try await TrainingRecorder.save(photo, at: moment, mode: capture.package.scanMode, in: capture.url)
                    saved += 1
                    failure = nil
                } catch {
                    failure = String(format: "Nicht gespeichert: %@".loc, String(describing: error))
                }
                saving = false
            }
        }
    }
}

private struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system share sheet for a file (AirDrop to the Mac, Files, Mail).
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The country of a series: every present-day country with its flag and the former states, searchable;
/// the first row clears the choice.
struct CountryPickerView: View {
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            if query.isEmpty {
                row(title: "–", chosen: selection == nil) { selection = nil }
            }
            ForEach(Countries.matching(query)) { country in
                row(title: country.title, chosen: country.code == selection) { selection = country.code }
            }
        }
        .searchable(text: $query, prompt: Text("Land suchen"))
        .navigationTitle("Land")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(title: String, chosen: Bool, pick: @escaping () -> Void) -> some View {
        Button {
            pick()
            dismiss()
        } label: {
            HStack {
                Text(verbatim: title).foregroundStyle(.primary)
                Spacer()
                if chosen { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
}
