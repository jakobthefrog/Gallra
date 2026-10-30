import Foundation

/// Lists folders and RAW files and reports changes. Read-only: never writes to user files.
public protocol FolderBrowsing: Sendable {
    /// Visible subfolders of `folder`, sorted by name.
    func subfolders(of folder: URL) throws -> [FolderNode]
    /// RAW files directly inside `folder` (metadata not yet read), sorted by name.
    func photos(in folder: URL) throws -> [Photo]
    /// Emits whenever the contents of `folder` change. Ends when the stream is cancelled.
    func changes(in folder: URL) -> AsyncStream<Void>
}

/// Default `FolderBrowsing` using FileManager and a kernel file-system watcher.
public struct FolderBrowser: FolderBrowsing {
    /// Name of the folder rejected photos are moved to; never listed as a normal subfolder.
    public static let rejectedFolderName = "Gallra Rejected"

    public init() {}

    public func subfolders(of folder: URL) throws -> [FolderNode] {
        let items = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { FolderNode(path: $0.path) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func photos(in folder: URL) throws -> [Photo] {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var result: [Photo] = []
        for url in items {
            guard let format = RawFormat(fileExtension: url.pathExtension),
                  let attrs = try? fm.attributesOfItem(atPath: url.path),
                  (attrs[.type] as? FileAttributeType) == .typeRegular else { continue }
            let volume = (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString) ?? "unknown"
            let id = PhotoID(volume: volume,
                             fileNumber: (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
                             path: url.path)
            result.append(Photo(id: id, format: format,
                                fileSize: (attrs[.size] as? NSNumber)?.int64Value ?? 0,
                                modified: (attrs[.modificationDate] as? Date) ?? .distantPast))
        }
        return result.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    public func changes(in folder: URL) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let fd = open(folder.path, O_EVTONLY)
            guard fd >= 0 else { continuation.finish(); return }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend],
                queue: .global(qos: .utility))
            source.setEventHandler { continuation.yield() }
            source.setCancelHandler { close(fd) }
            continuation.onTermination = { _ in source.cancel() }
            source.resume()
        }
    }
}
