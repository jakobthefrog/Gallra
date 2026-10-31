import Foundation
import ImageIO

public enum RatingError: Error, Sendable, Equatable {
    /// The file has no rating field to change; it is left untouched.
    case noRatingField
    case invalidRating
    /// Rating writing for this file type has not been tested on real files yet; the file is never touched.
    case formatNotTested
    /// The written file failed the checks; the original was kept or restored.
    case verificationFailed(String)
}

/// Writes a star rating into a photo file's XMP block. The only code allowed to modify a photo file.
///
/// Method (proven in the Stage 0 spike): the rating is one digit inside the existing XMP text, so
/// changing it moves no offsets. Steps: clone the file to a temp copy, change the digit there,
/// verify the copy, atomically swap it in, verify again. A backup clone of the original is kept
/// until the final check passes, and is restored if it fails. JPEG/TIFF/DNG files with no rating
/// field take the rewrite path in `RatingRewriter.swift` instead.
public struct RatingWriter: Sendable {
    public init() {}

    /// How far into the file to look for the XMP rating (it sits near the start in CR3 and 3FR).
    private static let searchLimit = 8 * 1024 * 1024

    /// Sets the rating (0-3 used by the app; 0-5 accepted) of the file at `url`.
    public func write(rating: Int, to url: URL) throws {
        guard (0...5).contains(rating) else { throw RatingError.invalidRating }
        guard PhotoFormat(fileExtension: url.pathExtension)?.ratingWriteTested == true else { throw RatingError.formatNotTested }
        let fm = FileManager.default
        let original = try Data(contentsOf: url, options: .alwaysMapped)
        let offset: Int
        do {
            offset = try RatingWriter.digitOffset(in: original)
        } catch RatingError.noRatingField where PhotoFormat(fileExtension: url.pathExtension)?.supportsMetadataRewrite == true {
            // No rating field to edit in place: let ImageIO copy the file with the rating added.
            try rewrite(rating: rating, at: url)
            return
        }
        if original[offset] == UInt8(ascii: "0") + UInt8(rating) { return }   // already set

        let id = UUID().uuidString
        let dir = url.deletingLastPathComponent()
        // Keep the extension: reading the rating back depends on the file type.
        let temp = dir.appendingPathComponent(".gallra-tmp-\(id).\(url.pathExtension)")
        let backup = dir.appendingPathComponent(".gallra-backup-\(id).\(url.pathExtension)")
        defer { try? fm.removeItem(at: temp) }

        try fm.copyItem(at: url, to: backup)
        do {
            try fm.copyItem(at: url, to: temp)
            let handle = try FileHandle(forUpdating: temp)
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: Data([UInt8(ascii: "0") + UInt8(rating)]))
            try handle.synchronize()
            try handle.close()
            try RatingWriter.verify(temp, against: original, offset: offset, rating: rating)

            _ = try fm.replaceItemAt(url, withItemAt: temp)
            try RatingWriter.verify(url, against: original, offset: offset, rating: rating)
        } catch {
            // Put the original bytes back if the swap happened but the result is wrong.
            if let now = try? Data(contentsOf: url, options: .alwaysMapped), now != original,
               (try? RatingWriter.verify(url, against: original, offset: offset, rating: rating)) == nil {
                _ = try? fm.replaceItemAt(url, withItemAt: backup)
            } else {
                try? fm.removeItem(at: backup)
            }
            throw error
        }
        try? fm.removeItem(at: backup)
    }

    /// Position of the rating digit in the XMP text, or `noRatingField`.
    static func digitOffset(in data: Data) throws -> Int {
        let head = data.prefix(searchLimit)
        let patterns = ["Rating>", "Rating=\""]
        var found: [Int] = []
        for pattern in patterns {
            let needle = Data(pattern.utf8)
            var start = head.startIndex
            while let range = head.range(of: needle, in: start..<head.endIndex) {
                let digit = range.upperBound
                if digit + 1 < head.endIndex, (UInt8(ascii: "0")...UInt8(ascii: "5")).contains(head[digit]) {
                    let after = head[digit + 1]
                    // Single digit only, closed by "<" (element) or quote (attribute).
                    if after == UInt8(ascii: "<") || after == UInt8(ascii: "\"") { found.append(digit) }
                }
                start = range.upperBound
            }
        }
        guard found.count == 1 else { throw RatingError.noRatingField }
        return found[0]
    }

    /// Same size, exactly the rating byte differs, rating reads back, and the preview still decodes.
    private static func verify(_ url: URL, against original: Data, offset: Int, rating: Int) throws {
        let now = try Data(contentsOf: url, options: .alwaysMapped)
        guard now.count == original.count else { throw RatingError.verificationFailed("size changed") }
        // Everything except the one rating byte must be identical (bulk compares are fast).
        guard now[..<offset] == original[..<offset],
              now[(offset + 1)...] == original[(offset + 1)...] else {
            throw RatingError.verificationFailed("unexpected bytes changed")
        }
        guard PhotoMetadataReader().read(url).rating == rating else {
            throw RatingError.verificationFailed("rating does not read back")
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceThumbnailMaxPixelSize: 160] as CFDictionary) != nil
        else { throw RatingError.verificationFailed("preview no longer decodes") }
    }
}
