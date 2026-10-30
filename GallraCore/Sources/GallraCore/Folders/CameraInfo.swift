import Foundation
import ImageIO

/// Shooting details of one photo, read from its EXIF data (read-only).
public struct CameraInfo: Sendable, Equatable {
    public var lens: String?
    public var aperture: Double?
    public var shutter: Double?      // seconds
    public var iso: Int?
    public var focalLength: Double?  // mm

    public init(lens: String? = nil, aperture: Double? = nil, shutter: Double? = nil,
                iso: Int? = nil, focalLength: Double? = nil) {
        self.lens = lens; self.aperture = aperture; self.shutter = shutter
        self.iso = iso; self.focalLength = focalLength
    }

    /// "RF 85mm · 85 mm · f/2.8 · 1/200 · ISO 400", leaving out whatever the file doesn't have.
    public var summary: String {
        var parts: [String] = []
        if let lens { parts.append(lens) }
        if let focalLength { parts.append("\(Int(focalLength.rounded())) mm") }
        if let aperture { parts.append("f/" + Self.number(aperture)) }
        if let shutter, shutter > 0 {
            parts.append(shutter >= 1 ? Self.number(shutter) + " s" : "1/\(Int((1 / shutter).rounded()))")
        }
        if let iso { parts.append("ISO \(iso)") }
        return parts.joined(separator: " · ")
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

extension PhotoMetadataReader {
    /// Lens, aperture, shutter, ISO and focal length of `url`; nil fields when missing.
    public func cameraInfo(_ url: URL) -> CameraInfo {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] else { return CameraInfo() }
        return CameraInfo(
            lens: exif[kCGImagePropertyExifLensModel] as? String,
            aperture: (exif[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue,
            shutter: (exif[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue,
            iso: ((exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first ?? exif[kCGImagePropertyExifISOSpeed] as? NSNumber)?.intValue,
            focalLength: (exif[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue)
    }
}
