import PhotosUI
import SwiftUI

/// The home screen's actions and switches, top to bottom. The rest of the settings are on
/// `SettingsView`, opened as a sheet by the gear button in the navigation bar.
enum HomeSection: CaseIterable {
    case photo, withoutPhoto, recognition
}

struct HomeView: View {
    @EnvironmentObject private var scale: ScaleModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCamera = false
    @State private var showSettings = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var photo: PickedPhoto?
    @AppStorage(CartridgeCatalog.includeObsoleteKey) private var includeObsolete = false
    @AppStorage(CartridgeCatalog.includeRareKey) private var includeRare = false
    @State private var fit = LargeTitleFit()
    private let canTakePhoto: Bool

    /// `canTakePhoto`: tests lay out a phone's home screen on the simulator, which has no camera.
    init(canTakePhoto: Bool = LiDARCamera.isAvailable || CameraPicker.isAvailable) {
        self.canTakePhoto = canTakePhoto
    }

    var body: some View {
        List {
            ForEach(HomeSection.allCases, id: \.self) { section in
                switch section {
                case .photo:
                    Section {
                        if canTakePhoto {
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
        }
        // Scrolls only when the screen is too small for it under the large title: otherwise a drag just
        // stretches and shrinks the title. `.basedOnSize` alone looks again once the title has collapsed:
        // on a phone a little smaller than the 17 Pro the list then fits and stops scrolling, title stuck small.
        .scrollBounceBehavior(fit.fits ? .basedOnSize : .always)
        .measuring($fit)
        .navigationTitle("Kaliberfinder")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Label("Einstellungen", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
                .environmentObject(scale)
        }
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
        guard let image = (SharedInbox.shared?.take() ?? []).lazy.compactMap(UIImage.init(data:)).first ?? Self.takeTourPhoto() else { return }
        showCamera = false
        photo = PickedPhoto(image: image)
    }

    /// For the PR screens tour only: the photo file given as `-screenTourPhoto <path>` at launch, once.
    private static var tourPhotoTaken = false
    private static func takeTourPhoto() -> UIImage? {
        guard !tourPhotoTaken, let path = UserDefaults.standard.string(forKey: "screenTourPhoto") else { return nil }
        tourPhotoTaken = true
        return UIImage(contentsOfFile: path)
    }
}

/// Whether a list fits under its large title, read only while the title is large (the largest top inset
/// seen so far): collapsed, the title frees room, and the list may fit where it did not before.
struct LargeTitleFit: Equatable {
    private(set) var fits = false
    private var largestInset = 0.0

    /// One scroll geometry: the top inset, and whether the content fits between the insets.
    struct Reading: Equatable {
        var insetTop: Double
        var fits: Bool
    }

    mutating func read(_ now: Reading) {
        largestInset = max(largestInset, now.insetTop)
        if now.insetTop >= largestInset - 1 { fits = now.fits }
    }
}

extension View {
    /// Feeds the scroll geometry to `fit`. iOS 17 has no scroll geometry: `fit` stays as it is.
    @ViewBuilder func measuring(_ fit: Binding<LargeTitleFit>) -> some View {
        if #available(iOS 18, *) {
            onScrollGeometryChange(for: LargeTitleFit.Reading.self) { g in
                LargeTitleFit.Reading(insetTop: g.contentInsets.top,
                                      fits: g.contentSize.height <= g.containerSize.height - g.contentInsets.top - g.contentInsets.bottom)
            } action: { _, now in fit.wrappedValue.read(now) }
        } else {
            self
        }
    }
}
