import Foundation
import ImageIO

/// Reads capture date and star rating from a RAW file via ImageIO (read-only, ~1-10 ms).
public struct PhotoMetadataReader: Sendable {
    public init() {}

    public func read(_ url: URL) -> (captureDate: Date?, rating: Int?) {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return (nil, nil) }
        var stars = rating(source)
        // macOS does not expose the XMP that Fujifilm RAF files carry inside their embedded JPEG,
        // so for RAF read the rating digit straight from that block (same scan the writer uses).
        if stars == nil, PhotoFormat(fileExtension: url.pathExtension) == .raf,
           let data = try? Data(contentsOf: url, options: .alwaysMapped),
           let offset = try? RatingWriter.digitOffset(in: data) {
            stars = Int(data[offset] - UInt8(ascii: "0"))
        }
        return (captureDate(source), stars)
    }

    private func captureDate(_ source: CGImageSource) -> Date? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        return Self.parse(text)
    }

    /// Parses "yyyy:MM:dd HH:mm:ss" (camera clock time, no time zone stored). Done by hand because
    /// building a DateFormatter per file is slow; the result is read in the current time zone.
    private static func parse(_ text: String) -> Date? {
        let parts = text.split(whereSeparator: { $0 == ":" || $0 == " " }).compactMap { Int($0) }
        guard parts.count == 6 else { return nil }
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute, c.second) = (parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])
        return Calendar(identifier: .gregorian).date(from: c)
    }

    private func rating(_ source: CGImageSource) -> Int? {
        guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let tag = CGImageMetadataCopyTagWithPath(metadata, nil, "xmp:Rating" as CFString),
              let value = CGImageMetadataTagCopyValue(tag) else { return nil }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }
}
