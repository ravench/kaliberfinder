import UIKit
import UniformTypeIdentifiers

/// "Kaliberfinder" in the share sheet: hands the shared photos to the app and opens it on the
/// matches. Nothing is analysed here; share extensions get little memory.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let spinner = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        spinner.startAnimating()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await handOver() }
    }

    private func handOver() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        var photos: [Data] = []
        for provider in providers.prefix(SharedInbox.maxPhotos) {
            if let data = await Self.imageData(from: provider) { photos.append(data) }
        }
        guard !photos.isEmpty, let inbox = SharedInbox.shared, (try? inbox.put(photos)) != nil else {
            show(SharedInbox.failedText)
            return
        }
        if openApp(SharedInbox.openURL) {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            // The app takes the photos the next time it comes to the front.
            show(SharedInbox.openAppText)
        }
    }

    private static func imageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// Extensions have no API to open their app; the host's UIApplication in the responder chain can.
    /// Called through the runtime because `open(_:options:)` is marked unavailable in extensions.
    private func openApp(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication, application.responds(to: selector) {
                typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let open = unsafeBitCast(application.method(for: selector), to: Open.self)
                open(application, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = current.next
        }
        return false
    }

    private func show(_ message: String) {
        spinner.stopAnimating()
        let label = UILabel()
        label.text = message
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .body)
        let done = UIButton(configuration: .borderedProminent(), primaryAction: UIAction(title: SharedInbox.doneText) { [weak self] _ in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        let stack = UIStackView(arrangedSubviews: [label, done])
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
    }
}
