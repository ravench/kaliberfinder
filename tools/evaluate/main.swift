// The evaluation tool (see README.md): the phone's photo analysis on every shot of the training
// data, with a Markdown report of how often the right calibre comes first. macOS only: it needs
// Vision's foreground mask, which the simulator lacks. Built by build.sh.
import CoreGraphics
import Foundation
import ImageIO

let usage = """
usage: evaluate [shots] [--holdout] [--mac-vision] [--json FILE] [--compare FILE] [--report FILE]

  shots         the training repo (its captures/ and splits.json), or a folder of capture packages
                such as KaliberfinderTests/Golden; default $KALIBERFINDER_TRAINING or ../kaliberfinder-training
  --holdout     the held-back packages of splits.json instead of the tuning shots
  --mac-vision  Vision on the Mac also for shots where the phone's Vision found nothing
  --json FILE   writes every shot's result, for --compare in a later run
  --compare FILE  compares with such an earlier run
  --report FILE writes the report there too (it always goes to the standard output)
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

struct Options {
    var shots: URL
    var holdout = false
    var macVision = false
    var json: URL?
    var compare: URL?
    var report: URL?

    init(_ arguments: [String]) {
        let environment = ProcessInfo.processInfo.environment["KALIBERFINDER_TRAINING"]
        shots = URL(fileURLWithPath: environment ?? "../kaliberfinder-training")
        var rest = arguments[...]
        func file() -> URL {
            guard let path = rest.popFirst() else { fail(usage) }
            return URL(fileURLWithPath: path)
        }
        while let argument = rest.popFirst() {
            switch argument {
            case "--holdout": holdout = true
            case "--mac-vision": macVision = true
            case "--json": json = file()
            case "--compare": compare = file()
            case "--report": report = file()
            case let path where !path.hasPrefix("-"): shots = URL(fileURLWithPath: path)
            default: fail(usage)
            }
        }
    }
}

/// The photo upright and scaled down as the phone analyses it (`PhotoAnalyzer.maxDimension`).
func uprightPhoto(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let thumbnail: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: Int(PhotoAnalyzer.maxDimension)]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail as CFDictionary)
}

/// What the phone does with the shot: its own Vision mask where it stored one, the colour cut-out
/// where its Vision found nothing, and Vision on the Mac for photos it never analysed. Without the
/// photo (the golden set) the mask is replayed with the phone's colour test, as GoldenSetTests does.
func analyse(_ entry: SavedShot, macVision: Bool) -> (PhotoAnalysis, Evaluation.Source) {
    let shot = entry.shot, path = entry.url.path
    let labels = CaptureStore.mask(of: shot, at: entry.url)
    if shot.mask != nil && labels == nil { fail("\(path): Vision mask unreadable (is Git LFS installed?)") }
    let photoURL = entry.url.appendingPathComponent(shot.photo)
    guard FileManager.default.fileExists(atPath: photoURL.path) else {
        guard let labels, let info = shot.mask, let width = info.imageWidth, let height = info.imageHeight else {
            fail("\(path): neither a photo nor a mask")
        }
        let analysis = PhotoAnalyzer.analyze(instanceLabels: labels, mask: (info.width, info.height), image: (width, height),
                                             isBrass: shot.analysis?.isBrass ?? true)
        return (analysis, .phone)
    }
    guard let photo = uprightPhoto(photoURL) else { fail("\(path): photo unreadable (is Git LFS installed?)") }
    let vision: PhotoAnalyzer.VisionResult?, source: Evaluation.Source
    if let labels, let info = shot.mask {
        vision = PhotoAnalyzer.visionResult(instanceLabels: labels, mask: (info.width, info.height), image: (photo.width, photo.height))
        source = .phone
    } else if shot.analysis != nil && !macVision {
        vision = nil
        source = .colour
    } else {
        vision = PhotoAnalyzer.visionResult(of: photo)
        source = .mac
    }
    return (PhotoAnalyzer.analysis(of: photo, vision: vision), vision == nil ? .colour : source)
}

let options = Options(Array(CommandLine.arguments.dropFirst()))
guard !CartridgeCatalog.all.isEmpty else { fail("Cartridges.json is missing next to the tool: build it with tools/evaluate/build.sh") }
let captures = options.shots.appendingPathComponent("captures")
let root = FileManager.default.fileExists(atPath: captures.path) ? captures : options.shots
let splits = (try? Data(contentsOf: options.shots.appendingPathComponent("splits.json")))
    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
let holdout = Set(splits?["holdout"] as? [String] ?? [])
let packages = CaptureStore(root: root).packages()
    .filter { holdout.contains($0.url.lastPathComponent) == options.holdout }
    .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
guard !packages.isEmpty else { fail("no capture packages in \(root.path)\n\n\(usage)") }

let started = Date()
var shots: [Evaluation.Shot] = []
for package in packages {
    for entry in package.shots {
        let name = "\(package.url.lastPathComponent)/\(entry.url.lastPathComponent)"
        let (analysis, source) = analyse(entry, macVision: options.macVision)
        let shot = Evaluation.shot(name, analysis: analysis, depth: entry.shot.scale?.depthScale, package: package.package, source: source)
        FileHandle.standardError.write(Data("\(name) rank \(shot.result.rank.map(String.init) ?? "–") first \(shot.first ?? "–") (\(source.rawValue))\n".utf8))
        shots.append(shot)
    }
}
FileHandle.standardError.write(Data(String(format: "%d shots in %.0f s\n", shots.count, Date().timeIntervalSince(started)).utf8))

let before = options.compare.map { url -> Evaluation.Baseline in
    guard let data = try? Data(contentsOf: url), let baseline = try? TrainingCapture.decoder.decode(Evaluation.Baseline.self, from: data)
    else { fail("cannot read \(url.path)") }
    return baseline
}
let kind = options.holdout ? "held-back" : "tuning"
let report = Evaluation.report(shots, title: "Matching on \(shots.count) \(kind) shots", before: before)
print(report)
do {
    if let url = options.report { try Data(report.utf8).write(to: url) }
    if let url = options.json {
        let results = Dictionary(uniqueKeysWithValues: shots.map { ($0.name, $0.result) })
        try TrainingCapture.encoder.encode(Evaluation.Baseline(results)).write(to: url)
    }
} catch {
    fail("cannot write: \(error)")
}
