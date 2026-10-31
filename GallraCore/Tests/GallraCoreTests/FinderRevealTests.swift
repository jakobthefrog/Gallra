import Foundation
import Testing
@testable import GallraCore

struct FinderRevealTests {
    @Test func foldersOpenAndFilesAreSelected() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("finder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)

        #expect(FinderReveal.action(for: dir) == .open(dir))
        #expect(FinderReveal.action(for: file) == .select(file))
        #expect(FinderReveal.action(for: dir.appendingPathComponent("missing")) == .none)
    }
}
