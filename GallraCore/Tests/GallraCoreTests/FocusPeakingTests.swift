import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import GallraCore

@Suite("Focus peaking")
struct FocusPeakingTests {
    private let w = 200, h = 200

    /// Hard-edged checkerboard (sharp) on the left half, flat grey on the right.
    private func sharpLeftFlatRight() -> [UInt8] {
        var g = [UInt8](repeating: 128, count: w * h)
        for y in 0..<h { for x in 0..<(w / 2) { g[y * w + x] = ((x / 8 + y / 8) % 2 == 0) ? 20 : 235 } }
        return g
    }

    /// Smooth waves: same pattern idea, but with no hard edges (what blur looks like).
    private func blurry() -> [UInt8] {
        var g = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w {
            g[y * w + x] = UInt8(128 + 100 * sin(Double(x) / 6) * sin(Double(y) / 6))
        } }
        return g
    }

    @Test func sharpEdgesAreMarkedAndFlatAreaIsNot() {
        let m = FocusPeaking.mask(gray: sharpLeftFlatRight(), width: w, height: h, sensitivity: 0.5)
        var left = 0, right = 0
        for y in 0..<h { for x in 0..<w where m.pixels[y * w + x] > 0 { if x < w / 2 + 2 { left += 1 } else { right += 1 } } }
        #expect(left > 500)
        #expect(right == 0)
    }

    @Test func blurryImageHasAlmostNoPeaking() {
        let m = FocusPeaking.mask(gray: blurry(), width: w, height: h, sensitivity: 0.5)
        #expect(m.coverage < 0.01)
    }

    @Test func higherSensitivityMarksMore() {
        let img = sharpLeftFlatRight()
        let low = FocusPeaking.mask(gray: img, width: w, height: h, sensitivity: 0).coverage
        let high = FocusPeaking.mask(gray: blurryNoisy(), width: w, height: h, sensitivity: 1).coverage
        let lowNoisy = FocusPeaking.mask(gray: blurryNoisy(), width: w, height: h, sensitivity: 0).coverage
        #expect(low > 0)
        #expect(high >= lowNoisy)
    }

    private func blurryNoisy() -> [UInt8] {
        blurry().enumerated().map { i, v in UInt8(clamping: Int(v) + (i % 7 == 0 ? 6 : 0)) }
    }

    @Test func jpegPreviewRoundTrip() throws {
        let gray = sharpLeftFlatRight()
        let provider = CGDataProvider(data: Data(gray) as CFData)!
        let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        let m = try FocusPeaking.mask(fromJPEG: out as Data)
        #expect(m.width == w && m.height == h)
        #expect(m.coverage > 0.02)
        #expect(m.overlay(color: .red) != nil)
    }
}
