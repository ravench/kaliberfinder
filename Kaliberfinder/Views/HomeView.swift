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
    /// The release notes of this build, the first time it is opened (`Changelog`).
    @State private var whatsNew: [String] = []
    @State private var showWhatsNew = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var loading = PhotoLoading()
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
                        Text("Seitlich auf hellem Grund, von oben fotografieren.")
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
                }
                }
            }
        }
        // Nothing to tap while a library photo loads: a second pick would start a second load, and a push
        // from another screen would land the matches on top of it.
        .disabled(loading.isLoading)
        .overlay {
            if loading.isLoading {
                ProgressView { Text("Foto wird geladen …") }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        // Scrolls only when the screen is too small for it under the large title: otherwise a drag just
        // stretches and shrinks the title. `.basedOnSize` alone looks again once the title has collapsed:
        // on a phone a little smaller than the 17 Pro the list then fits and stops scrolling, title stuck small.
        .scrollBounceBehavior(fit.fits ? .basedOnSize : .always)
        .measuring($fit)
        .readableWidth()
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
                .pageSized()
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(bullets: whatsNew)
                .pageSized()
        }
        .navigationDestination(item: $photo) {
            // New identity per photo, so a photo shared while the matches are open is analysed afresh.
            MatchesView(photo: $0.image, depth: $0.depth).id($0.id)
        }
        // Photos shared from other apps: the extension opens the app with this URL. If iOS did not
        // let it, they wait in the inbox until the app comes to the front.
        .onOpenURL { if SharedInbox.isOpenURL($0) { takeSharedPhoto() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { takeSharedPhoto() } }
        .onAppear { takeSharedPhoto(); showNotes() }
        .fullScreenCover(isPresented: $showCamera) {
            if LiDARCamera.isAvailable {
                LiDARCameraView { photo = PickedPhoto(image: $0, depth: $1) }
            } else {
                CameraPicker { photo = PickedPhoto(image: $0) }
                    .ignoresSafeArea()
            }
        }
        .onChange(of: libraryItem) { _, item in
            guard let item, loading.start() else { return }
            Task {
                // The data loads off the main thread (from iCloud, perhaps: seconds for a 48 MP photo); `UIImage(data:)`
                // only reads the header, the pixels decode later in `PhotoAnalyzer`, behind the matches' own progress view.
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    photo = PickedPhoto(image: image)
                }
                libraryItem = nil
                loading.finish()
            }
        }
    }

    /// Opens the matches for a photo shared from another app.
    private func takeSharedPhoto() {
        guard let image = (SharedInbox.shared?.take() ?? []).lazy.compactMap(UIImage.init(data:)).first ?? Self.takeTourPhoto() else { return }
        showCamera = false
        photo = PickedPhoto(image: image)
    }

    /// Shows the build's release notes, if it has any and they were not shown yet.
    private func showNotes() {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        guard let notes = Changelog.toShow(build: build, language: Bundle.main.preferredLocalizations.first ?? "de") else { return }
        whatsNew = notes
        showWhatsNew = true
    }

    /// For the PR screens tour only: the photo file given as `-screenTourPhoto <path>` at launch, once.
    private static var tourPhotoTaken = false
    private static func takeTourPhoto() -> UIImage? {
        guard !tourPhotoTaken, let path = UserDefaults.standard.string(forKey: "screenTourPhoto") else { return nil }
        tourPhotoTaken = true
        return UIImage(contentsOfFile: path)
    }
}

/// The wait between the library picker closing and the matches opening, with the home screen on view: the
/// picked photo's data loads meanwhile. The screen shows it is busy and takes no second pick.
struct PhotoLoading: Equatable {
    private(set) var isLoading = false

    /// Starts a load; false while one is running, so a second pick does not start another.
    mutating func start() -> Bool {
        if isLoading { return false }
        isLoading = true
        return true
    }

    /// The load is over: the matches are opening, or it failed.
    mutating func finish() { isLoading = false }
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
