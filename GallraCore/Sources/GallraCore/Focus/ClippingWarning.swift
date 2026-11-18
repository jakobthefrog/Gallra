import Foundation
import ImageIO
import CoreGraphics
import Accelerate

/// Which end of the tonal range to warn about.
public enum ClippingKind: String, Codable, CaseIterable, Sendable {
    /// Blown highlights: pure white, no detail left.
    case highlights
    /// Crushed shadows: pure black, no detail left.
    case shadows

    /// Colour used to paint the warning: green for highlights, blue for shadows.
    public var color: PeakingColor { self == .highlights ? .green : .blue }
}

/// Finds blown highlights and crushed shadows ("clipping warning"). Read-only image maths,
/// like `FocusPeaking`; it never touches a user's file. Call it off the main thread.
///
/// A pixel counts as blown when all of red, green and blue are at least `highlightLevel`,
/// and as crushed when all three are at most `shadowLevel` (0...255 scale). Tiny isolated
/// spots are ignored so the warning shows areas, not noise. It works on the camera's
/// embedded JPEG preview, so it is a quick guide, not a verdict on the RAW data.
public enum ClippingWarning {
    public static let highlightLevel = 250
    public static let shadowLevel = 5

    /// Decodes a JPEG preview (as served by `PreviewService`) and finds its clipped areas.
    /// `maxPixel` is the long edge used for analysis; the overlay scales to fit the photo.
    public static func mask(fromJPEG data: Data, kind: ClippingKind, maxPixel: Int = 2048) throws -> FocusMask {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw PreviewError.cannotRead }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PreviewError.cannotRead
        }
        let w = image.width, h = image.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { throw PreviewError.cannotRead }
        return mask(rgba: rgba, width: w, height: h, kind: kind)
    }

    /// Finds clipped pixels in 8-bit RGBA data (4 bytes per pixel, row by row; alpha is ignored).
    public static func mask(rgba: [UInt8], width: Int, height: Int, kind: ClippingKind) -> FocusMask {
        precondition(rgba.count == width * height * 4, "rgba buffer size must match width * height * 4")
        let n = width * height
        var marked = [UInt8](repeating: 0, count: n)
        let high = UInt8(highlightLevel), low = UInt8(shadowLevel)
        rgba.withUnsafeBufferPointer { p in
            marked.withUnsafeMutableBufferPointer { m in
                if kind == .highlights {
                    for i in 0..<n where p[i * 4] >= high && p[i * 4 + 1] >= high && p[i * 4 + 2] >= high { m[i] = 255 }
                } else {
                    for i in 0..<n where p[i * 4] <= low && p[i * 4 + 1] <= low && p[i * 4 + 2] <= low { m[i] = 255 }
                }
            }
        }
        guard width >= 5, height >= 5 else { return FocusMask(width: width, height: height, pixels: marked) }

        // Ignore lone specks: keep a marked pixel only if enough of its 5x5 neighbourhood is marked too.
        var density = [UInt8](repeating: 0, count: n)
        marked.withUnsafeMutableBytes { m in
            density.withUnsafeMutableBytes { d in
                var src = vImage_Buffer(data: m.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width)
                var dst = vImage_Buffer(data: d.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width)
                vImageBoxConvolve_Planar8(&src, &dst, nil, 0, 0, 5, 5, 0, vImage_Flags(kvImageEdgeExtend))
            }
        }
        var out = marked
        out.withUnsafeMutableBufferPointer { o in
            density.withUnsafeBufferPointer { d in
                for i in 0..<n where o[i] > 0 && d[i] < 90 { o[i] = 0 }   // under about 35% of the 5x5 area
            }
        }
        return FocusMask(width: width, height: height, pixels: out)
    }
}
