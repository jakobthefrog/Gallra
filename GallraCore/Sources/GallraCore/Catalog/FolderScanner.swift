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

    /// Returns the photos in `folder` with up-to-date metadata.
    public func scan(_ folder: URL) async throws -> [Photo] {
        // Catalog keys use resolved paths (/private/var, not /var), matching what listing returns.
        let folderPath = FolderScanner.canonicalPath(folder)
        let onDisk = try browser.photos(in: folder)
        let cached = Dictionary(uniqueKeysWithValues:
            try await catalog.photos(inFolder: folderPath).map { ($0.id, $0) })

        var result: [Photo] = []
        var changed: [Photo] = []
        for var photo in onDisk {
            if let old = cached[photo.id], old.modified == photo.modified, old.fileSize == photo.fileSize {
                result.append(old)
                continue
            }
            let meta = reader.read(photo.url)
            photo.captureDate = meta.captureDate
            photo.rating = meta.rating
            changed.append(photo)
            result.append(photo)
        }
        if !changed.isEmpty { try await catalog.upsert(changed) }
        try await catalog.removePhotos(inFolder: folderPath, except: Set(onDisk.map(\.id.rawValue)))
        return result
    }
}
