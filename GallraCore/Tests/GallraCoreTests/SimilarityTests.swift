import Testing
import Foundation
@testable import GallraCore

@Suite struct SimilarityTests {
    private func makeService() throws -> SimilarityService {
        let tmp = FileManager.default.temporaryDirectory
        let catalog = try Catalog(url: tmp.appendingPathComponent("gallra-sim-\(UUID().uuidString)/c.sqlite"))
        let previews = PreviewService(diskFolder: tmp.appendingPathComponent("gallra-pv-\(UUID().uuidString)"))
        return SimilarityService(previews: previews, catalog: catalog)
    }

    /// Sample burst shots (seconds apart, visually alike) group; unrelated shots stay apart.
    @Test func groupsBurstsAndSeparatesOtherScenes() async throws {
        var photos: [Photo] = []
        for var p in try FolderBrowser().photos(in: Scratch.samples) where p.format == .cr3 {
            p.captureDate = PhotoMetadataReader().read(p.url).captureDate
            photos.append(p)
        }
        let scenes = await (try makeService()).scenes(for: photos)
        func sceneOf(_ name: String) -> Int? { scenes.first { $0.photos.contains { $0.path.hasSuffix(name) } }?.id }
        #expect(sceneOf("_A0A7515.CR3") == sceneOf("_A0A7516.CR3"))
        #expect(sceneOf("_A0A7713.CR3") == sceneOf("_A0A7714.CR3"))
        #expect(sceneOf("_A0A7516.CR3") != sceneOf("_A0A7535.CR3"))
        #expect(scenes.flatMap(\.photos).count == photos.count)   // every photo in exactly one scene
    }

    @Test func printsAreCachedInCatalog() async throws {
        let tmp = FileManager.default.temporaryDirectory
        let catalog = try Catalog(url: tmp.appendingPathComponent("gallra-sim-\(UUID().uuidString)/c.sqlite"))
        let previews = PreviewService(diskFolder: tmp.appendingPathComponent("gallra-pv-\(UUID().uuidString)"))
        let photo = try #require(try FolderBrowser().photos(in: Scratch.samples).first { $0.format == .cr3 })
        _ = await SimilarityService(previews: previews, catalog: catalog).scenes(for: [photo])
        #expect(try await catalog.featurePrint(id: photo.id.path, fileSize: photo.fileSize) != nil)
    }
}
