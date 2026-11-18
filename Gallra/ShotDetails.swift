import Foundation
import GallraCore

/// How a photo's shooting details are written in every panel: date, time, shutter, aperture, ISO, focal length.
/// Date is Swedish numeric (2026-11-13), time is 24-hour (14:32). No lens anywhere.
enum ShotDetails {
    /// Fixed format and locale so the time is always 24-hour, whatever the Mac's settings.
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
    // Used on the main thread by views only.
    private static let dateFormatter = formatter("yyyy-MM-dd")
    private static let timeFormatter = formatter("HH:mm")

    static func date(_ photo: Photo) -> String? { photo.captureDate.map(dateFormatter.string(from:)) }
    static func time(_ photo: Photo) -> String? { photo.captureDate.map(timeFormatter.string(from:)) }

    static func shutter(_ info: CameraInfo) -> String? {
        guard let s = info.shutter, s > 0 else { return nil }
        return s >= 1 ? number(s) + " s" : "1/\(Int((1 / s).rounded()))"
    }
    static func aperture(_ info: CameraInfo) -> String? { info.aperture.map { "f/" + number($0) } }
    static func iso(_ info: CameraInfo) -> String? { info.iso.map { "ISO \($0)" } }
    static func focalLength(_ info: CameraInfo) -> String? { info.focalLength.map { "\(Int($0.rounded())) mm" } }

    /// Label and value for each detail, in display order; nil where the file has no value.
    static func rows(_ photo: Photo, _ info: CameraInfo?) -> [(label: String, value: String?)] {
        [("Date", date(photo)), ("Time", time(photo)),
         ("Shutter", info.flatMap(shutter)), ("Aperture", info.flatMap(aperture)),
         ("ISO", info?.iso.map(String.init)), ("Focal length", info.flatMap(focalLength))]
    }

    /// One line for the status bar: "2026-11-13 · 14:32 · 1/200 · f/2.8 · ISO 400 · 85 mm", skipping what's missing.
    static func summary(_ photo: Photo, _ info: CameraInfo) -> String {
        [date(photo), time(photo), shutter(info), aperture(info), iso(info), focalLength(info)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
