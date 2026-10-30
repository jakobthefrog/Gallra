import SwiftUI
import AppKit
import GallraCore

/// App-wide state: the engine services, favorites, and the list of open tabs.
@MainActor
@Observable
final class AppModel {
    let catalog: Catalog?
    let scanner: FolderScanner?
    let browser = FolderBrowser()
    let images: ImageStore
    let previews: PreviewService
    let similarity: SimilarityService?
    let ratingWriter = RatingWriter()
    /// One step Cmd+Z can reverse.
    enum UndoStep {
        case reject(MoveBatch)
        /// Hand-made grouping: group ids photos had before, and photos that had none.
        case grouping(tab: UUID, previous: [String: String], unassigned: [String])
    }
    /// Actions that can still be undone, newest last.
    var undoStack: [UndoStep] = []

    var tabs: [FolderTab] = [] { didSet { saveSession() } }
    var selectedTabID: UUID? { didSet { saveSession() } }
    /// Paths of the sidebar folders that are expanded (remembered between launches).
    var expandedFolders: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "expandedFolders") ?? []) {
        didSet { UserDefaults.standard.set(Array(expandedFolders), forKey: "expandedFolders") }
    }
    var favorites: [String] = []
    var sidebarVisible = true
    /// Show photos from all sub folders too (remembered between launches, on by default).
    var includeSubfolders = UserDefaults.standard.object(forKey: "includeSubfolders") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(includeSubfolders, forKey: "includeSubfolders")
            for tab in tabs { tab.subfolderSettingChanged() }
        }
    }
    /// With sub folders included: true = one section per folder, false = one flat grid.
    var layoutByFolder = UserDefaults.standard.bool(forKey: "layoutByFolder") {
        didSet {
            UserDefaults.standard.set(layoutByFolder, forKey: "layoutByFolder")
            for tab in tabs { tab.subfolderSettingChanged() }
        }
    }
    var startupError: String?

    var selectedTab: FolderTab? { tabs.first { $0.id == selectedTabID } }

    init() {
        let previews = PreviewService()
        self.previews = previews
        images = ImageStore(previews: previews)
        do {
            let catalog = try Catalog()
            self.catalog = catalog
            scanner = FolderScanner(browser: browser, catalog: catalog)
            similarity = SimilarityService(previews: previews, catalog: catalog)
        } catch {
            catalog = nil
            scanner = nil
            similarity = nil
            startupError = "Could not open the photo cache: \(error)"
        }
        // Read what the last session saved before opening tabs (opening them saves again).
        let savedTabs = UserDefaults.standard.stringArray(forKey: "openTabs") ?? []
        let savedSelected = UserDefaults.standard.string(forKey: "selectedTab")
        newTab()
        for path in savedTabs {
            var isFolder: ObjCBool = false
            // Skip folders that are gone (for example an unplugged drive).
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue else { continue }
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if tabs.count == 1, tabs[0].folder == nil { tabs[0].open(url) } else { openInNewTab(url) }
        }
        if let savedSelected, let tab = tabs.first(where: { $0.folderPath == FolderScanner.canonicalPath(URL(fileURLWithPath: savedSelected)) }) {
            selectedTabID = tab.id
        }
        Task { await reloadFavorites() }
    }

    /// Remembers the open folders and the selected one, so the next launch opens them again.
    /// Empty tabs aren't saved.
    func saveSession() {
        let paths = tabs.compactMap { $0.folder?.path }
        UserDefaults.standard.set(paths, forKey: "openTabs")
        if let selected = selectedTab?.folder?.path { UserDefaults.standard.set(selected, forKey: "selectedTab") }
    }

    // MARK: Cache

    /// Bytes used on disk by previews and the photo-details database.
    func cacheBytes() async -> Int64 {
        let previews = self.previews, catalog = self.catalog
        return await previews.diskCacheBytes() + (catalog?.fileBytes() ?? 0)
    }

    /// Deletes previews and cached photo details, then reloads open folders.
    func clearCache() async {
        await previews.clearDiskCache()
        try? await catalog?.clearCache()
        for tab in tabs where tab.folder != nil { tab.reload() }
    }

    // MARK: Tabs

    /// Opens an empty tab (shows a "choose a folder" prompt).
    func newTab() {
        let tab = FolderTab(model: self)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    /// Opens `folder` in a new tab, or switches to the tab that already shows it.
    func openInNewTab(_ folder: URL) {
        let path = FolderScanner.canonicalPath(folder)
        if let existing = tabs.first(where: { $0.folderPath == path }) {
            selectedTabID = existing.id
            return
        }
        let tab = FolderTab(model: self)
        tabs.append(tab)
        selectedTabID = tab.id
        tab.open(folder)
    }

    /// Shows `folder` in the current tab (an empty tab if none).
    func open(_ folder: URL) {
        if let tab = selectedTab { tab.open(folder) } else { openInNewTab(folder) }
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].close()
        tabs.remove(at: index)
        if tabs.isEmpty { newTab() } else if selectedTabID == id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
    }

    func chooseFolder(inNewTab: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if inNewTab { openInNewTab(url) } else { open(url) }
    }

    /// Reverses the most recent reject or grouping action.
    func undoLast() {
        guard let step = undoStack.popLast() else { selectedTab?.showNotice("Nothing to undo."); return }
        switch step {
        case .reject(let batch):
            let failed = RejectService().undo(batch)
            selectedTab?.showNotice(failed.isEmpty ? "Restored \(batch.files.count) photo(s)."
                                                   : "Could not restore: \(failed.joined(separator: ", ")).")
            for tab in tabs { tab.reload() }
        case .grouping(let tabID, let previous, let unassigned):
            guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
            tab.restoreGrouping(previous: previous, unassigned: unassigned)
            tab.showNotice("Undid grouping.")
        }
    }

    // MARK: Favorites

    func isFavorite(_ url: URL) -> Bool { favorites.contains(FolderScanner.canonicalPath(url)) }

    func toggleFavorite(_ url: URL) {
        let path = FolderScanner.canonicalPath(url)
        let wasFavorite = favorites.contains(path)
        // Update the list right away; persist in the background.
        if wasFavorite { favorites.removeAll { $0 == path } } else { favorites.append(path) }
        guard let catalog else { return }
        Task {
            if wasFavorite { try? await catalog.removeFavorite(path) } else { try? await catalog.addFavorite(path) }
            await reloadFavorites()
        }
    }

    private func reloadFavorites() async {
        guard let catalog, let list = try? await catalog.favorites() else { return }
        favorites = list
    }
}
