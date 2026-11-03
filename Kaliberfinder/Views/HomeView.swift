import PhotosUI
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var scale: ScaleModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var photo: PickedPhoto?
    @AppStorage(LengthUnit.storageKey) private var unit: LengthUnit = .metric

    var body: some View {
        List {
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
                Text("Patrone seitlich auf einen hellen Untergrund legen und von oben fotografieren. Für die Aufschrift danach den Boden fotografieren.")
            }
            Section {
                NavigationLink { MeasureView() } label: {
                    Label("Masse eingeben", systemImage: "ruler")
                }
                NavigationLink { CatalogView(selecting: true) } label: {
                    Label("Kaliber auswählen und vergleichen", systemImage: "square.split.2x1")
                }
                NavigationLink { CatalogView() } label: {
                    Label("Alle Kaliber", systemImage: "list.bullet")
                }
            } header: {
                Text("Ohne Foto")
            }
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
            Section("Einheiten") {
                UnitPicker(unit: $unit)
            }
            Section {
                Text(verbatim: "© 2026 Simon Giotta · PolyForm Noncommercial 1.0.0")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Kaliberfinder")
        .navigationDestination(item: $photo) {
            // New identity per photo, so a photo shared while the matches are open is analysed afresh.
            MatchesView(photo: $0.image, depth: $0.depth, base: $0.base).id($0.id)
        }
        // Photos shared from other apps: the extension opens the app with this URL. If iOS did not
        // let it, they wait in the inbox until the app comes to the front.
        .onOpenURL { if SharedInbox.isOpenURL($0) { takeSharedPhotos() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { takeSharedPhotos() } }
        .task { takeSharedPhotos() }
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

    private func takeSharedPhotos() {
        let images = (SharedInbox.shared?.take() ?? []).compactMap(UIImage.init(data:))
        guard let first = images.first else { return }
        showCamera = false
        photo = PickedPhoto(image: first, base: images.dropFirst().first)
    }
}
