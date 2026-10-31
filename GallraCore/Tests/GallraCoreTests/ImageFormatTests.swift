import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import GallraCore

/// JPEG and TIFF (8/16 bit) support, using small images generated into a scratch folder.
@Suite struct ImageFormatTests {
    /// Writes a small gradient image with no rating field in it.
    private func makeImage(_ name: String, type: UTType, bits: Int, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let width = 64, height = 48
        let bytesPerPixel = bits == 16 ? 8 : 4
        var data = Data(count: width * height * bytesPerPixel)
        data.withUnsafeMutableBytes { raw in
            for i in 0..<(width * height) {
                if bits == 16 {
                    let p = raw.bindMemory(to: UInt16.self)
                    p[i * 4] = UInt16(i % width) * 1000; p[i * 4 + 1] = UInt16(i / width) * 1300
                    p[i * 4 + 2] = 30000; p[i * 4 + 3] = .max
                } else {
                    let p = raw.bindMemory(to: UInt8.self)
                    p[i * 4] = UInt8(i % width * 4); p[i * 4 + 1] = UInt8(i / width * 5)
                    p[i * 4 + 2] = 120; p[i * 4 + 3] = 255
                }
            }
        }
        let info: UInt32 = bits == 16
            ? CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
            : CGImageAlphaInfo.premultipliedLast.rawValue
        let provider = try #require(CGDataProvider(data: data as CFData))
        let image = try #require(CGImage(
            width: width, height: height, bitsPerComponent: bits, bitsPerPixel: bits * 4,
            bytesPerRow: width * bytesPerPixel, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent))
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gallra-img-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func extensionsMapToFormats() {
        #expect(PhotoFormat(fileExtension: "JPEG") == .jpg)
        #expect(PhotoFormat(fileExtension: "jpg") == .jpg)
        #expect(PhotoFormat(fileExtension: "TIF") == .tiff)
        #expect(PhotoFormat(fileExtension: "tiff") == .tiff)
        #expect(PhotoFormat(fileExtension: "DNG") == .dng)
        #expect(PhotoFormat(fileExtension: "png") == nil)
    }

    @Test(arguments: [("a.jpg", UTType.jpeg, 8), ("b.tif", UTType.tiff, 8), ("c.tiff", UTType.tiff, 16)])
    func listsAndRatesImageWithoutRatingField(name: String, type: UTType, bits: Int) async throws {
        let dir = try scratch()
        let url = try makeImage(name, type: type, bits: bits, in: dir)
        let photos = try FolderBrowser().photos(in: dir)
        #expect(photos.count == 1)
        #expect(PhotoMetadataReader().read(url).rating == nil)

        try RatingWriter().write(rating: 2, to: url)
        #expect(PhotoMetadataReader().read(url).rating == 2)
        try RatingWriter().write(rating: 3, to: url)   // second write now has a field to edit in place
        #expect(PhotoMetadataReader().read(url).rating == 3)

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        #expect(props?[kCGImagePropertyPixelWidth] as? Int == 64)
        #expect(props?[kCGImagePropertyDepth] as? Int == bits)
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".gallra-") }
        #expect(left.isEmpty)

        let preview = try await PreviewService(diskFolder: dir.appendingPathComponent("cache"))
            .preview(for: try #require(FolderBrowser().photos(in: dir).first), size: .thumbnail)
        #expect(!preview.isEmpty)
    }

    @Test func jpegPixelsSurviveRewrite() throws {
        let dir = try scratch()
        let url = try makeImage("p.jpg", type: .jpeg, bits: 8, in: dir)
        func pixels() throws -> Data {
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            return try #require(image.dataProvider?.data) as Data
        }
        let before = try pixels()
        try RatingWriter().write(rating: 1, to: url)
        #expect(try pixels() == before)   // no re-encoding of the picture
    }
}

/// Real sample files from Gallra-TestPhotos (always worked on as COPIES).
@Suite struct RealSampleTests {
    private func copy(_ suffix: String) throws -> URL {
        let name = try #require(try FileManager.default.contentsOfDirectory(atPath: Scratch.samples.path)
            .sorted().first { $0.hasSuffix(suffix) })
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gallra-real-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try FileManager.default.copyItem(at: Scratch.samples.appendingPathComponent(name), to: url)
        return url
    }

    @Test(arguments: ["_web.jpg", "_8bit.tif", "_16bit.tif", ".dng", "DSCF3883.RAF", "DSCF6243.RAF"])
    func ratesRealSample(suffix: String) async throws {
        let url = try copy(suffix)
        let dir = url.deletingLastPathComponent()
        let photo = try #require(try FolderBrowser().photos(in: dir).first)
        let start = PhotoMetadataReader().read(url)
        print("SAMPLE \(url.lastPathComponent) format=\(photo.format) rating=\(String(describing: start.rating)) date=\(String(describing: start.captureDate))")

        // Filters read the date and shooting details; they must be there for every format.
        let info = PhotoMetadataReader().cameraInfo(url)
        print("SAMPLE \(url.lastPathComponent) info: \(info.summary)")
        #expect(start.captureDate != nil)
        #expect(info.iso != nil || suffix.hasSuffix("tif"))

        let clock = ContinuousClock()
        #expect(photo.format == PhotoFormat(fileExtension: url.pathExtension))
        let t = try await clock.measure {
            let service = PreviewService(diskFolder: dir.appendingPathComponent("cache"))
            let data = try await service.preview(for: photo, size: .full)
            #expect(!data.isEmpty)
            #expect(!(try await service.preview(for: photo, size: .thumbnail)).isEmpty)
        }
        print("SAMPLE \(suffix) full preview: \(t)")

        let src0 = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let fp0 = RatingWriter.Fingerprint(src0)
        for stars in [2, 3, 0] {
            try RatingWriter().write(rating: stars, to: url)
            #expect(PhotoMetadataReader().read(url).rating == stars)
        }
        let fp1 = RatingWriter.Fingerprint(try #require(CGImageSourceCreateWithURL(url as CFURL, nil)))
        #expect(fp0 == fp1)
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".gallra-") }
        #expect(left.isEmpty)
    }
}

@Suite struct OtherCameraFormatTests {
    @Test func extensionsMapToFormats() {
        let expected: [(String, PhotoFormat)] = [("ARW", .arw), ("nef", .nef), ("RAF", .raf), ("cr2", .cr2),
                                                 ("ORF", .orf), ("rw2", .rw2), ("HEIC", .heic), ("heif", .heic), ("hif", .heic)]
        for (ext, format) in expected { #expect(PhotoFormat(fileExtension: ext) == format) }
    }

    /// Formats not yet tried on real files are listed but never written to.
    @Test(arguments: ["arw", "nef", "cr2", "orf", "rw2", "heic"])
    func untestedFormatsRefuseRatingWrites(ext: String) throws {
        let dir = try Scratch.folder(cr3: 1, threeFR: 0)
        let cr3 = try FolderBrowser().photos(in: dir)[0].url
        let url = dir.appendingPathComponent("fake.\(ext)")
        try FileManager.default.moveItem(at: cr3, to: url)   // a file with a valid rating field, wrong extension
        let before = try Data(contentsOf: url)
        #expect(try FolderBrowser().photos(in: dir).count == 1)
        #expect(throws: RatingError.formatNotTested) { try RatingWriter().write(rating: 3, to: url) }
        #expect(try Data(contentsOf: url) == before)
    }
}
