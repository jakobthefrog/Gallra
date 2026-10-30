import AppKit
import ImageIO
import GallraCore

/// Decoded-image cache for the views. Asks `PreviewService` for JPEG data, decodes it off the
/// main thread, and keeps recent images in memory so next/previous is instant.
@MainActor
final class ImageStore {
    private let previews: PreviewService
    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    init(previews: PreviewService) {
        self.previews = previews
        cache.totalCostLimit = 1_500 * 1024 * 1024
    }

    private func key(_ photo: Photo, _ size: PreviewSize) -> String { "\(size.rawValue)|\(photo.id.rawValue)" }

    /// Already-decoded image, if any (no waiting).
    func cached(_ photo: Photo, size: PreviewSize) -> NSImage? {
        cache.object(forKey: key(photo, size) as NSString)
    }

    /// Decoded image, loading it if needed. Returns nil if the file has no readable preview.
    func image(_ photo: Photo, size: PreviewSize) async -> NSImage? {
        let k = key(photo, size)
        if let hit = cache.object(forKey: k as NSString) { return hit }
        if let task = inFlight[k] { return await task.value }
        let previews = self.previews
        let task = Task<NSImage?, Never> {
            guard let data = try? await previews.preview(for: photo, size: size) else { return nil }
            return await Task.detached(priority: .userInitiated) { Self.decode(data) }.value
        }
        inFlight[k] = task
        let image = await task.value
        inFlight[k] = nil
        if let image {
            cache.setObject(image, forKey: k as NSString, cost: Int(image.size.width * image.size.height * 4))
        }
        return image
    }

    /// Warms disk and memory caches for photos likely to be shown next.
    func prefetch(_ photos: [Photo], size: PreviewSize) {
        for photo in photos { Task { _ = await image(photo, size: size) } }
    }

    nonisolated private static func decode(_ data: Data) -> NSImage? {
        let opts = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, opts) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
