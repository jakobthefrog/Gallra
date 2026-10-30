import Testing
import Foundation
@testable import GallraCore

@Suite struct CullTests {
    private func firstPhoto(_ dir: URL, _ ext: String) throws -> Photo {
        try #require(try FolderBrowser().photos(in: dir).first { $0.format.rawValue == ext })
    }

    @Test(arguments: ["cr3", "3fr"]) func ratingWriteChangesOneByteAndRoundTrips(ext: String) throws {
        let dir = try Scratch.folder(cr3: 1, threeFR: 1)
        let photo = try firstPhoto(dir, ext)
        let before = try Data(contentsOf: photo.url)
        let original = PhotoMetadataReader().read(photo.url).rating ?? 0
        for stars in [(original + 1) % 4, (original + 2) % 4, original] {
            try RatingWriter().write(rating: stars, to: photo.url)
            #expect(PhotoMetadataReader().read(photo.url).rating == stars)
        }
        #expect(try Data(contentsOf: photo.url) == before)   // back to the original rating = identical bytes
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".gallra-") }
        #expect(leftovers.isEmpty)
    }

    @Test func fileWithoutRatingFieldIsUntouched() throws {
        let dir = try Scratch.folder(cr3: 1, threeFR: 0)
        let url = try FolderBrowser().photos(in: dir)[0].url
        var data = try Data(contentsOf: url)
        let range = try #require(data.range(of: Data("Rating".utf8)))
        data.replaceSubrange(range, with: Data("Ratinx".utf8))   // break the field name
        try data.write(to: url)
        #expect(throws: RatingError.noRatingField) { try RatingWriter().write(rating: 2, to: url) }
        #expect(try Data(contentsOf: url) == data)
    }

    @Test func rejectMovesAndUndoRestores() throws {
        let dir = try Scratch.folder(cr3: 2, threeFR: 0)
        let photos = try FolderBrowser().photos(in: dir)
        let result = RejectService().reject([photos[0]])
        #expect(result.failures.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: photos[0].url.path))
        let rejected = dir.appendingPathComponent(FolderBrowser.rejectedFolderName)
        #expect(FileManager.default.fileExists(atPath: rejected.appendingPathComponent(photos[0].fileName).path))
        #expect(try FolderBrowser().photos(in: dir).count == 1)
        #expect(RejectService().undo(result.batch).isEmpty)
        #expect(try FolderBrowser().photos(in: dir).count == 2)
    }

    @Test func rejectNeverOverwritesSameName() throws {
        let dir = try Scratch.folder(cr3: 1, threeFR: 0)
        let photo = try FolderBrowser().photos(in: dir)[0]
        let copy = dir.appendingPathComponent("copy.cr3")
        try FileManager.default.copyItem(at: photo.url, to: copy)
        let first = RejectService().reject([photo])
        try FileManager.default.copyItem(at: copy, to: photo.url)   // same name again
        let again = RejectService().reject([try FolderBrowser().photos(in: dir).first { $0.fileName == photo.fileName }!])
        #expect(first.batch.files[0].moved != again.batch.files[0].moved)
        #expect(FileManager.default.fileExists(atPath: first.batch.files[0].moved.path))
    }

    @Test func filters() {
        func p(_ r: Int?) -> Photo {
            Photo(id: PhotoID(volume: "v", fileNumber: 1, path: "/x/a.cr3"), format: .cr3, fileSize: 1,
                  modified: .distantPast, rating: r)
        }
        let all = [p(nil), p(0), p(1), p(2), p(3)]
        #expect(RatingFilter.unrated.apply(to: all).count == 2)
        #expect(RatingFilter.anyStars.apply(to: all).count == 3)
        #expect(RatingFilter.twoStars.apply(to: all).count == 1)
        #expect(RatingFilter.all.apply(to: all).count == 5)
    }
}
