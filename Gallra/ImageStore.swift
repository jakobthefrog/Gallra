import AppKit
import ImageIO
import GallraCore

/// Decoded-image cache for the views. Asks `PreviewService` for JPEG data, decodes it off the
/// main thread, and keeps recent images in memory so next/previous is instant.
///
/// Loads are cancellable: when a view stops waiting (you moved on to another photo) and nobody
/// else wants the image, it is never started. Big previews and thumbnails have separate lanes
/// with a limited number of simultaneous loads, so one can never starve the other.
@MainActor
final class ImageStore {
    private let previews: PreviewService
    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: (task: Task<NSImage?, Never>, waiters: Int)] = [:]
    private let fullLane = Lane(slots: 2)
    private let thumbnailLane = Lane(slots: 4)
    private var prefetchTask: Task<Void, Never>?

    init(previews: PreviewService) {
        self.previews = previews
        cache.totalCostLimit = 1_500 * 1024 * 1024
    }

    private func key(_ photo: Photo, _ size: PreviewSize) -> String { "\(size.rawValue)|\(photo.id.rawValue)" }

    /// Already-decoded image, if any (no waiting).
    func cached(_ photo: Photo, size: PreviewSize) -> NSImage? {
        cache.object(forKey: key(photo, size) as NSString)
    }

    /// Decoded image, loading it if needed. Returns nil if the file has no readable preview,
    /// or if the calling task was cancelled first. `delay` waits that long before starting, so
    /// photos you only fly past are never loaded.
    func image(_ photo: Photo, size: PreviewSize, delay: Duration = .zero) async -> NSImage? {
        let k = key(photo, size)
        if let hit = cache.object(forKey: k as NSString) { return hit }

        if inFlight[k] != nil {
            inFlight[k]?.waiters += 1
        } else {
            let lane = size == .full ? fullLane : thumbnailLane
            let previews = self.previews
            let task = Task<NSImage?, Never> { [weak self] in
                if delay > .zero { try? await Task.sleep(for: delay) }
                if Task.isCancelled { return nil }
                guard await lane.acquire() else { return nil }
                defer { lane.release() }
                guard let data = try? await previews.preview(for: photo, size: size) else { return nil }
                let image = await Task.detached(priority: .userInitiated) { Self.decode(data) }.value
                if let image {
                    self?.cache.setObject(image, forKey: k as NSString, cost: Int(image.size.width * image.size.height * 4))
                }
                return image
            }
            inFlight[k] = (task, 1)
        }
        guard let task = inFlight[k]?.task else { return nil }

        let image = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor [weak self] in self?.stopWaiting(k) }
        }
        if !Task.isCancelled { inFlight[k] = nil }
        return image
    }

    /// One caller gave up; if nobody is left waiting, cancel the load.
    private func stopWaiting(_ k: String) {
        guard var entry = inFlight[k] else { return }
        entry.waiters -= 1
        if entry.waiters <= 0 {
            entry.task.cancel()
            inFlight[k] = nil
        } else {
            inFlight[k] = entry
        }
    }

    /// Warms memory for photos likely to be shown next, one after another, once you pause.
    /// A new call replaces the previous one.
    func prefetch(_ photos: [Photo], size: PreviewSize) {
        prefetchTask?.cancel()
        prefetchTask = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            for photo in photos {
                if Task.isCancelled { return }
                _ = await self?.image(photo, size: size)
            }
        }
    }

    nonisolated private static func decode(_ data: Data) -> NSImage? {
        let opts = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, opts) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

/// Lets a few loads run at once. Waiters can be cancelled, and the newest waiter goes first
/// (when scrolling fast, the photo you last landed on matters most).
@MainActor
private final class Lane {
    private var free: Int
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

    init(slots: Int) { free = slots }

    /// Waits for a free slot. Returns false if the caller was cancelled while waiting.
    func acquire() async -> Bool {
        if Task.isCancelled { return false }
        if free > 0 { free -= 1; return true }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { waiters.append((id, $0)) }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(id) }
        }
    }

    func release() {
        if let next = waiters.popLast() { next.continuation.resume(returning: true) } else { free += 1 }
    }

    private func cancel(_ id: UUID) {
        guard let i = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: i).continuation.resume(returning: false)
    }
}
