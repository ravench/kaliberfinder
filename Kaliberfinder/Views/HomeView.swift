import PhotosUI
import SwiftUI

/// The home screen's settings and actions, top to bottom.
enum HomeSection: CaseIterable {
    case photo, withoutPhoto, recognition, units, realSize
}

struct HomeView: View {
    @EnvironmentObject private var scale: ScaleModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var photo: PickedPhoto?
    @AppStorage(LengthUnit.storageKey) private var unit: LengthUnit = .metric
    @AppStorage(CartridgeCatalog.includeObsoleteKey) private var includeObsolete = false
    @AppStorage(CartridgeCatalog.includeRareKey) private var includeRare = false
    /// Hidden developer switch: five taps on the copyright line (`TrainingCapture`).
    @AppStorage(TrainingCapture.enabledKey) private var trainingCapture = false

    var body: some View {
        List {
            ForEach(HomeSection.allCases, id: \.self) { section in
                switch section {
                case .photo:
                    Section {
                        if LiDARCamera.isAvailable || CameraPicker.isAvailable {
                            Button { showCamera = true } label: {
                                Label("Patrone fotografieren", systemImage: "camera")
                            }
                        }
                        PhotosPicker(selection: $libraryItem, matching: .images) {
                            Label("Foto auswählen", systemImage: "photo")
                        }
                    } header: {
                        Text("Patrone erkennen")
                    } footer: {
                        Text("Patrone seitlich auf einen hellen Untergrund legen und von oben fotografieren.")
                }
                case .withoutPhoto:
                Section {
                    NavigationLink { MeasureView() } label: {
                        Label("Masse eingeben", systemImage: "ruler")
                    }
                    NavigationLink { CatalogView(selecting: true) } label: {
                        Label("Auswählen und vergleichen", systemImage: "square.split.2x1")
                    }
                    NavigationLink { CatalogView() } label: {
                        Label("Alle Kaliber", systemImage: "list.bullet")
                    }
                } header: {
                    Text("Ohne Foto")
                }
                case .realSize:
                Section {
                    NavigationLink { CalibrationView() } label: {
                        LabeledContent {
                            Text(verbatim: unit.scaleText(pointsPerMM: scale.pointsPerMM))
                        } label: {
                            Text("Bildschirm")
                            Text(scale.resolution.source.title.loc)
                        }
                    }
                } header: {
                    Text("Originalgrösse")
                } footer: {
                    Text("Bildschirmzoom und Kalibrierung werden berücksichtigt. Prüfe die Grösse einmal mit einer Bankkarte.")
                }
                case .units:
                Section("Einheiten") {
                    UnitPicker(unit: $unit)
                }
                case .recognition:
                Section {
                    Toggle(isOn: $includeObsolete) {
                        Label { Text("Veraltete Kaliber berücksichtigen") } icon: { TagIcon(tag: .obsolete).foregroundStyle(.secondary) }
                    }
                    Toggle(isOn: $includeRare) {
                        Label { Text("Seltene Kaliber berücksichtigen") } icon: { TagIcon(tag: .rare).foregroundStyle(.orange) }
                    }
                } header: {
                    Text("Erkennung")
                } footer: {
                    Text("Gilt für Fotos und «Masse eingeben». Veraltet: nicht mehr regulär hergestellt, z. B. GP 1890 oder Vetterli. Selten: kaum je zu finden, ein Treffer ist meist eine ähnliche Patrone. «Alle Kaliber» zeigt immer alle.")
                }
                }
            }
            if trainingCapture {
                Section {
                    NavigationLink { TrainingCaptureView() } label: {
                        Label { Text(verbatim: "Trainingsdaten aufnehmen") } icon: { Image(systemName: "tray.and.arrow.down") }
                    }
                } footer: {
                    Text(verbatim: "Entwicklerfunktion. Fünfmal auf die Copyright-Zeile tippen blendet sie wieder aus.")
                }
            }
            Section {
                Text(verbatim: "© 2026 Simon Giotta · PolyForm Noncommercial 1.0.0")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .onTapGesture(count: 5) { trainingCapture.toggle() }
            }
        }
        .navigationTitle("Kaliberfinder")
        .navigationDestination(item: $photo) {
            // New identity per photo, so a photo shared while the matches are open is analysed afresh.
            MatchesView(photo: $0.image, depth: $0.depth).id($0.id)
        }
        // Photos shared from other apps: the extension opens the app with this URL. If iOS did not
        // let it, they wait in the inbox until the app comes to the front.
        .onOpenURL { if SharedInbox.isOpenURL($0) { takeSharedPhoto() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { takeSharedPhoto() } }
        .onAppear { takeSharedPhoto() }
        .fullScreenCover(isPresented: $showCamera) {
            if LiDARCamera.isAvailable {
                LiDARCameraView { photo = PickedPhoto(image: $0, depth: $1) }
            } else {
                CameraPicker { photo = PickedPhoto(image: $0) }
                    .ignoresSafeArea()
            }
        }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    photo = PickedPhoto(image: image)
                }
                libraryItem = nil
            }
        }
    }

    /// Opens the matches for a photo shared from another app.
    private func takeSharedPhoto() {
        guard let image = (SharedInbox.shared?.take() ?? []).lazy.compactMap(UIImage.init(data:)).first else { return }
        showCamera = false
        photo = PickedPhoto(image: image)
    }
}
