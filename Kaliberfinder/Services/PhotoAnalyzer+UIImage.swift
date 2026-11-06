import UIKit

/// The analysis of a `UIImage` (the phone's photos): upright and scaled to `maxDimension` first.
/// Apart from the rest of `PhotoAnalyzer`, which needs no UIKit, so the evaluation tool
/// (tools/evaluate) compiles it for macOS.
extension PhotoAnalyzer {
    static func analyze(_ image: UIImage) async -> PhotoAnalysis {
        await Task.detached(priority: .userInitiated) { analyzeNow(image) }.value
    }

    /// Analyses only the cartridge in `candidate` (fractions of the photo, from `candidates`):
    /// the photo is cut down to a margin around it, so the others don't get in the way.
    static func analyze(_ image: UIImage, focusingOn candidate: CGRect) async -> PhotoAnalysis {
        await Task.detached(priority: .userInitiated) { analyzeNow(image, focusingOn: candidate) }.value
    }

    static func analyzeNow(_ image: UIImage, focusingOn candidate: CGRect) -> PhotoAnalysis {
        analyzeNow(image, in: focusRegion(candidate))
    }

    /// The part `region` of the photo (fractions of the upright photo) cut out at full size and
    /// analysed on its own (one look), as an analysis of the whole photo (`inPhoto`).
    private static func analyzeNow(_ image: UIImage, in region: CGRect) -> PhotoAnalysis {
        inPhoto(firstLook(cropped(image, to: region)), region: region, photoSize: image.size)
    }

    /// The part of the photo inside `region` (fractions of the upright photo), upright.
    static func cropped(_ image: UIImage, to region: CGRect) -> UIImage {
        let size = image.size
        let crop = CGRect(x: region.minX * size.width, y: region.minY * size.height,
                          width: region.width * size.width, height: region.height * size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: crop.size, format: format).image { _ in
            image.draw(at: CGPoint(x: -crop.minX, y: -crop.minY))
        }
    }

    /// Two looks: the whole photo, then the full-size part around the cartridge it found
    /// (`secondLookRegion`).
    static func analyzeNow(_ image: UIImage) -> PhotoAnalysis {
        let first = firstLook(image)
        guard let region = secondLookRegion(of: first) else { return first }
        return secondLook(first, then: analyzeNow(image, in: region))
    }

    /// One look at the photo, scaled to `maxDimension`.
    private static func firstLook(_ image: UIImage) -> PhotoAnalysis {
        guard let cgImage = upright(image, maxSide: maxDimension) else { return PhotoAnalysis(shape: nil) }
        return analyzeNow(cgImage)
    }

    /// The image scaled down and with its orientation applied, so pixels are upright.
    private static func upright(_ image: UIImage, maxSide: CGFloat) -> CGImage? {
        let longSide = max(image.size.width, image.size.height)
        guard longSide > 0 else { return nil }
        let factor = min(1, maxSide / longSide)
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}
