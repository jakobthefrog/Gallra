import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import GallraCore

@Suite("Clipping warning")
struct ClippingWarningTests {
    private let w = 120, h = 60

    /// Left third white, middle third mid grey, right third black.
    private func threeBands(speck: Bool = false) -> [UInt8] {
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let v: UInt8 = x < w / 3 ? 255 : (x < 2 * w / 3 ? 128 : 0)
            let i = (y * w + x) * 4
            px[i] = v; px[i + 1] = v; px[i + 2] = v; px[i + 3] = 255
        } }
        if speck { let i = (30 * w + 60) * 4; px[i] = 255; px[i + 1] = 255; px[i + 2] = 255 }   // one white pixel in the grey
        return px
    }

    private func region(_ m: FocusMask, xs: Range<Int>) -> Int {
        var count = 0
        for y in 0..<h { for x in xs where m.pixels[y * w + x] > 0 { count += 1 } }
        return count
    }

    @Test func highlightsMarkOnlyTheWhiteBand() {
        let m = ClippingWarning.mask(rgba: threeBands(), width: w, height: h, kind: .highlights)
        #expect(region(m, xs: 0..<(w / 3 - 3)) == (w / 3 - 3) * h)
        #expect(region(m, xs: (w / 3 + 3)..<w) == 0)
    }

    @Test func shadowsMarkOnlyTheBlackBand() {
        let m = ClippingWarning.mask(rgba: threeBands(), width: w, height: h, kind: .shadows)
        #expect(region(m, xs: (2 * w / 3 + 3)..<w) == (w / 3 - 3) * h)
        #expect(region(m, xs: 0..<(2 * w / 3 - 3)) == 0)
    }

    @Test func loneBrightPixelIsIgnored() {
        let m = ClippingWarning.mask(rgba: threeBands(speck: true), width: w, height: h, kind: .highlights)
        #expect(m.pixels[30 * w + 60] == 0)
    }

    @Test func oneClippedChannelAloneIsNotEnough() {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) { px[i * 4] = 255; px[i * 4 + 1] = 100; px[i * 4 + 2] = 100; px[i * 4 + 3] = 255 }   // saturated red
        #expect(ClippingWarning.mask(rgba: px, width: w, height: h, kind: .highlights).coverage == 0)
        #expect(ClippingWarning.mask(rgba: px, width: w, height: h, kind: .shadows).coverage == 0)
    }

    @Test func jpegRoundTripAndColours() throws {
        let px = threeBands()
        let provider = CGDataProvider(data: Data(px) as CFData)!
        let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        let hi = try ClippingWarning.mask(fromJPEG: out as Data, kind: .highlights)
        let lo = try ClippingWarning.mask(fromJPEG: out as Data, kind: .shadows)
        #expect(hi.coverage > 0.25 && hi.coverage < 0.4)
        #expect(lo.coverage > 0.25 && lo.coverage < 0.4)
        #expect(ClippingKind.highlights.color == .green && ClippingKind.shadows.color == .blue)
        #expect(hi.overlay(color: ClippingKind.highlights.color, thickness: 0) != nil)
    }
}

@Suite("Clipping warning from RAW")
struct ClippingWarningRawTests {
    private static let sample = URL(fileURLWithPath: NSString(string: "~/Documents/Gallra/Gallra-TestPhotos/DJI_0372.DNG").expandingTildeInPath)

    @Test func notARawFileThrowsSoCallersCanFallBack() throws {
        let jpeg = FileManager.default.temporaryDirectory.appendingPathComponent("clip-test-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: jpeg) }
        let px = [UInt8](repeating: 200, count: 40 * 40 * 4)
        let image = CGImage(width: 40, height: 40, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 160,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: CGDataProvider(data: Data(px) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let dest = CGImageDestinationCreateWithURL(jpeg as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        #expect(throws: (any Error).self) { try ClippingWarning.mask(fromRAW: jpeg, kind: .highlights) }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: sample.path)))
    func sampleRawGivesAMaskAtReducedSize() throws {
        let m = try ClippingWarning.mask(fromRAW: Self.sample, kind: .highlights, maxPixel: 1024)
        #expect(max(m.width, m.height) <= 1024 && min(m.width, m.height) > 100)
        #expect(m.coverage >= 0 && m.coverage < 1)
    }
}
