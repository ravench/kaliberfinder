// Diagnostic: Vision's foreground instance masks for photos, as the app gets them on a device
// (photo upright, scaled to 1600 px). Prints one line per photo: a full-size label map
// (0 background, n = instance n) as a base64 PNG.
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

for path in CommandLine.arguments.dropFirst() {
    let name = (path as NSString).lastPathComponent
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary) else {
        print("VMASK \(name) unreadable"); continue
    }
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    let request = VNGenerateForegroundInstanceMaskRequest()
    do { try handler.perform([request]) } catch { print("VMASK \(name) error \(error)"); continue }
    guard let observation = request.results?.first else { print("VMASK \(name) none"); continue }
    let width = image.width, height = image.height
    var map = [UInt8](repeating: 0, count: width * height)
    for instance in observation.allInstances {
        guard let mask = try? observation.generateScaledMaskForImage(forInstances: [instance], from: handler) else { continue }
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        let base = CVPixelBufferGetBaseAddress(mask)!
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)
        let isFloat = CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent32Float
        for y in 0..<min(height, CVPixelBufferGetHeight(mask)) {
            let row = base.advanced(by: y * rowBytes)
            for x in 0..<min(width, CVPixelBufferGetWidth(mask)) {
                let v = isFloat ? row.load(fromByteOffset: x * 4, as: Float.self) : Float(row.load(fromByteOffset: x, as: UInt8.self)) / 255
                if v > 0.5 { map[y * width + x] = UInt8(instance) }
            }
        }
        CVPixelBufferUnlockBaseAddress(mask, .readOnly)
    }
    let provider = CGDataProvider(data: Data(map) as CFData)!
    let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                     space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, cg, nil)
    CGImageDestinationFinalize(dest)
    print("VMASK \(name) \(width)x\(height) n=\(observation.allInstances.count) \((data as Data).base64EncodedString())")
}
