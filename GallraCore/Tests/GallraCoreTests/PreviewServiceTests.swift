import Testing
import Foundation
import ImageIO
@testable import GallraCore

@Suite struct PreviewServiceTests {
    private func service() -> PreviewService {
        PreviewService(diskFolder: FileManager.default.temporaryDirectory
            .appendingPathComponent("gallra-prev-\(UUID().uuidString)"))
    }

    private func pixelWidth(_ data: Data) -> Int? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return nil }
        return props[kCGImagePropertyPixelWidth] as? Int
    }

    @Test func extractsJPEGForBothFormats() async throws {
        let dir = try Scratch.folder(cr3: 1, threeFR: 1)
        let service = service()
        for photo in try FolderBrowser().photos(in: dir) {
            let full = try await service.preview(for: photo, size: .full)
            #expect((pixelWidth(full) ?? 0) >= 2000, "\(photo.fileName) full preview too small")
            let thumb = try await service.preview(for: photo, size: .thumbnail)
            let width = try #require(pixelWidth(thumb))
            #expect(width <= 320 && width > 0)
        }
    }

    @Test func secondRequestHitsMemoryThenDisk() async throws {
        let dir = try Scratch.folder(cr3: 1, threeFR: 0)
        let photo = try #require(try FolderBrowser().photos(in: dir).first)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gallra-prev-\(UUID().uuidString)")

        let first = PreviewService(diskFolder: folder)
        _ = try await first.preview(for: photo, size: .full)
        _ = try await first.preview(for: photo, size: .full)
        #expect(await first.extractions == 1)
        #expect(await first.memoryHits == 1)

        let restarted = PreviewService(diskFolder: folder)   // empty memory, same disk cache
        _ = try await restarted.preview(for: photo, size: .full)
        #expect(await restarted.diskHits == 1)
        #expect(await restarted.extractions == 0)
    }

    @Test func prefetchWarmsCache() async throws {
        let dir = try Scratch.folder(cr3: 2, threeFR: 2)
        let photos = try FolderBrowser().photos(in: dir)
        let service = service()
        await service.prefetch(photos, size: .full)
        for _ in 0..<100 where await service.extractions < photos.count {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(await service.extractions == photos.count)
        _ = try await service.preview(for: photos[0], size: .full)
        #expect(await service.memoryHits == 1)
    }

    @Test func cachedPreviewIsFast() async throws {
        let dir = try Scratch.folder(cr3: 1, threeFR: 1)
        let service = service()
        for photo in try FolderBrowser().photos(in: dir) {
            _ = try await service.preview(for: photo, size: .full)
            let start = ContinuousClock.now
            _ = try await service.preview(for: photo, size: .full)
            let elapsed = ContinuousClock.now - start
            #expect(elapsed < .milliseconds(50), "cached preview took \(elapsed)")
        }
    }

    @Test func sourceFileIsUnchangedAfterPreviews() async throws {
        let dir = try Scratch.folder(cr3: 1, threeFR: 1)
        let photos = try FolderBrowser().photos(in: dir)
        let before = try photos.map { try Data(contentsOf: $0.url) }
        let service = service()
        for photo in photos { _ = try await service.preview(for: photo, size: .full) }
        #expect(try photos.map { try Data(contentsOf: $0.url) } == before)
    }
}
