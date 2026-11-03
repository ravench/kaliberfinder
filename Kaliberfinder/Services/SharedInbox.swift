import Foundation

/// Photos shared from other apps (Photos, Files, Messages …) through the share extension.
/// The extension drops them into the App Group folder and opens the app, which takes them out
/// and analyses them like a photo picked in the app. Compiled into the app and the extension.
struct SharedInbox {
    static let appGroup = "group.ch.giotta.kaliberfinder"
    /// Opened by the extension; the app then looks into the inbox.
    static let openURL = URL(string: "kaliberfinder://shared")!
    /// The side photo, then optionally the base photo for the headstamp.
    static let maxPhotos = 2

    /// Shown in the share sheet when iOS did not let the extension open the app.
    static var openAppText: String { "Foto übernommen. Öffne Kaliberfinder, um die Treffer zu sehen.".loc }
    static var failedText: String { "Das Foto konnte nicht übernommen werden.".loc }
    static var doneText: String { "Fertig".loc }

    let directory: URL

    /// The inbox in the App Group folder; nil when the build has no App Group entitlement
    /// (unsigned simulator builds).
    static var shared: SharedInbox? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            .map { SharedInbox(directory: $0.appendingPathComponent("Inbox", isDirectory: true)) }
    }

    static func isOpenURL(_ url: URL) -> Bool {
        url.scheme == openURL.scheme && url.host == openURL.host
    }

    /// Replaces whatever is still waiting with these photos (encoded image files, in order).
    func put(_ photos: [Data]) throws {
        let fileManager = FileManager.default
        // Written next to the inbox first, so the app never sees half of a share.
        let staging = directory.deletingLastPathComponent().appendingPathComponent(directory.lastPathComponent + "-new", isDirectory: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        for (index, data) in photos.prefix(Self.maxPhotos).enumerated() {
            try data.write(to: staging.appendingPathComponent(String(index)))
        }
        try? fileManager.removeItem(at: directory)
        try fileManager.moveItem(at: staging, to: directory)
    }

    /// The waiting photos in the order they were shared, and empties the inbox.
    func take() -> [Data] {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [] }
        let photos = names.compactMap { name in Int(name).map { (index: $0, name: name) } }
            .sorted { $0.index < $1.index }
            .compactMap { try? Data(contentsOf: directory.appendingPathComponent($0.name)) }
        try? fileManager.removeItem(at: directory)
        return photos
    }
}
