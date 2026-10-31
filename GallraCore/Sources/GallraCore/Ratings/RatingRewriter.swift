import Foundation
import ImageIO

extension RatingWriter {
    /// Adds an `xmp:Rating` to a file that has none, by letting ImageIO copy the image data
    /// unchanged into a temp file with the new metadata (no re-encoding of pixels).
    ///
    /// Same safety steps as the in-place path: write a temp copy, verify it, keep a backup clone,
    /// atomically swap, verify again, restore the backup if anything is wrong. If ImageIO cannot
    /// rewrite this kind of file, the file is left untouched and `noRatingField` is thrown.
    func rewrite(rating: Int, at url: URL) throws {
        let fm = FileManager.default
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) else { throw RatingError.noRatingField }
        let before = Fingerprint(source)
        let originalSize = (try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        // ImageIO cannot write DNG files at all, so DNG goes straight to the padding method.
        if PhotoFormat(fileExtension: url.pathExtension) == .dng {
            try rewriteUsingPadding(rating: rating, at: url, before: before, originalSize: originalSize)
            return
        }

        let id = UUID().uuidString
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let temp = dir.appendingPathComponent(".gallra-tmp-\(id).\(ext)")
        let backup = dir.appendingPathComponent(".gallra-backup-\(id).\(ext)")
        defer { try? fm.removeItem(at: temp) }

        let metadata = CGImageMetadataCreateMutable()
        let tag = CGImageMetadataTagCreate(kCGImageMetadataNamespaceXMPBasic, kCGImageMetadataPrefixXMPBasic,
                                           "Rating" as CFString, .string, "\(rating)" as CFString)
        guard let tag, CGImageMetadataSetTagWithPath(metadata, nil, "xmp:Rating" as CFString, tag),
              let destination = CGImageDestinationCreateWithURL(temp as CFURL, type, 1, nil) else {
            throw RatingError.noRatingField
        }
        let options = [kCGImageDestinationMetadata: metadata,
                       kCGImageDestinationMergeMetadata: true] as CFDictionary
        var error: Unmanaged<CFError>?
        guard CGImageDestinationCopyImageSource(destination, source, options, &error) else {
            // ImageIO cannot rewrite this file; nothing was changed.
            throw RatingError.noRatingField
        }
        try RatingWriter.verifyRewrite(temp, before: before, originalSize: originalSize, rating: rating)
        try RatingWriter.commit(temp, over: url, backup: backup) {
            try RatingWriter.verifyRewrite($0, before: before, originalSize: originalSize, rating: rating)
        }
    }

    /// Backup clone, atomic swap, verify the result, restore the backup if it fails.
    static func commit(_ temp: URL, over url: URL, backup: URL, verify: (URL) throws -> Void) throws {
        let fm = FileManager.default
        try fm.copyItem(at: url, to: backup)
        do {
            _ = try fm.replaceItemAt(url, withItemAt: temp)
            try verify(url)
        } catch {
            _ = try? fm.replaceItemAt(url, withItemAt: backup)
            throw error
        }
        try? fm.removeItem(at: backup)
    }

    /// DNG fallback. Adobe-style XMP packets end in a run of blank padding, so a rating attribute can be
    /// inserted into the packet and the same number of padding bytes dropped: the file keeps its exact
    /// size and nothing after the packet moves. Anything unexpected leaves the file untouched.
    private func rewriteUsingPadding(rating: Int, at url: URL, before: Fingerprint, originalSize: Int64) throws {
        let fm = FileManager.default
        let original = try Data(contentsOf: url, options: .alwaysMapped)
        let head = original.prefix(8 * 1024 * 1024)
        guard let begin = head.range(of: Data("<?xpacket begin".utf8)),
              let end = head.range(of: Data("<?xpacket end".utf8), in: begin.upperBound..<head.endIndex),
              head.range(of: Data("Rating".utf8), in: begin.upperBound..<end.lowerBound) == nil,
              head.range(of: Data("xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\"".utf8), in: begin.upperBound..<end.lowerBound) != nil,
              let about = head.range(of: Data("rdf:about=\"\"".utf8), in: begin.upperBound..<end.lowerBound)
        else { throw RatingError.noRatingField }

        let insert = Data(" xmp:Rating=\"\(rating)\"".utf8)
        // Blank run right before "<?xpacket end": its last bytes are given up to make room.
        var padStart = end.lowerBound
        while padStart > about.upperBound, [0x20, 0x0A, 0x0D, 0x09].contains(original[padStart - 1]) { padStart -= 1 }
        let padLength = end.lowerBound - padStart
        guard padLength >= insert.count + 16 else { throw RatingError.noRatingField }

        let id = UUID().uuidString
        let dir = url.deletingLastPathComponent()
        let temp = dir.appendingPathComponent(".gallra-tmp-\(id).dng")
        let backup = dir.appendingPathComponent(".gallra-backup-\(id).dng")
        defer { try? fm.removeItem(at: temp) }
        try fm.copyItem(at: url, to: temp)

        let from = about.upperBound
        let to = end.lowerBound - insert.count          // the bytes [to, end) were padding
        let shifted = original[from..<to]               // everything between, moved right by insert.count
        let handle = try FileHandle(forUpdating: temp)
        try handle.seek(toOffset: UInt64(from))
        try handle.write(contentsOf: insert)
        try handle.write(contentsOf: shifted)
        try handle.synchronize()
        try handle.close()

        let check: (URL) throws -> Void = { file in
            let now = try Data(contentsOf: file, options: .alwaysMapped)
            guard now.count == original.count,
                  now[..<from] == original[..<from],
                  now[end.lowerBound...] == original[end.lowerBound...] else {
                throw RatingError.verificationFailed("bytes outside the XMP padding changed")
            }
            try RatingWriter.verifyRewrite(file, before: before, originalSize: originalSize, rating: rating)
        }
        try check(temp)
        try RatingWriter.commit(temp, over: url, backup: backup, verify: check)
    }

    /// What must survive a rewrite unchanged.
    struct Fingerprint: Equatable {
        let width: Int?
        let height: Int?
        let orientation: Int?
        let captureDate: String?
        let frames: Int

        init(_ source: CGImageSource) {
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            width = props?[kCGImagePropertyPixelWidth] as? Int
            height = props?[kCGImagePropertyPixelHeight] as? Int
            orientation = props?[kCGImagePropertyOrientation] as? Int
            captureDate = (props?[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifDateTimeOriginal] as? String
            frames = CGImageSourceGetCount(source)
        }
    }

    /// Rating reads back, image size/date/orientation unchanged, file not suspiciously smaller, and it decodes.
    private static func verifyRewrite(_ url: URL, before: Fingerprint, originalSize: Int64, rating: Int) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              Fingerprint(source) == before else {
            throw RatingError.verificationFailed("image properties changed")
        }
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size >= originalSize * 9 / 10 else { throw RatingError.verificationFailed("file got smaller") }
        guard PhotoMetadataReader().read(url).rating == rating else {
            throw RatingError.verificationFailed("rating does not read back")
        }
        guard CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceThumbnailMaxPixelSize: 160] as CFDictionary) != nil else {
            throw RatingError.verificationFailed("image no longer decodes")
        }
    }
}
