import PhotosUI
import SwiftUI

// Hidden developer screens for recording training data (see `TrainingCapture`). German only and
// with verbatim texts: they are not part of the app users see, and go away with the feature.

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
                    Label { Text(verbatim: "Neue Aufnahmeserie") } icon: { Image(systemName: "plus.circle") }
                }
            } footer: {
                Text(verbatim: """
                Wähle das Kaliber, das du fotografierst, und mache mehrere Fotos davon. Gespeichert werden das Foto, \
                die LiDAR-Tiefe, die Kameradaten und die Vision-Maske. Teile die Serie als ZIP, sie kommt in die Tests.
                """)
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
                    Text(verbatim: "Gespeichert")
                }
            }
        }
        .navigationTitle(Text(verbatim: "Trainingsdaten"))
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
            Text(verbatim: "\(capture.package.scanMode == .emptyCase ? "Leere Hülse" : "Patrone") · \(capture.shotCount) Fotos · "
                 + capture.package.created.formatted(date: .abbreviated, time: .shortened))
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
                        Text(verbatim: calibre?.name ?? "Wählen")
                    } label: {
                        Text(verbatim: "Kaliber")
                    }
                }
                Picker(selection: $mode) {
                    ForEach(TrainingCapture.parts) { part in
                        Text(verbatim: part == .emptyCase ? "Leere Hülse" : "Patrone").tag(part)
                    }
                } label: {
                    Text(verbatim: "Im Bild")
                }
                .pickerStyle(.segmented)
                TextField(text: $note, prompt: Text(verbatim: "z. B. Holztisch, Tageslicht")) { Text(verbatim: "Notiz") }
            } footer: {
                Text(verbatim: "Alle Fotos dieser Serie zeigen dieses Kaliber.")
            }
        }
        .navigationTitle(Text(verbatim: "Neue Serie"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Text(verbatim: "Abbrechen") }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    if let calibre { onStart(TrainingRecorder.package(calibre: calibre.id, mode: mode, note: note)) }
                } label: {
                    Text(verbatim: "Starten")
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
        .navigationTitle(Text(verbatim: "Kaliber"))
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
                        Label { Text(verbatim: "Fotografieren") } icon: { Image(systemName: "camera") }
                    }
                }
                PhotosPicker(selection: $libraryItems, matching: .images, preferredItemEncoding: .current) {
                    Label { Text(verbatim: "Aus Fotos hinzufügen (ohne Tiefe)") } icon: { Image(systemName: "photo") }
                }
                Button(action: share) {
                    Label { Text(verbatim: "Als ZIP teilen") } icon: { Image(systemName: "square.and.arrow.up") }
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
                Text(verbatim: "\(shots.count) Fotos")
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
                status = "\(saved) von \(items.count) Fotos hinzugefügt"
                libraryItems = []
                reload()
            }
        }
    }

    /// E.g. "03  LiDAR 251 mm  3.02  9x19 mm".
    static func summary(_ name: String, _ shot: CaptureShot) -> String {
        let depth = shot.scale.map { String(format: "LiDAR %.0f mm", $0.tableDistance) } ?? (shot.depth == nil ? "ohne Tiefe" : "Tiefe relativ")
        let aspect = shot.analysis?.aspect.map { String(format: "%.2f", $0) } ?? "–"
        return "\(name)  \(depth)  \(aspect)  \(shot.analysis?.matches.first ?? "kein Treffer")"
    }

    private func reload() { shots = capture.shots }

    private func share() {
        do {
            shared = SharedFile(url: try CaptureStore.zip(capture.url))
        } catch {
            status = "ZIP fehlgeschlagen: \(error.localizedDescription)"
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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session).ignoresSafeArea()
            VStack(spacing: 12) {
                Text(verbatim: "\(CartridgeCatalog.cartridge(id: capture.package.calibre)?.name ?? capture.package.calibre) · \(saved) neue Fotos")
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
                    Button { dismiss() } label: { Text(verbatim: "Fertig") }
                        .foregroundStyle(.white)
                    Spacer()
                    Button(action: shoot) {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 72, height: 72)
                            .overlay(Circle().fill(saving ? Color.gray : Color.white).padding(8))
                    }
                    .disabled(saving || !camera.isRunning)
                    Spacer()
                    Text(verbatim: "Fertig").hidden()
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
        camera.captureRaw { photo in
            Task { @MainActor in
                do {
                    try await TrainingRecorder.save(photo, gravity: camera.gravity, tilt: camera.tilt,
                                                    mode: capture.package.scanMode, in: capture.url)
                    saved += 1
                    failure = nil
                } catch {
                    failure = "Nicht gespeichert: \(error)"
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
