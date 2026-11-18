import Testing
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
@testable import GallraCore

/// Manual helper, skipped in normal runs. Compares clipping from the JPEG preview with clipping
/// from the RAW for the photos listed in GALLRA_CLIP_INPUT (paths separated by ":"). Read-only.
@Suite("Clipping RAW demo")
struct ClippingRawDemo {
    static let input = ProcessInfo.processInfo.environment["GALLRA_CLIP_INPUT"]

    @Test(.enabled(if: input != nil))
    func compare() throws {
        let outFolder = ProcessInfo.processInfo.environment["GALLRA_CLIP_OUTPUT"].map { URL(fileURLWithPath: $0) }
        if let outFolder { try FileManager.default.createDirectory(at: outFolder, withIntermediateDirectories: true) }
        for path in (Self.input ?? "").split(separator: ":").map(String.init) {
            let url = URL(fileURLWithPath: path)
            let jpeg = try PreviewService.extract(from: url, maxPixel: 2048)
            if let outFolder {
                let src = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
                let base = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
                for (label, useRaw) in [("jpeg", false), ("raw", true)] {
                    let ctx = try #require(CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                    let rect = CGRect(x: 0, y: 0, width: base.width, height: base.height)
                    ctx.draw(base, in: rect)
                    for kind in ClippingKind.allCases {
                        let m = useRaw ? try ClippingWarning.mask(fromRAW: url, kind: kind) : try ClippingWarning.mask(fromJPEG: jpeg, kind: kind)
                        if let o = m.overlay(color: kind.color, thickness: 0) { ctx.draw(o, in: rect) }
                    }
                    let file = outFolder.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent)-clipping-\(label).jpg")
                    let dest = try #require(CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
                    CGImageDestinationAddImage(dest, try #require(ctx.makeImage()), [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
                    #expect(CGImageDestinationFinalize(dest))
                }
            }
            for kind in ClippingKind.allCases {
                let a = try ClippingWarning.mask(fromJPEG: jpeg, kind: kind)
                let t = Date()
                let b = try ClippingWarning.mask(fromRAW: url, kind: kind)
                let ms = Int(Date().timeIntervalSince(t) * 1000)
                func pct(_ m: FocusMask) -> String { String(format: "%.2f%%", m.coverage * 100) }
                print("CLIP \(url.lastPathComponent) \(kind.rawValue): jpeg \(pct(a))  raw \(pct(b))  (\(b.width)x\(b.height), \(ms) ms)")
            }
        }
    }
}
