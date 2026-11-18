import Testing
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import GallraCore

/// Manual helper, skipped in normal test runs. Run it with `scripts/focus-peaking-demo.sh <photo>`.
/// Reads one photo and writes NEW images only (preview with red peaking at three sensitivities).
@Suite("Focus peaking demo")
struct FocusPeakingDemo {
    static let input = ProcessInfo.processInfo.environment["GALLRA_PEAKING_INPUT"]
    static let output = ProcessInfo.processInfo.environment["GALLRA_PEAKING_OUTPUT"]

    @Test(.enabled(if: input != nil && output != nil))
    func writeDemoImages() throws {
        let photo = URL(fileURLWithPath: try #require(Self.input))
        let outFolder = URL(fileURLWithPath: try #require(Self.output))
        try FileManager.default.createDirectory(at: outFolder, withIntermediateDirectories: true)

        let jpeg = try PreviewService.extract(from: photo, maxPixel: 2048)
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let base = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let name = photo.deletingPathExtension().lastPathComponent

        for (label, sensitivity) in [("low", 0.25), ("mid", 0.5), ("high", 0.75)] {
            let start = Date()
            let mask = try FocusPeaking.mask(fromJPEG: jpeg, sensitivity: sensitivity)
            let seconds = Date().timeIntervalSince(start)
            let overlay = try #require(mask.overlay(color: .red))

            let ctx = try #require(CGContext(
                data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let rect = CGRect(x: 0, y: 0, width: base.width, height: base.height)
            ctx.draw(base, in: rect)
            ctx.draw(overlay, in: rect)
            let result = try #require(ctx.makeImage())

            let file = outFolder.appendingPathComponent("\(name)-peaking-\(label).jpg")
            let dest = try #require(CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(dest, result, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            #expect(CGImageDestinationFinalize(dest))
            print("PEAKING \(label): \(Int(mask.coverage * 1000) / 10)% of pixels, \(Int(seconds * 1000)) ms -> \(file.path)")
        }
    }
}
