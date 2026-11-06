import PhotosUI
import SwiftUI

// Hidden developer screens for recording training data (see `TrainingCapture`). Reached by
// tapping the copyright line in Settings five times; translated like the rest of the app.

/// The saved series and a button for a new one.
struct TrainingCaptureView: View {
    @State private var captures: [SavedCapture] = []
    @State private var showNew = false
    @State private var opened: SavedCapture?
    private let store = CaptureStore.standard

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
                        NavigationLink(value: capture) { TrainingCaptureRow(capture: capture) }
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
        .navigationDestination(for: SavedCapture.self) { TrainingPackageView(capture: $0) }
        .navigationDestination(item: $opened) { TrainingPackageView(capture: $0) }
        .sheet(isPresented: $showNew) {
            NavigationStack {
                NewTrainingSeriesView { package in
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
            Text(verbatim: CartridgeCatalog.cartridge(id: capture.package.calibre)?.name ?? capture.package.calibre)
            let partName = (capture.package.scanMode == .emptyCase ? "Leere Hülse" : "Patrone").loc
            let dateText = capture.package.created.formatted(date: .abbreviated, time: .shortened)
            Text("\(partName) · \(capture.shotCount) Fotos · \(dateText)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Calibre, part and a note for a new series.
private struct NewTrainingSeriesView: View {
    let onStart: (CapturePackage) -> Void
    @State private var calibre: Cartridge?
    @State private var mode: ScanMode = .cartridge
    @State private var note = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                NavigationLink { TrainingCalibrePicker(selection: $calibre) } label: {
                    LabeledContent {
                        Text(calibre?.name ?? "Wählen".loc)
                    } label: {
                        Text("Fotografiertes Kaliber")
                    }
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
                    if let calibre { onStart(TrainingRecorder.package(calibre: calibre.id, mode: mode, note: note)) }
                } label: {
                    Text("Starten")
                }
                .disabled(calibre == nil)
            }
        }
    }
}

/// Searchable list of all calibres; picking one goes back.
private struct TrainingCalibrePicker: View {
    @Binding var selection: Cartridge?
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(CartridgeCatalog.search(query)) { c in
            Button {
                selection = c
                dismiss()
            } label: {
                HStack {
                    Text(verbatim: c.name).foregroundStyle(.primary)
                    Spacer()
                    if c == selection { Image(systemName: "checkmark") }
                }
            }
        }
        .searchable(text: $query)
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

    var body: some View {
        List {
            Section {
                if LiDARCamera.isAvailable {
                    Button { showCamera = true } label: {
                        Label { Text("Fotografieren") } icon: { Image(systemName: "camera") }
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
                Text(verbatim: CartridgeCatalog.cartridge(id: capture.package.calibre)?.name ?? capture.package.calibre)
            } footer: {
                if !capture.package.note.isEmpty { Text(verbatim: capture.package.note) }
            }
            Section {
                ForEach(shots) { entry in
                    Text(verbatim: Self.summary(entry.url.lastPathComponent, entry.shot)).font(.footnote.monospaced())
                }
            } header: {
                Text("\(shots.count) Fotos")
            }
        }
        .navigationTitle(Text(verbatim: capture.url.lastPathComponent))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
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

    /// E.g. "03  LiDAR 251 mm  3.02  9x19 mm".
    static func summary(_ name: String, _ shot: CaptureShot) -> String {
        let depth = shot.scale.map { String(format: "LiDAR %.0f mm".loc, $0.tableDistance) } ?? (shot.depth == nil ? "ohne Tiefe".loc : "Tiefe relativ".loc)
        let aspect = shot.analysis?.aspect.map { String(format: "%.2f", $0) } ?? "–"
        return "\(name)  \(depth)  \(aspect)  \(shot.analysis?.matches.first ?? "kein Treffer".loc)"
    }

    private func reload() { shots = capture.shots }

    private func share() {
        do {
            shared = SharedFile(url: try CaptureStore.zip(capture.url))
        } catch {
            status = String(format: "ZIP fehlgeschlagen: %@".loc, error.localizedDescription)
        }
    }
}

/// The LiDAR camera for a series: every photo is saved straight away, the screen stays open.
private struct TrainingCameraView: View {
    let capture: SavedCapture
    @StateObject private var camera = LiDARCamera()
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var saved = 0
    @State private var failure: String?

    private var calibreName: String { CartridgeCatalog.cartridge(id: capture.package.calibre)?.name ?? capture.package.calibre }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("\(calibreName) · \(saved) neue Fotos")
                    .font(.headline)
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                if let failure { Text(verbatim: failure).font(.footnote).foregroundStyle(.red) }
                Spacer()
                Label(camera.guidance.title.loc, systemImage: camera.guidance == .ready ? "checkmark.circle.fill" : "ruler")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(camera.guidance == .ready ? Color.green.opacity(0.85) : Color.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
                HStack {
                    Button("Fertig") { dismiss() }
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: shoot) {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 72, height: 72)
                            .overlay(Circle().fill(saving ? Color.gray : Color.white).padding(8))
                    }
                    .disabled(saving || !camera.isRunning)
                    Spacer()
                    Text("Fertig").hidden()
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
        camera.captureRaw { photo, focus in
            Task { @MainActor in
                do {
                    try await TrainingRecorder.save(photo, gravity: camera.gravity, tilt: camera.tilt, focus: focus,
                                                    mode: capture.package.scanMode, in: capture.url)
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
