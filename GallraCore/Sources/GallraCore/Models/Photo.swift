import Foundation

/// The photo file formats Gallra understands (RAW and ready-made images).
public enum PhotoFormat: String, Codable, Sendable, CaseIterable {
    case cr3
    case threeFR = "3fr"
    case dng
    case jpg
    case tiff
    case heic
    case arw    // Sony
    case nef    // Nikon
    case raf    // Fujifilm
    case cr2    // Canon (older)
    case orf    // Olympus / OM System
    case rw2    // Panasonic

    /// Returns the format for a file extension (case-insensitive), or nil if unsupported.
    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "cr3": self = .cr3
        case "3fr": self = .threeFR
        case "dng": self = .dng
        case "jpg", "jpeg": self = .jpg
        case "tif", "tiff": self = .tiff
        case "heic", "heif", "hif": self = .heic
        case "arw": self = .arw
        case "nef": self = .nef
        case "raf": self = .raf
        case "cr2": self = .cr2
        case "orf": self = .orf
        case "rw2": self = .rw2
        default: return nil
        }
    }

    /// Formats whose rating writing has been tried on real files. Others open and preview but are never written to.
    var ratingWriteTested: Bool {
        switch self {
        case .cr3, .threeFR, .dng, .jpg, .tiff, .raf: true
        default: false
        }
    }

    /// True for formats where ImageIO can add a rating by copying the file without re-encoding pixels.
    var supportsMetadataRewrite: Bool { self == .jpg || self == .tiff || self == .dng }
}

/// Stable identity of a photo: volume + file number + path, never view state.
public struct PhotoID: Codable, Hashable, Sendable {
    public let volume: String
    public let fileNumber: UInt64
    public let path: String

    public init(volume: String, fileNumber: UInt64, path: String) {
        self.volume = volume
        self.fileNumber = fileNumber
        self.path = path
    }

    /// Single-string form used as database key and cache key.
    public var rawValue: String { "\(volume):\(fileNumber):\(path)" }
}

/// One photo file on disk, with the metadata the catalog caches.
public struct Photo: Codable, Hashable, Sendable, Identifiable {
    public let id: PhotoID
    public let format: PhotoFormat
    public let fileSize: Int64
    public let modified: Date
    /// When the shot was taken (EXIF), if the file says.
    public var captureDate: Date?
    /// Star rating 0-5 as stored in the file; nil if the file has no rating field (counts as unrated).
    public var rating: Int?

    public init(id: PhotoID, format: PhotoFormat, fileSize: Int64, modified: Date,
                captureDate: Date? = nil, rating: Int? = nil) {
        self.id = id
        self.format = format
        self.fileSize = fileSize
        self.modified = modified
        self.captureDate = captureDate
        self.rating = rating
    }

    public var url: URL { URL(fileURLWithPath: id.path) }
    public var fileName: String { url.lastPathComponent }
    /// Folder containing the file.
    public var folderPath: String { url.deletingLastPathComponent().path }
}

/// A subfolder shown in the sidebar.
public struct FolderNode: Codable, Hashable, Sendable, Identifiable {
    public let path: String
    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    public var name: String { url.lastPathComponent }

    public init(path: String) { self.path = path }
}
