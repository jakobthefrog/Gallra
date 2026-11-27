import Foundation

/// A connected SD card or external disk.
public struct ExternalVolume: Identifiable, Hashable, Sendable {
    /// Where it is mounted, e.g. "/Volumes/EOS_DIGITAL".
    public let path: String
    public let name: String
    /// True when it has a camera folder (DCIM) at the top, so it is shown as a memory card.
    public let isCameraCard: Bool
    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    public init(path: String, name: String, isCameraCard: Bool) {
        self.path = path
        self.name = name
        self.isCameraCard = isCameraCard
    }
}

/// Finds external drives and tells whether a saved folder is currently reachable. Read-only.
public enum ExternalVolumes {
    /// What the system says about a mounted volume.
    public struct Traits: Sendable {
        public var isRoot, isBrowsable, isLocal, isInternal, isRemovable, isEjectable: Bool

        public init(isRoot: Bool = false, isBrowsable: Bool = true, isLocal: Bool = true,
                    isInternal: Bool = false, isRemovable: Bool = false, isEjectable: Bool = false) {
            self.isRoot = isRoot
            self.isBrowsable = isBrowsable
            self.isLocal = isLocal
            self.isInternal = isInternal
            self.isRemovable = isRemovable
            self.isEjectable = isEjectable
        }
    }

    /// A local, visible, non-startup volume that can be unplugged. The built-in SD card slot counts
    /// as "internal" to macOS, so removable and ejectable volumes qualify too. Network shares don't.
    public static func isExternal(_ t: Traits) -> Bool {
        !t.isRoot && t.isBrowsable && t.isLocal && (!t.isInternal || t.isRemovable || t.isEjectable)
    }

    private static let keys: Set<URLResourceKey> = [
        .volumeNameKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey, .volumeIsLocalKey,
        .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey]

    /// Every visible mounted volume except the startup disk and system mounts, split by kind.
    public static func mounted() -> (external: [ExternalVolume], other: [URL]) {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        var external: [ExternalVolume] = []
        var other: [URL] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: keys),
                  v.volumeIsRootFileSystem != true,
                  !url.lastPathComponent.hasPrefix("com.apple.")   // e.g. Time Machine local snapshots
            else { continue }
            let traits = Traits(isBrowsable: v.volumeIsBrowsable != false, isLocal: v.volumeIsLocal != false,
                                isInternal: v.volumeIsInternal == true, isRemovable: v.volumeIsRemovable == true,
                                isEjectable: v.volumeIsEjectable == true)
            if isExternal(traits) {
                external.append(ExternalVolume(path: url.path, name: v.volumeName ?? url.lastPathComponent,
                                               isCameraCard: isFolder(url.appendingPathComponent("DCIM").path)))
            } else if traits.isBrowsable {
                other.append(url)
            }
        }
        return (external.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, other)
    }

    /// The drive name in a "/Volumes/<name>/…" path; nil for folders on the startup disk.
    public static func volumeName(inPath path: String) -> String? {
        let parts = path.split(separator: "/")
        return parts.count >= 2 && parts[0] == "Volumes" ? String(parts[1]) : nil
    }

    /// True when `path` is the folder `root` or lies inside it.
    public static func path(_ path: String, isInside root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }

    /// True when `path` is a folder that exists right now.
    public static func isFolder(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
