// Diagnostic: the app's photo measurement with Vision's real foreground mask, on macOS (the
// simulator has no Vision foreground mask). Mirrors PhotoAnalyzer.silhouette.
import CoreVideo
import Foundation
import ImageIO
import Vision

let catalogue = CartridgeCatalog.matchable(includeObsolete: false,
                                           in: CartridgeCatalog.load(from: Bundle(path: FileManager.default.currentDirectoryPath + "/Kaliberfinder/Resources")!))

func pixels(_ buffer: CVPixelBuffer, step: Int, _ body: (Int, Int, Float) -> Void) {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let base = CVPixelBufferGetBaseAddress(buffer)!
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    let isFloat = CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float
    for y in stride(from: 0, to: height, by: step) {
        let row = base.advanced(by: y * rowBytes)
        for x in stride(from: 0, to: width, by: step) {
            body(x, y, isFloat ? row.load(fromByteOffset: x * 4, as: Float.self) : Float(row.load(fromByteOffset: x, as: UInt8.self)))
        }
    }
}

func describe(_ label: String, _ points: [Point], step: Int, width: Int, height: Int) {
    guard let m = ShapeMatcher.measureWithLength(points, pixelSize: Double(step)) else { print("  \(label): no shape"); return }
    let f = m.shape.features
    let w = m.shape.widths.map { String(format: "%.2f", $0) }
    let top = Matcher.rank(shape: m.shape, cartridges: catalogue, limit: 3).map { "\($0.cartridge.id) \(String(format: "%.2f", $0.score))" }
    let box = ShapeMatcher.orientedBox(points, pixelSize: Double(step))?.map { String(format: "(%.2f,%.2f)", $0.x / Double(width), $0.y / Double(height)) } ?? []
    print("  \(label): aspect \(String(format: "%.2f", m.shape.aspect)) len \(Int(m.length)) part \(ScanMode.auto.part(for: m.shape)) flat \(f?.isFlatEnd ?? false) rim \(String(format: "%.2f", f?.rim ?? 0)) mouth \(String(format: "%.2f", f?.mouth ?? 0))")
    print("    widths \(w.prefix(5).joined(separator: " ")) … \(w.suffix(5).joined(separator: " "))")
    print("    top \(top.joined(separator: " | ")) box \(box.joined(separator: " "))")
}

for path in CommandLine.arguments.dropFirst() {
    let name = (path as NSString).lastPathComponent
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary) else { continue }
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    let request = VNGenerateForegroundInstanceMaskRequest()
    guard (try? handler.perform([request])) != nil, let observation = request.results?.first else { print("VCHECK \(name): no Vision result"); continue }
    let labels = observation.instanceMask
    var map: [Int] = []
    pixels(labels, step: 1) { _, _, v in map.append(Int(v.rounded())) }
    let lw = CVPixelBufferGetWidth(labels), lh = CVPixelBufferGetHeight(labels)
    let instances = SubjectPicker.joiningParts(SubjectPicker.instances(labels: map, width: lw), labels: map, width: lw, height: lh)
    print("VCHECK \(name) \(image.width)x\(image.height) labels \(lw)x\(lh) instances \(instances.map { "\(Array($0.labels)):\($0.count)@\($0.bounds.x0),\($0.bounds.y0)-\($0.bounds.x1),\($0.bounds.y1)" })")
    guard let picked = SubjectPicker.pickInstance(instances, width: lw, height: lh),
          let mask = try? observation.generateScaledMaskForImage(forInstances: picked.labels, from: handler) else { print("  picked none"); continue }
    let scale = Double(CVPixelBufferGetWidth(mask) * CVPixelBufferGetHeight(mask)) / Double(lw * lh)
    for step in [max(1, Int((Double(CVPixelBufferGetWidth(mask) * CVPixelBufferGetHeight(mask)) / 40_000).squareRoot().rounded(.up))),
                 max(1, Int((Double(picked.count) * scale / 40_000).squareRoot().rounded(.up)))] {
        var points: [Point] = []
        pixels(mask, step: step) { x, y, v in if v > 0.5 { points.append(Point(x: Double(x), y: Double(y))) } }
        print("  picked \(Array(picked.labels)) points \(points.count) step \(step)")
        describe("raw    ", points, step: step, width: image.width, height: image.height)
        describe("trimmed", ShapeMatcher.mirrorTrimmed(points, pixelSize: Double(step)), step: step, width: image.width, height: image.height)
    }
}
