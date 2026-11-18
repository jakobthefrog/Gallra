import Foundation
import ImageIO
import CoreGraphics
import Accelerate

/// Colour used to paint in-focus edges.
public enum PeakingColor: String, Codable, CaseIterable, Sendable {
    case red, yellow, green, blue

    var rgb: (r: UInt8, g: UInt8, b: UInt8) {
        switch self {
        case .red: (255, 59, 48)
        case .yellow: (255, 214, 10)
        case .green: (48, 209, 88)
        case .blue: (10, 132, 255)
        }
    }
}

/// Which pixels of a photo are in focus. One byte per pixel: 255 = sharp edge, 0 = not.
/// The mask may be smaller than the photo; scale the overlay to fit when drawing.
public struct FocusMask: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [UInt8]
    /// Part of the photo this mask covers, as fractions (0...1) of the photo. The whole photo by default.
    public let region: CGRect

    public init(width: Int, height: Int, pixels: [UInt8], region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) {
        self.width = width; self.height = height; self.pixels = pixels; self.region = region
    }

    /// Share of pixels marked sharp, 0...1.
    public var coverage: Double {
        guard !pixels.isEmpty else { return 0 }
        return Double(pixels.lazy.filter { $0 > 0 }.count) / Double(pixels.count)
    }

    /// A transparent image with the sharp pixels painted in `color`, ready to lay over the photo.
    /// `thickness` widens each marked pixel by that many pixels in every direction so it stays visible.
    public func overlay(color: PeakingColor, thickness: Int = 1) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let c = color.rgb
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height { for x in 0..<width where pixels[y * width + x] > 0 {
            for yy in max(0, y - thickness)...min(height - 1, y + thickness) {
                for xx in max(0, x - thickness)...min(width - 1, x + thickness) {
                    let i = yy * width + xx
                    rgba[i * 4] = c.r; rgba[i * 4 + 1] = c.g; rgba[i * 4 + 2] = c.b; rgba[i * 4 + 3] = 255
                }
            }
        } }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// Finds in-focus edges ("focus peaking"). Pure read-only image maths: it never touches
/// a user's file. Work is CPU-heavy, so call it off the main thread.
public enum FocusPeaking {
    /// Decodes a JPEG preview (as served by `PreviewService`) and finds its sharp edges.
    /// - Parameters:
    ///   - sensitivity: 0 (only the sharpest edges) ... 1 (many edges). Default 0.5.
    ///   - maxPixel: long edge used for analysis; larger is more exact but slower.
    public static func mask(fromJPEG data: Data, sensitivity: Double = 0.5, maxPixel: Int = 2048) throws -> FocusMask {
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
        guard let gray = grayPixels(image, width: w, height: h) else { throw PreviewError.cannotRead }
        return mask(gray: gray, width: w, height: h, sensitivity: sensitivity)
    }

    /// Like `mask(fromJPEG:)`, but analyses only `region` (fractions of the photo) at full detail.
    /// Use it when zoomed in, so the edges stay crisp. `maxPixel` caps the long edge of the analysed
    /// area (it is scaled down if larger). The result's `region` is the area actually covered.
    public static func mask(fromJPEG data: Data, sensitivity: Double = 0.5, region: CGRect, maxPixel: Int = 4608) throws -> FocusMask {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PreviewError.cannotRead }
        let W = Double(full.width), H = Double(full.height)
        let wanted = CGRect(x: region.minX * W, y: region.minY * H, width: region.width * W, height: region.height * H)
        let rect = wanted.integral.intersection(CGRect(x: 0, y: 0, width: W, height: H))
        guard rect.width >= 5, rect.height >= 5, let cropped = full.cropping(to: rect) else { throw PreviewError.cannotRead }
        let scale = min(1, Double(maxPixel) / max(rect.width, rect.height))
        let w = max(5, Int(rect.width * scale)), h = max(5, Int(rect.height * scale))
        guard let gray = grayPixels(cropped, width: w, height: h) else { throw PreviewError.cannotRead }
        let found = mask(gray: gray, width: w, height: h, sensitivity: sensitivity)
        let covered = CGRect(x: rect.minX / W, y: rect.minY / H, width: rect.width / W, height: rect.height / H)
        return FocusMask(width: w, height: h, pixels: found.pixels, region: covered)
    }

    private static func grayPixels(_ image: CGImage, width w: Int, height h: Int) -> [UInt8]? {
        var gray = [UInt8](repeating: 0, count: w * h)
        let drawn = gray.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? gray : nil
    }

    /// Finds sharp edges in an 8-bit grayscale image (row by row, `width * height` bytes).
    /// Steps: light 3x3 blur (ignores grain), Laplacian edge strength, then a threshold.
    public static func mask(gray: [UInt8], width: Int, height: Int, sensitivity: Double = 0.5) -> FocusMask {
        precondition(gray.count == width * height, "gray buffer size must match width * height")
        guard width >= 5, height >= 5 else { return FocusMask(width: width, height: height, pixels: [UInt8](repeating: 0, count: gray.count)) }
        let s = min(max(sensitivity, 0), 1)
        let threshold = Float(7 - 5 * s)     // edge strength needed, on a 0...255 scale
        let n = width * height

        // One 5x5 kernel = light 3x3 blur (ignores grain) followed by a Laplacian (edge strength / 4).
        let box = [Float](repeating: 1.0 / 9, count: 9)
        let lap: [Float] = [0, -1, 0, -1, 4, -1, 0, -1, 0].map { $0 / 4 }
        var kernel = [Float](repeating: 0, count: 25)
        for ly in 0..<3 { for lx in 0..<3 { for by in 0..<3 { for bx in 0..<3 {
            kernel[(ly + by) * 5 + lx + bx] += lap[ly * 3 + lx] * box[by * 3 + bx]
        } } } }

        // Accelerate does the heavy lifting (fast even in unoptimised debug builds).
        var input = [Float](repeating: 0, count: n)
        var edges = [Float](repeating: 0, count: n)
        vDSP_vfltu8(gray, 1, &input, 1, vDSP_Length(n))
        input.withUnsafeMutableBytes { i in
            edges.withUnsafeMutableBytes { e in
                var src = vImage_Buffer(data: i.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)
                var dst = vImage_Buffer(data: e.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)
                vImageConvolve_PlanarF(&src, &dst, nil, 0, 0, kernel, 5, 5, 0, vImage_Flags(kvImageEdgeExtend))
            }
        }
        vDSP_vabs(edges, 1, &edges, 1, vDSP_Length(n))

        var out = [UInt8](repeating: 0, count: n)
        edges.withUnsafeBufferPointer { e in
            out.withUnsafeMutableBufferPointer { o in
                for i in 0..<n where e[i] > threshold { o[i] = 255 }
            }
        }
        return FocusMask(width: width, height: height, pixels: out)
    }
}
