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

@Suite struct ScanTreeTests {
    /// Root with 2 photos, `a/b` with 2 photos, and a Rejected folder with 1 photo (all copies).
    private func nestedFolder() throws -> URL {
        let fm = FileManager.default
        let root = try Scratch.folder(cr3: 1, threeFR: 1)
        let deep = root.appendingPathComponent("a/b", isDirectory: true)
        let rejected = root.appendingPathComponent(FolderBrowser.rejectedFolderName, isDirectory: true)
        try fm.createDirectory(at: deep, withIntermediateDirectories: true)
        try fm.createDirectory(at: rejected, withIntermediateDirectories: true)
        let files = try fm.contentsOfDirectory(atPath: root.path).filter { RawFormat(fileExtension: ($0 as NSString).pathExtension) != nil }
        for name in files {
            try fm.copyItem(at: root.appendingPathComponent(name), to: deep.appendingPathComponent(name))
        }
        try fm.copyItem(at: root.appendingPathComponent(files[0]), to: rejected.appendingPathComponent(files[0]))
        return root
    }

    @Test func treeScanFindsNestedPhotosAndSkipsRejected() async throws {
        let root = try nestedFolder()
        let catalog = try Catalog(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("gallra-cat-\(UUID().uuidString)/catalog.sqlite"))
        let scanner = FolderScanner(catalog: catalog)

        #expect(try await scanner.scan(root).count == 2)
        let all = try await scanner.scanTree(root)
        #expect(all.count == 4)
        #expect(!all.contains { $0.id.path.contains(FolderBrowser.rejectedFolderName) })
        #expect(Set(all.map(\.folderPath)).count == 2)
    }
}

@Suite struct SubfolderDetectionTests {
    @Test func onlyFoldersWithPhotosCount() throws {
        let fm = FileManager.default
        let root = try Scratch.folder(cr3: 1, threeFR: 1)
        try fm.createDirectory(at: root.appendingPathComponent("Exports"), withIntermediateDirectories: true)
        let rejected = root.appendingPathComponent(FolderBrowser.rejectedFolderName)
        try fm.createDirectory(at: rejected, withIntermediateDirectories: true)
        let name = try fm.contentsOfDirectory(atPath: root.path).first { $0.lowercased().hasSuffix("cr3") }!
        try fm.copyItem(at: root.appendingPathComponent(name), to: rejected.appendingPathComponent(name))
        #expect(!FolderScanner.hasPhotosInSubfolders(of: root))

        let shoot = root.appendingPathComponent("Shoot")
        try fm.createDirectory(at: shoot, withIntermediateDirectories: true)
        try fm.copyItem(at: root.appendingPathComponent(name), to: shoot.appendingPathComponent(name))
        #expect(FolderScanner.hasPhotosInSubfolders(of: root))
    }
}

@Suite struct ClearCacheTests {
    @Test func clearKeepsFavoritesAndGroups() async throws {
        let dir = try Scratch.folder()
        let catalog = try Catalog(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("gallra-cat-\(UUID().uuidString)/catalog.sqlite"))
        let folder = FolderScanner.canonicalPath(dir)
        _ = try await FolderScanner(catalog: catalog).scan(dir)
        try await catalog.addFavorite("/some/folder")
        try await catalog.setManualGroups(["/a.cr3": "g1"], folder: folder)
        #expect(catalog.fileBytes() > 0)

        try await catalog.clearCache()
        #expect(try await catalog.photos(inFolder: folder).isEmpty)
        #expect(try await catalog.favorites() == ["/some/folder"])
        #expect(try await catalog.manualGroups(inFolder: folder) == ["/a.cr3": "g1"])
    }
}
