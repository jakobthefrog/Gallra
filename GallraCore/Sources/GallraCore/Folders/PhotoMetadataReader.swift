import Foundation
import ImageIO

/// Reads capture date and star rating from a RAW file via ImageIO (read-only, ~1-10 ms).
public struct PhotoMetadataReader: Sendable {
    public init() {}

    public func read(_ url: URL) -> (captureDate: Date?, rating: Int?) {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return (nil, nil) }
        return (captureDate(source), rating(source))
    }

    private func captureDate(_ source: CGImageSource) -> Date? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"   // camera clock time, no time zone stored
        return formatter.date(from: text)
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
