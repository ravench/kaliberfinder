// The evaluation tool (see README.md): the phone's photo analysis on every shot of the training
// data, with a Markdown report of how often the right calibre comes first. macOS only: it needs
// Vision's foreground mask, which the simulator lacks. Built by build.sh.
import CoreGraphics
import Foundation
import ImageIO

let usage = """
usage: evaluate [shots] [--holdout] [--mac-vision] [--one-look] [--json FILE] [--compare FILE] [--report FILE]

  shots         the training repo (its captures/ and splits.json), or a folder of capture packages
                such as KaliberfinderTests/Golden; default $KALIBERFINDER_TRAINING or ../kaliberfinder-training
  --holdout     the held-back packages of splits.json instead of the tuning shots
  --mac-vision  Vision on the Mac also for shots where the phone's Vision found nothing
  --one-look    without the second look at the cartridge cut out of the full-size photo
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
    var oneLook = false
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
            case "--one-look": oneLook = true
            case "--json": json = file()
            case "--compare": compare = file()
            case "--report": report = file()
            case let path where !path.hasPrefix("-"): shots = URL(fileURLWithPath: path)
            default: fail(usage)
            }
        }
    }
}

/// The photo upright, at most `maxSide` pixels long: as the phone analyses it (`PhotoAnalyzer.maxDimension`),
/// or at full size for the second look.
func uprightPhoto(_ url: URL, maxSide: Int = Int(PhotoAnalyzer.maxDimension)) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let thumbnail: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: maxSide]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail as CFDictionary)
}

/// The part `region` (fractions) of the full-size photo `full`, scaled to at most `PhotoAnalyzer.maxDimension`.
func part(_ full: CGImage, region: CGRect) -> CGImage? {
    let pixels = CGRect(x: region.minX * Double(full.width), y: region.minY * Double(full.height),
                        width: region.width * Double(full.width), height: region.height * Double(full.height)).integral
    guard let crop = full.cropping(to: pixels) else { return nil }
    let factor = min(1, Double(PhotoAnalyzer.maxDimension) / Double(max(crop.width, crop.height)))
    guard factor < 1 else { return crop }
    let width = Int((Double(crop.width) * factor).rounded()), height = Int((Double(crop.height) * factor).rounded())
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    context.interpolationQuality = .high
    context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

/// How the analysis looked at the shot a second time.
enum SecondLook { case none, again, picked }

/// The phone's second look (`PhotoAnalyzer.secondLook`): the cartridge cut out of the full-size photo
/// and analysed again, with Vision on the Mac (the phone's mask of it isn't stored). Where several
/// cartridges compete, the phone waits for the user to pick one and looks at that one alone
/// (`focusingOn:`): here the one the first look measured is picked. Nil when the first look found nothing
/// to look at again or the second look kept it.
func secondLook(_ first: PhotoAnalysis, photo url: URL) -> (PhotoAnalysis, SecondLook)? {
    let picked = first.hasSeveralObjects ? first.outline.flatMap(PhotoAnalyzer.focusRegion(around:)) : nil
    guard let region = picked ?? PhotoAnalyzer.secondLookRegion(of: first), let full = uprightPhoto(url, maxSide: 1_000_000),
          let image = part(full, region: region) else { return nil }
    let second = PhotoAnalyzer.inPhoto(PhotoAnalyzer.analyzeNow(image), region: region,
                                       photoSize: CGSize(width: full.width, height: full.height))
    if picked != nil { return (second, .picked) }
    let looked = PhotoAnalyzer.secondLook(first, then: second)
    return looked.outline == first.outline ? nil : (looked, .again)
}

/// What the phone does with the shot: its own Vision mask where it stored one, the colour cut-out
/// where its Vision found nothing, and Vision on the Mac for photos it never analysed; then the second
/// look, with Vision on the Mac. Without the photo (the golden set) the mask is replayed with the
/// phone's colour test, as GoldenSetTests does, and there is no second look.
func analyse(_ entry: SavedShot, macVision: Bool, oneLook: Bool) -> (PhotoAnalysis, Evaluation.Source, SecondLook) {
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
        return (analysis, .phone, .none)
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
    let first = PhotoAnalyzer.analysis(of: photo, vision: vision)
    let looked = oneLook ? nil : secondLook(first, photo: photoURL)
    return (looked?.0 ?? first, vision == nil ? .colour : source, looked?.1 ?? .none)
}

// TEMPORARY diagnostic (not for merging): silhouettes of chosen shots as edge points in photo fractions.
func dumpEdges(_ tag: String, _ name: String, _ points: [Point], toPhoto: (Double, Double) -> (Double, Double)) {
    guard points.count >= 50 else { FileHandle.standardError.write(Data("EDGES \(tag) \(name) none\n".utf8)); return }
    let n = Double(points.count)
    let mx = points.reduce(0) { $0 + $1.x } / n, my = points.reduce(0) { $0 + $1.y } / n
    var sxx = 0.0, syy = 0.0, sxy = 0.0
    for p in points { let dx = p.x - mx, dy = p.y - my; sxx += dx * dx; syy += dy * dy; sxy += dx * dy }
    let a = 0.5 * atan2(2 * sxy, sxx - syy), ux = cos(a), uy = sin(a)
    let u = points.map { ($0.x - mx) * ux + ($0.y - my) * uy }, v = points.map { -($0.x - mx) * uy + ($0.y - my) * ux }
    let lo = u.min() ?? 0, hi = u.max() ?? 1, bins = 120
    var minV = [Double](repeating: .infinity, count: bins), maxV = [Double](repeating: -.infinity, count: bins)
    for (pu, pv) in zip(u, v) {
        let i = min(bins - 1, Int((pu - lo) / (hi - lo) * Double(bins)))
        minV[i] = min(minV[i], pv); maxV[i] = max(maxV[i], pv)
    }
    var out: [String] = []
    for i in 0..<bins where maxV[i] >= minV[i] {
        let uc = lo + (Double(i) + 0.5) / Double(bins) * (hi - lo)
        for vv in [minV[i], maxV[i]] {
            let (fx, fy) = toPhoto(mx + uc * ux - vv * uy, my + uc * uy + vv * ux)
            out.append(String(format: "%.5f,%.5f", fx, fy))
        }
    }
    FileHandle.standardError.write(Data("EDGES \(tag) \(name) n \(points.count) \(out.joined(separator: " "))\n".utf8))
}

func diagnose(_ name: String, _ entry: SavedShot) {
    guard name.contains("20261103") || name.hasPrefix("9x19-mm-20261105-224844/0") else { return }
    let url = entry.url.appendingPathComponent(entry.shot.photo)
    guard let photo = uprightPhoto(url), let rgb = PhotoAnalyzer.rgbImage(photo) else { return }
    let w = Double(photo.width), h = Double(photo.height)
    if let colour = ColorSegmenter.best(rgb) {
        dumpEdges("colour1600", name, colour.points) { ($0 / w, $1 / h) }
    }
    if let v = PhotoAnalyzer.visionResult(of: photo) { dumpEdges("vision1600", name, v.points) { ($0 / w, $1 / h) } }
    let first = PhotoAnalyzer.analysis(of: photo, vision: PhotoAnalyzer.visionResult(of: photo))
    guard let region = PhotoAnalyzer.secondLookRegion(of: first), let full = uprightPhoto(url, maxSide: 1_000_000),
          let image = part(full, region: region) else { return }
    let pw = Double(image.width), ph = Double(image.height)
    let map = { (x: Double, y: Double) in (region.minX + x / pw * region.width, region.minY + y / ph * region.height) }
    if let v = PhotoAnalyzer.visionResult(of: image) { dumpEdges("vision2", name, v.points, toPhoto: map) }
    if let prgb = PhotoAnalyzer.rgbImage(image), let colour = ColorSegmenter.best(prgb) { dumpEdges("colour2", name, colour.points, toPhoto: map) }
    FileHandle.standardError.write(Data("REGION \(name) \(region.minX) \(region.minY) \(region.width) \(region.height) part \(image.width)x\(image.height) full \(full.width)x\(full.height)\n".utf8))
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
var secondLooks = 0, picks = 0
for package in packages {
    for entry in package.shots {
        let name = "\(package.url.lastPathComponent)/\(entry.url.lastPathComponent)"
        let (analysis, source, looked) = analyse(entry, macVision: options.macVision, oneLook: options.oneLook)
        diagnose(name, entry)
        if let a = analysis.shapeAtAxis(depth: entry.shot.scale?.depthScale) {
            let size = (try? analysis.size(depth: entry.shot.scale?.depthScale).get()).map { String(format: "%.3f %.3f %.3f %.3f", $0.length, $0.diameter, $0.lengthError, $0.diameterError) } ?? "nil"
            FileHandle.standardError.write(Data("SHAPE \(name) aspect \(a.aspect) share \(a.caseShare.map { String($0) } ?? "nil") brass \(analysis.isBrass) size \(size) widths \(a.widths.map { String(format: "%.4f", $0) }.joined(separator: ","))\n".utf8))
        }
        let shot = Evaluation.shot(name, analysis: analysis, depth: entry.shot.scale?.depthScale, package: package.package, source: source)
        if looked == .again { secondLooks += 1 }
        if looked == .picked { picks += 1 }
        let look = looked == .none ? "" : looked == .picked ? ", picked" : ", second look"
        let r = shot.result, rows = [r.row, r.rowObsolete, r.rowAll].map { $0.map(String.init) ?? "–" }.joined(separator: "/")
        // The case's share of the length where the colours show the mouth, and the calibre's.
        let calibre = CartridgeCatalog.cartridge(id: shot.calibre).map { $0.dimensions.caseLength / $0.outline.height } ?? .nan
        let share = analysis.contour?.mouth.map { String(format: ", case %.3f of %.3f", 1 - $0, calibre) } ?? ""
        FileHandle.standardError.write(Data("\(name) rows \(rows) rank \(r.rank.map(String.init) ?? "–") first \(shot.first ?? "–") (\(source.rawValue)\(look)\(share))\n".utf8))
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
let looks = options.oneLook ? "one look only"
    : "second look on \(secondLooks); first of several cartridges picked on \(picks)"
let report = Evaluation.report(shots, title: "Matching on \(shots.count) \(kind) shots (\(looks))", before: before)
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
