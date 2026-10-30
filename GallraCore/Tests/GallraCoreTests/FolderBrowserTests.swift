import Testing
import Foundation
@testable import GallraCore

@Suite struct FolderBrowserTests {
    @Test func listsOnlyRawFilesAndSubfolders() throws {
        let dir = try Scratch.folder(cr3: 2, threeFR: 1)
        try Data("x".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sub"), withIntermediateDirectories: false)

        let browser = FolderBrowser()
        let photos = try browser.photos(in: dir)
        #expect(photos.count == 3)
        #expect(Set(photos.map(\.format)) == [.cr3, .threeFR])
        #expect(try browser.subfolders(of: dir).map(\.name) == ["Sub"])
    }

    @Test func photoIDsAreStableAndUnique() throws {
        let dir = try Scratch.folder()
        let first = try FolderBrowser().photos(in: dir)
        let second = try FolderBrowser().photos(in: dir)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(Set(first.map(\.id)).count == first.count)
    }

    @Test func reportsChanges() async throws {
        let dir = try Scratch.folder(cr3: 0, threeFR: 0)
        var iterator = FolderBrowser().changes(in: dir).makeAsyncIterator()
        try Data("x".utf8).write(to: dir.appendingPathComponent("new.txt"))
        let event: Void? = await iterator.next()
        #expect(event != nil)
    }
}
