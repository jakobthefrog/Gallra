import Testing
import Foundation
@testable import GallraCore

@Suite struct CameraInfoTests {
    @Test func summaryLeavesOutMissingFields() {
        #expect(CameraInfo().summary == "")
        let info = CameraInfo(lens: "RF 85mm", aperture: 2.8, shutter: 1.0 / 200, iso: 400, focalLength: 85)
        #expect(info.summary == "RF 85mm · 85 mm · f/2.8 · 1/200 · ISO 400")
        #expect(CameraInfo(aperture: 8, shutter: 2).summary == "f/8 · 2 s")
    }

    @Test func readsSettingsFromRealFiles() throws {
        let dir = try Scratch.folder(cr3: 1, threeFR: 1)
        for photo in try FolderBrowser().photos(in: dir) {
            let info = PhotoMetadataReader().cameraInfo(photo.url)
            #expect(info.aperture != nil && info.iso != nil, "\(photo.fileName) has no camera info")
        }
    }
}
