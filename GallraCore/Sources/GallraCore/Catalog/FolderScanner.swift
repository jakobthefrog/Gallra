import Foundation

/// Combines FolderBrowser + Catalog: lists a folder, re-reads metadata only for new or
/// changed files, and keeps the catalog in sync. Never writes to user files.
public struct FolderScanner: Sendable {
    private let browser: any FolderBrowsing
    private let catalog: Catalog
    private let reader: PhotoMetadataReader

    public init(browser: any FolderBrowsing = FolderBrowser(), catalog: Catalog,
                reader: PhotoMetadataReader = PhotoMetadataReader()) {
        self.browser = browser
        self.catalog = catalog
        self.reader = reader
    }

    /// Folder path with symlinks resolved via realpath (Foundation's version strips /private).
    public static func canonicalPath(_ folder: URL) -> String {
        guard let resolved = realpath(folder.path, nil) else { return folder.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Every folder below `root` (any depth), sorted by path. Hidden folders, symlinks and
    /// the Rejected folders are left out.
    public static func subfolders(under root: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            if url.lastPathComponent == FolderBrowser.rejectedFolderName { walker.skipDescendants(); continue }
            found.append(url)
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// True if any folder below `root` holds a supported RAW file. Stops at the first one found.
    public static func hasPhotosInSubfolders(of root: URL) -> Bool {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return false }
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            if url.lastPathComponent == FolderBrowser.rejectedFolderName { walker.skipDescendants(); continue }
            if rawFileCount(in: url) > 0 { return true }
        }
        return false
    }

    /// Like `scan`, but includes every sub folder at any depth: the folder's own photos first,
    /// then each sub folder in path order. A sub folder that cannot be read is skipped.
    /// `progress` is called with (photos done, photos in total) as files are read; the total
    /// counts RAW files found by a quick listing before the scan starts.
    public func scanTree(_ root: URL, progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> [Photo] {
        let folders = [root] + FolderScanner.subfolders(under: root)
        let total = folders.reduce(0) { $0 + FolderScanner.rawFileCount(in: $1) }
        progress?(0, total)
        var result: [Photo] = []
        for (n, folder) in folders.enumerated() {
            let base = result.count
            var onRead: (@Sendable (Int) -> Void)?
            if let report = progress {
                onRead = { @Sendable (read: Int) in report(base + read, total) }
            }
            if n == 0 { result += try await scan(folder, onRead: onRead) }
            else if let found = try? await scan(folder, onRead: onRead) { result += found }
            progress?(result.count, total)
        }
        return result
    }

    /// Number of supported RAW files directly in `folder` (names only, no file attributes read).
    static func rawFileCount(in folder: URL) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && RawFormat(fileExtension: ($0 as NSString).pathExtension) != nil }.count
    }

    /// Returns the photos in `folder` with up-to-date metadata.
    public func scan(_ folder: URL, onRead: (@Sendable (Int) -> Void)? = nil) async throws -> [Photo] {
        // Catalog keys use resolved paths (/private/var, not /var), matching what listing returns.
        let folderPath = FolderScanner.canonicalPath(folder)
        let onDisk = try browser.photos(in: folder)
        let cached = Dictionary(uniqueKeysWithValues:
            try await catalog.photos(inFolder: folderPath).map { ($0.id, $0) })

        // Files already known and unchanged keep their catalog data; the rest are read in parallel.
        var known: [PhotoID: Photo] = [:]
        var toRead: [Photo] = []
        for photo in onDisk {
            if let old = cached[photo.id], old.modified == photo.modified, old.fileSize == photo.fileSize {
                known[photo.id] = old
            } else {
                toRead.append(photo)
            }
        }
        let reader = self.reader
        let changed = await withTaskGroup(of: Photo.self, returning: [Photo].self) { group in
            for var photo in toRead {
                group.addTask {
                    let meta = reader.read(photo.url)
                    photo.captureDate = meta.captureDate
                    photo.rating = meta.rating
                    return photo
                }
            }
            var done: [Photo] = []
            for await photo in group { done.append(photo); onRead?(done.count) }
            return done
        }
        for photo in changed { known[photo.id] = photo }
        let result = onDisk.compactMap { known[$0.id] }
        if !changed.isEmpty { try await catalog.upsert(changed) }
        try await catalog.removePhotos(inFolder: folderPath, except: Set(onDisk.map(\.id.rawValue)))
        return result
    }
}
