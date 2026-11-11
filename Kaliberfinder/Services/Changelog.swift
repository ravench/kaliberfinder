import Foundation

/// The release notes of a TestFlight build, written into the bundle by CI (tools/changelog.py) and
/// shown the first time the build is opened (`WhatsNewView`). Development builds carry none.
struct Changelog: Decodable {
    /// Bullet points by language (de, en, fr, it).
    var notes: [String: [String]]

    /// UserDefaults key: the build (CFBundleVersion) whose notes were shown.
    static let shownBuildKey = "changelogShownBuild"

    static func load(from bundle: Bundle = .main) -> Changelog? {
        // The PR screens tour brings a file of its own (-screenTourChangelog <path>).
        let url = UserDefaults.standard.string(forKey: "screenTourChangelog").map { URL(fileURLWithPath: $0) }
            ?? bundle.url(forResource: "Changelog", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Changelog.self, from: data)
    }

    /// The bullets in `language`, German (the source language) when it has none; nil without any.
    func bullets(language: String) -> [String]? {
        [notes[language], notes["de"]].compactMap { $0 }.first { !$0.isEmpty }
    }

    /// The notes to show at this start: those of a build other than the one shown last. Marks `build` as shown.
    /// A fresh install shows none: someone who just got the app from the App Store has nothing to compare with.
    static func toShow(build: String, language: String, defaults: UserDefaults = .standard, changelog: Changelog? = load()) -> [String]? {
        let shown = defaults.string(forKey: shownBuildKey)
        guard shown != build else { return nil }
        defaults.set(build, forKey: shownBuildKey)
        return shown == nil ? nil : changelog?.bullets(language: language)
    }
}
