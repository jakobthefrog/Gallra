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

    var tabs: [FolderTab] = []
    var selectedTabID: UUID?
    var favorites: [String] = []
    var sidebarVisible = true
    var startupError: String?

    var selectedTab: FolderTab? { tabs.first { $0.id == selectedTabID } }

    init() {
        let previews = PreviewService()
        images = ImageStore(previews: previews)
        do {
            let catalog = try Catalog()
            self.catalog = catalog
            scanner = FolderScanner(browser: browser, catalog: catalog)
        } catch {
            catalog = nil
            scanner = nil
            startupError = "Could not open the photo cache: \(error)"
        }
        newTab()
        Task { await reloadFavorites() }
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
