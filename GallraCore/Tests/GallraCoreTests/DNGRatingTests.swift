import Testing
import Foundation
@testable import GallraCore

/// Ratings on DNG files from drones (DJI) and DNGs re-saved by Lightroom. Runs on COPIES only.
@Suite struct DNGRatingTests {
    @Test func everySampleDNGTakesARating() throws {
        let fm = FileManager.default
        let names = try fm.contentsOfDirectory(atPath: Scratch.samples.path)
            .filter { $0.lowercased().hasSuffix(".dng") }.sorted()
        try #require(!names.isEmpty)
        let dir = fm.temporaryDirectory.appendingPathComponent("gallra-dng-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        for name in names {
            let original = Scratch.samples.appendingPathComponent(name)
            let before = try fm.attributesOfItem(atPath: original.path)[.modificationDate] as? Date
            let copy = dir.appendingPathComponent(name)
            try fm.copyItem(at: original, to: copy)
            for stars in [3, 1, 0] {
                try RatingWriter().write(rating: stars, to: copy)
                #expect(PhotoMetadataReader().read(copy).rating == stars, "\(name): rating \(stars) did not read back")
            }
            #expect(try fm.attributesOfItem(atPath: original.path)[.modificationDate] as? Date == before, "\(name): original was touched")
        }
        // No leftover temp or backup files next to the copies.
        #expect(try fm.contentsOfDirectory(atPath: dir.path).allSatisfy { !$0.hasPrefix(".gallra-") })
    }
}
