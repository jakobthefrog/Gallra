import Testing
import Foundation
@testable import GallraCore

@Suite struct SceneArrangerTests {
    private func photo(_ name: String, _ t: Double) -> Photo {
        Photo(id: PhotoID(volume: "v", fileNumber: 1, path: "/x/\(name).cr3"), format: .cr3, fileSize: 1,
              modified: .distantPast, captureDate: Date(timeIntervalSince1970: 1000 + t))
    }
    private let a = "a", b = "b", c = "c", d = "d"

    @Test func movedPhotoLeavesItsSceneAndJoinsTheManualGroup() {
        let p = [photo("a", 0), photo("b", 5), photo("c", 10), photo("d", 500)]
        let auto = [PhotoScene(id: 0, photos: p[0...2].map(\.id), start: p[0].captureDate),
                    PhotoScene(id: 1, photos: [p[3].id], start: p[3].captureDate)]
        let r = SceneArranger.apply(manual: ["/x/b.cr3": "g1", "/x/d.cr3": "g1"], photos: p, to: auto)
        #expect(r.count == 2)
        #expect(r[0].photos.map(\.path) == ["/x/a.cr3", "/x/c.cr3"])
        #expect(r[0].manualID == nil)
        #expect(r[1].photos.map(\.path) == ["/x/b.cr3", "/x/d.cr3"])
        #expect(r[1].manualID == "g1")
        #expect(r.map(\.id) == [0, 1])
    }

    @Test func emptiedAutomaticSceneDisappears() {
        let p = [photo("a", 0), photo("b", 5)]
        let auto = [PhotoScene(id: 0, photos: [p[0].id], start: p[0].captureDate),
                    PhotoScene(id: 1, photos: [p[1].id], start: p[1].captureDate)]
        let r = SceneArranger.apply(manual: ["/x/a.cr3": "g"], photos: p, to: auto)
        #expect(r.count == 2)
        #expect(r.filter { $0.manualID == nil }.count == 1)
    }

    @Test func unknownPathsAreIgnored() {
        let p = [photo("a", 0)]
        let auto = [PhotoScene(id: 0, photos: [p[0].id], start: p[0].captureDate)]
        let r = SceneArranger.apply(manual: ["/gone.cr3": "g"], photos: p, to: auto)
        #expect(r.count == 1)
    }

    @Test func manualGroupsSurviveInCatalog() async throws {
        let cat = try Catalog(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("gallra-mg-\(UUID().uuidString)/c.sqlite"))
        try await cat.setManualGroups(["/x/a.cr3": "g1", "/x/b.cr3": "g1"], folder: "/x")
        try await cat.setManualGroups(["/x/b.cr3": "g2"], folder: "/x")
        let loaded = try await cat.manualGroups(inFolder: "/x")
        #expect(loaded == ["/x/a.cr3": "g1", "/x/b.cr3": "g2"])
        #expect(try await cat.manualGroups(inFolder: "/y").isEmpty)
        try await cat.removeManualGroups(paths: ["/x/a.cr3"])
        #expect(try await cat.manualGroups(inFolder: "/x") == ["/x/b.cr3": "g2"])
    }
}
