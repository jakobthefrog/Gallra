import Testing
import Foundation
@testable import GallraCore

/// Timing check on a big folder. Only runs when GALLRA_BIG_FOLDER points at one:
/// `GALLRA_BIG_FOLDER=~/Documents/Gallra-BigTest swift test --filter BigFolderBenchmark`
@Suite struct BigFolderBenchmark {
    @Test func scanAndThumbnails() async throws {
        guard let path = ProcessInfo.processInfo.environment["GALLRA_BIG_FOLDER"] else { return }
        let folder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(UUID().uuidString).sqlite")
        let catalog = try Catalog(url: dbURL)
        let scanner = FolderScanner(catalog: catalog)

        var t = ContinuousClock.now
        let photos = try await scanner.scan(folder)
        print("BENCH first scan: \(photos.count) photos in \(ContinuousClock.now - t)")
        t = ContinuousClock.now
        _ = try await scanner.scan(folder)
        print("BENCH repeat scan: \(ContinuousClock.now - t)")

        let service = PreviewService(diskFolder: FileManager.default.temporaryDirectory
            .appendingPathComponent("bench-prev-\(UUID().uuidString)"))
        t = ContinuousClock.now
        await withTaskGroup(of: Void.self) { group in
            for photo in photos.prefix(60) {
                group.addTask { _ = try? await service.preview(for: photo, size: .thumbnail) }
            }
        }
        print("BENCH 60 thumbnails cold: \(ContinuousClock.now - t)")
        t = ContinuousClock.now
        for photo in photos.prefix(60) { _ = try await service.preview(for: photo, size: .thumbnail) }
        print("BENCH 60 thumbnails warm: \(ContinuousClock.now - t)")
    }
}
