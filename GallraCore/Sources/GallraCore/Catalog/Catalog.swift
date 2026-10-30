import Foundation
import SQLite3

public enum CatalogError: Error, Sendable {
    case openFailed(String)
    case sqlFailed(String)
}

/// Local SQLite cache of file lists, ratings and favorites. It is only a cache:
/// the RAW files remain the source of truth, so the database can be deleted safely.
public actor Catalog {
    nonisolated(unsafe) private var db: OpaquePointer?

    /// Default location: `~/Library/Application Support/Gallra/catalog.sqlite`.
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gallra/catalog.sqlite")
    }

    /// Opens (creating if needed) the database at `url`.
    public init(url: URL = Catalog.defaultURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            throw CatalogError.openFailed(String(cString: sqlite3_errmsg(handle)))
        }
        db = handle
        try Catalog.exec(handle, """
            CREATE TABLE IF NOT EXISTS photos(
                id TEXT PRIMARY KEY, folder TEXT NOT NULL, volume TEXT NOT NULL,
                file_number INTEGER NOT NULL, path TEXT NOT NULL, format TEXT NOT NULL,
                size INTEGER NOT NULL, modified REAL NOT NULL,
                capture REAL, rating INTEGER);
            CREATE INDEX IF NOT EXISTS photos_folder ON photos(folder);
            CREATE TABLE IF NOT EXISTS favorites(
                path TEXT PRIMARY KEY, position INTEGER NOT NULL);
            """)
    }

    deinit { sqlite3_close(db) }

    // MARK: Photos

    /// Cached photos of one folder, sorted by file name.
    public func photos(inFolder folder: String) throws -> [Photo] {
        let stmt = try prepare("""
            SELECT volume, file_number, path, format, size, modified, capture, rating
            FROM photos WHERE folder = ?
            """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, folder)
        var result: [Photo] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let format = RawFormat(rawValue: text(stmt, 3)) else { continue }
            let id = PhotoID(volume: text(stmt, 0), fileNumber: UInt64(sqlite3_column_int64(stmt, 1)),
                             path: text(stmt, 2))
            result.append(Photo(
                id: id, format: format, fileSize: sqlite3_column_int64(stmt, 4),
                modified: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)),
                captureDate: sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil
                    : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6)),
                rating: sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil
                    : Int(sqlite3_column_int(stmt, 7))))
        }
        return result.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    /// Inserts or replaces the given photos in one transaction.
    public func upsert(_ photos: [Photo]) throws {
        try Catalog.exec(db, "BEGIN")
        do {
            let stmt = try prepare("""
                INSERT OR REPLACE INTO photos
                (id, folder, volume, file_number, path, format, size, modified, capture, rating)
                VALUES (?,?,?,?,?,?,?,?,?,?)
                """)
            defer { sqlite3_finalize(stmt) }
            for photo in photos {
                sqlite3_reset(stmt)
                bind(stmt, 1, photo.id.rawValue)
                bind(stmt, 2, photo.folderPath)
                bind(stmt, 3, photo.id.volume)
                sqlite3_bind_int64(stmt, 4, Int64(bitPattern: photo.id.fileNumber))
                bind(stmt, 5, photo.id.path)
                bind(stmt, 6, photo.format.rawValue)
                sqlite3_bind_int64(stmt, 7, photo.fileSize)
                sqlite3_bind_double(stmt, 8, photo.modified.timeIntervalSince1970)
                if let date = photo.captureDate { sqlite3_bind_double(stmt, 9, date.timeIntervalSince1970) }
                else { sqlite3_bind_null(stmt, 9) }
                if let rating = photo.rating { sqlite3_bind_int(stmt, 10, Int32(rating)) }
                else { sqlite3_bind_null(stmt, 10) }
                guard sqlite3_step(stmt) == SQLITE_DONE else { throw lastError() }
            }
            try Catalog.exec(db, "COMMIT")
        } catch {
            try? Catalog.exec(db, "ROLLBACK")
            throw error
        }
    }

    /// Removes cached rows of `folder` whose id is not in `keep` (files deleted or moved away).
    public func removePhotos(inFolder folder: String, except keep: Set<String>) throws {
        let stmt = try prepare("SELECT id FROM photos WHERE folder = ?")
        var stale: [String] = []
        bind(stmt, 1, folder)
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = text(stmt, 0)
            if !keep.contains(id) { stale.append(id) }
        }
        sqlite3_finalize(stmt)
        for id in stale {
            let del = try prepare("DELETE FROM photos WHERE id = ?")
            bind(del, 1, id)
            sqlite3_step(del)
            sqlite3_finalize(del)
        }
    }

    // MARK: Favorites

    /// Favorite folder paths in the user's order.
    public func favorites() throws -> [String] {
        let stmt = try prepare("SELECT path FROM favorites ORDER BY position")
        defer { sqlite3_finalize(stmt) }
        var result: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW { result.append(text(stmt, 0)) }
        return result
    }

    /// Adds a favorite at the end (no-op if already there).
    public func addFavorite(_ path: String) throws {
        let stmt = try prepare("""
            INSERT OR IGNORE INTO favorites(path, position)
            VALUES (?, COALESCE((SELECT MAX(position) + 1 FROM favorites), 0))
            """)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, path)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw lastError() }
    }

    public func removeFavorite(_ path: String) throws {
        let stmt = try prepare("DELETE FROM favorites WHERE path = ?")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, path)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw lastError() }
    }

    // MARK: SQLite helpers

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw lastError() }
        return stmt
    }

    private func lastError() -> CatalogError { .sqlFailed(String(cString: sqlite3_errmsg(db))) }

    private static func exec(_ db: OpaquePointer?, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw CatalogError.sqlFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private nonisolated func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }

    private nonisolated func text(_ stmt: OpaquePointer?, _ column: Int32) -> String {
        sqlite3_column_text(stmt, column).map { String(cString: $0) } ?? ""
    }
}
