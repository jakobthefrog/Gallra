import Foundation
import Testing
@testable import GallraCore

struct ExternalVolumesTests {
    @Test func externalDisksAndCardsQualify() {
        #expect(ExternalVolumes.isExternal(.init()))                       // USB disk
        #expect(ExternalVolumes.isExternal(.init(isInternal: true, isRemovable: true)))   // built-in SD slot
        #expect(ExternalVolumes.isExternal(.init(isInternal: true, isEjectable: true)))
    }

    @Test func startupInternalNetworkAndHiddenVolumesDoNot() {
        #expect(!ExternalVolumes.isExternal(.init(isRoot: true)))
        #expect(!ExternalVolumes.isExternal(.init(isInternal: true)))      // second internal partition
        #expect(!ExternalVolumes.isExternal(.init(isLocal: false)))        // network share
        #expect(!ExternalVolumes.isExternal(.init(isBrowsable: false)))
    }

    @Test func readsDriveNameFromPath() {
        #expect(ExternalVolumes.volumeName(inPath: "/Volumes/EOS_DIGITAL/DCIM") == "EOS_DIGITAL")
        #expect(ExternalVolumes.volumeName(inPath: "/Volumes/T7 Shield") == "T7 Shield")
        #expect(ExternalVolumes.volumeName(inPath: "/Users/someone/Pictures") == nil)
    }

    @Test func insideMatchesWholeFolderNamesOnly() {
        #expect(ExternalVolumes.path("/Volumes/A", isInside: "/Volumes/A"))
        #expect(ExternalVolumes.path("/Volumes/A/x", isInside: "/Volumes/A"))
        #expect(!ExternalVolumes.path("/Volumes/A 1/x", isInside: "/Volumes/A"))
    }

    @Test func missingFolderIsNotReachable() {
        #expect(ExternalVolumes.isFolder(NSTemporaryDirectory()))
        #expect(!ExternalVolumes.isFolder("/Volumes/gallra-no-such-drive-\(UUID().uuidString)"))
    }
}
