import Foundation
import ImageIO
import CryptoKit
import UniformTypeIdentifiers

/// Size of a preview. Previews are always returned as ready-made JPEG data.
public enum PreviewSize: String, Codable, Sendable {
    /// About 320 px on the long edge, for the grid.
    case thumbnail
    /// The camera's full embedded preview, for the viewer.
    case full

    var maxPixel: Int? { self == .thumbnail ? 320 : nil }
}

public enum PreviewError: Error, Sendable {
    case cannotRead
    case cannotEncode
}

/// Serves fast previews: memory cache, then disk cache, then extraction of the embedded
/// JPEG from the RAW via ImageIO (never a full RAW decode). Decoding runs off the main thread.
public actor PreviewService {
    private let diskFolder: URL
    private let memory = NSCache<NSString, NSData>()
    private var inFlight: [String: Task<Data, Error>] = [:]
    private var prefetchTask: Task<Void, Never>?

    /// Counters for tests and tuning.
    public private(set) var memoryHits = 0
    public private(set) var diskHits = 0
    public private(set) var extractions = 0

    /// Default disk cache: `~/Library/Application Support/Gallra/Previews`.
    public static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gallra/Previews")
    }

    public init(diskFolder: URL = PreviewService.defaultFolder, memoryLimitBytes: Int = 512 * 1024 * 1024) {
        self.diskFolder = diskFolder
        memory.totalCostLimit = memoryLimitBytes
        try? FileManager.default.createDirectory(at: diskFolder, withIntermediateDirectories: true)
    }

    /// JPEG data for `photo` at `size`.
    public func preview(for photo: Photo, size: PreviewSize) async throws -> Data {
        let key = cacheKey(photo, size)
        if let hit = memory.object(forKey: key as NSString) { memoryHits += 1; return hit as Data }
        if let running = inFlight[key] { return try await running.value }

        let diskURL = diskFolder.appendingPathComponent(key + ".jpg")
        let source = photo.url
        let task = Task.detached(priority: .userInitiated) { () throws -> (Data, Bool) in
            if let data = try? Data(contentsOf: diskURL) { return (data, true) }
            let data = try PreviewService.extract(from: source, maxPixel: size.maxPixel)
            try? data.write(to: diskURL, options: .atomic)   // cache file only, never a user file
            return (data, false)
        }
        let wrapper = Task { try await task.value.0 }
        inFlight[key] = wrapper
        defer { inFlight[key] = nil }
        let (data, fromDisk) = try await task.value
        if fromDisk { diskHits += 1 } else { extractions += 1 }
        memory.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        return data
    }

    /// Warms the caches for `photos` (e.g. the neighbours of the current photo), in order.
    /// A new call cancels the previous prefetch.
    public func prefetch(_ photos: [Photo], size: PreviewSize) {
        prefetchTask?.cancel()
        prefetchTask = Task(priority: .utility) { [weak self] in
            for photo in photos {
                if Task.isCancelled { return }
                _ = try? await self?.preview(for: photo, size: size)
            }
        }
    }

    /// Total size in bytes of the preview files on disk.
    public func diskCacheBytes() -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: diskFolder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    /// Deletes the disk cache (previews are rebuilt on demand).
    public func clearDiskCache() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: diskFolder)
        try? FileManager.default.createDirectory(at: diskFolder, withIntermediateDirectories: true)
    }

    // MARK: Internals

    private func cacheKey(_ photo: Photo, _ size: PreviewSize) -> String {
        let raw = "v2|\(photo.id.rawValue)|\(photo.modified.timeIntervalSince1970)|\(photo.fileSize)|\(size.rawValue)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func longEdge(of source: CGImageSource) -> Int {
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        return max(w, h, 1)
    }

    /// Reads the embedded preview and encodes it as JPEG, downscaled if `maxPixel` is set.
    nonisolated static func extract(from url: URL, maxPixel: Int?) throws -> Data {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { throw PreviewError.cannotRead }
        // Both sizes go through the thumbnail call because it applies the photo's orientation
        // (portraits upright). For the full size the limit is the image's own long edge.
        let limit = maxPixel ?? PreviewService.longEdge(of: source)
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
        ] as CFDictionary)
        guard let image else { throw PreviewError.cannotRead }

        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw PreviewError.cannotEncode }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw PreviewError.cannotEncode }
        return data as Data
    }
}
