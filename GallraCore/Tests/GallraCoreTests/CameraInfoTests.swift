import Testing
import Foundation
@testable import GallraCore

@Suite struct CameraInfoTests {
    @Test func summaryLeavesOutMissingFields() {
        #expect(CameraInfo().summary == "")
        let info = CameraInfo(lens: "RF 85mm", aperture: 2.8, shutter: 1.0 / 200, iso: 400, focalLength: 85)
        #expect(info.summary == "1/200 · f/2.8 · ISO 400 · 85 mm")   // order: shutter, aperture, ISO, focal length; no lens
        #expect(CameraInfo(aperture: 8, shutter: 2).summary == "2 s · f/8")
    }

    @Test func lensNameDropsHasselbladFocalSuffix() {
        #expect(CameraInfo.cleanLens("XCD 35-100E@35") == "XCD 35-100E")
        #expect(CameraInfo.cleanLens("RF 85mm F1.2") == "RF 85mm F1.2")
    }

    @Test func readsSettingsFromRealFiles() throws {
        let dir = try Scratch.folder(cr3: 1, threeFR: 1)
        for photo in try FolderBrowser().photos(in: dir) {
            let info = PhotoMetadataReader().cameraInfo(photo.url)
            #expect(info.aperture != nil && info.iso != nil, "\(photo.fileName) has no camera info")
        }
    }
}
