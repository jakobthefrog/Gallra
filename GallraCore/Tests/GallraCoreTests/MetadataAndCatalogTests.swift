import Testing
import Foundation
@testable import GallraCore

@Suite struct MetadataAndCatalogTests {
    private func tempCatalog() throws -> Catalog {
        try Catalog(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("gallra-cat-\(UUID().uuidString)/catalog.sqlite"))
    }

    @Test func readsRatingAndCaptureDate() throws {
        let dir = try Scratch.folder(cr3: 2, threeFR: 2)
        for photo in try FolderBrowser().photos(in: dir) {
            let meta = PhotoMetadataReader().read(photo.url)
            #expect(meta.rating != nil, "no rating read for \(photo.fileName)")
            #expect(meta.captureDate != nil, "no capture date for \(photo.fileName)")
        }
    }

    @Test func scanFillsCatalogAndSecondScanUsesIt() async throws {
        let dir = try Scratch.folder()
        let catalog = try tempCatalog()
        let scanner = FolderScanner(catalog: catalog)

        let first = try await scanner.scan(dir)
        #expect(first.count == 4)
        let cached = try await catalog.photos(inFolder: FolderScanner.canonicalPath(dir))
        #expect(Set(cached.map(\.id)) == Set(first.map(\.id)))
        #expect(cached.map(\.rating) == first.map(\.rating))
        #expect(cached.map(\.captureDate) == first.map(\.captureDate))

        let second = try await scanner.scan(dir)
        #expect(second == first)
    }

    @Test func scanDropsFilesThatDisappear() async throws {
        let dir = try Scratch.folder()
        let catalog = try tempCatalog()
        let scanner = FolderScanner(catalog: catalog)
        let before = try await scanner.scan(dir)
        try FileManager.default.removeItem(at: before[0].url)   // scratch copy only
        let after = try await scanner.scan(dir)
        #expect(after.count == before.count - 1)
        let cached = try await catalog.photos(inFolder: FolderScanner.canonicalPath(dir))
        #expect(cached.count == after.count)
    }

    @Test func favoritesKeepOrderAndIgnoreDuplicates() async throws {
        let catalog = try tempCatalog()
        try await catalog.addFavorite("/a")
        try await catalog.addFavorite("/b")
        try await catalog.addFavorite("/a")
        #expect(try await catalog.favorites() == ["/a", "/b"])
        try await catalog.removeFavorite("/a")
        #expect(try await catalog.favorites() == ["/b"])
    }
}
