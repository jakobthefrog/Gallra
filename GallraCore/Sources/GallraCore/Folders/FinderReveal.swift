import AppKit

/// Shows files and folders in Finder. Read-only: never changes anything on disk.
public enum FinderReveal {
    /// What Finder will be asked to do for a path.
    public enum Action: Equatable, Sendable {
        /// Open Finder with this file highlighted inside its folder.
        case select(URL)
        /// Open this folder's contents in Finder.
        case open(URL)
        /// Nothing to show (path no longer exists).
        case none
    }

    /// Decides what to do for `url`: folders are opened, files are highlighted, missing paths do nothing.
    public static func action(for url: URL) -> Action {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return .none }
        return isDirectory.boolValue ? .open(url) : .select(url)
    }

    /// Reveals a file (highlighted) or folder (opened) in Finder.
    @MainActor public static func reveal(_ url: URL) {
        switch action(for: url) {
        case .select(let file): NSWorkspace.shared.activateFileViewerSelecting([file])
        case .open(let folder): NSWorkspace.shared.open(folder)
        case .none: NSSound.beep()
        }
    }

    /// Convenience for the paths the app passes around.
    @MainActor public static func reveal(path: String) {
        reveal(URL(fileURLWithPath: path))
    }
}
