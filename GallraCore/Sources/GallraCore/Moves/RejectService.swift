import Foundation

/// One file moved by a reject action: where it was and where it went.
public struct MovedFile: Codable, Hashable, Sendable {
    public let original: URL
    public let moved: URL
}

/// Everything moved by a single reject action. Pass it to `RejectService.undo` to put it back.
public struct MoveBatch: Codable, Sendable {
    public var files: [MovedFile]
    public var isEmpty: Bool { files.isEmpty }
}

/// Moves rejected RAW files into `Gallra Rejected` inside their own folder. Never deletes.
public struct RejectService: Sendable {
    public init() {}

    /// Moves `photos` into the Rejected folder next to them. Files that fail are skipped and
    /// reported in `failures`; the rest are still moved.
    public func reject(_ photos: [Photo]) -> (batch: MoveBatch, failures: [String]) {
        let fm = FileManager.default
        var moved: [MovedFile] = []
        var failures: [String] = []
        for photo in photos {
            let target = photo.url.deletingLastPathComponent()
                .appendingPathComponent(FolderBrowser.rejectedFolderName, isDirectory: true)
            do {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                let destination = RejectService.freeName(for: photo.url.lastPathComponent, in: target)
                try fm.moveItem(at: photo.url, to: destination)
                moved.append(MovedFile(original: photo.url, moved: destination))
            } catch {
                failures.append(photo.fileName)
            }
        }
        return (MoveBatch(files: moved), failures)
    }

    /// Moves a batch back to where it came from. Returns names that could not be restored
    /// (for example because a new file now has the old name); those stay in the Rejected folder.
    @discardableResult
    public func undo(_ batch: MoveBatch) -> [String] {
        let fm = FileManager.default
        var failures: [String] = []
        for file in batch.files {
            guard !fm.fileExists(atPath: file.original.path) else {
                failures.append(file.original.lastPathComponent); continue
            }
            do { try fm.moveItem(at: file.moved, to: file.original) }
            catch { failures.append(file.original.lastPathComponent) }
        }
        return failures
    }

    /// `name`, or "name 2.ext", "name 3.ext"... if taken.
    static func freeName(for name: String, in folder: URL) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(name)
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}
