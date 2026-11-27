import SwiftUI
import GallraCore

/// Favorites, external drives, Locations and an expandable folder tree.
struct SidebarView: View {
    let width: Double
    @Environment(AppModel.self) private var model

    private var locations: [URL] { [FileManager.default.homeDirectoryForCurrentUser] + model.otherVolumes }

    private func volume(at path: String) -> ExternalVolume? { model.externalVolumes.first { $0.path == path } }
    private func icon(_ drive: ExternalVolume) -> String { drive.isCameraCard ? "sdcard" : "externaldrive" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if !model.favorites.isEmpty {
                    SectionTitle("Favorites")
                    ForEach(model.favorites, id: \.self) { path in
                        if model.missingFavorites.contains(path) {
                            MissingFavoriteRow(path: path)
                        } else {
                            FolderRow(url: URL(fileURLWithPath: path, isDirectory: true), depth: 0, expandable: true,
                                      title: volume(at: path)?.name, icon: volume(at: path).map(icon) ?? "folder",
                                      scope: "favorites:")
                        }
                    }
                }
                if !model.externalVolumes.isEmpty {
                    SectionTitle("External Drives")
                    ForEach(model.externalVolumes) { drive in
                        FolderRow(url: drive.url, depth: 0, expandable: true, title: drive.name,
                                  icon: icon(drive), scope: "drives:")
                    }
                }
                SectionTitle("Locations")
                ForEach(locations, id: \.self) { url in
                    FolderRow(url: url, depth: 0, expandable: true, title: url == locations.first ? "Mac (\(url.lastPathComponent))" : nil)
                }
            }
            .padding(8)
        }
        // Favorite folders can be deleted or restored outside the app.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshMissingFavorites() }
        .onReceive(NotificationCenter.default.publisher(for: .gallraFoldersChanged)) { _ in model.refreshMissingFavorites() }
        .background(Theme.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button("Open Folder…") { model.chooseFolder(inNewTab: false) }
                .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(Theme.sidebar)
        }
        // Width goes on the whole column: the button above stretches, which would otherwise
        // make the column take half the window.
        .frame(width: width)
    }
}

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8).padding(.top, 8)
    }
}

extension Notification.Name {
    /// Posted when the app itself creates or fills a folder (rejecting photos), so the sidebar re-reads.
    static let gallraFoldersChanged = Notification.Name("gallraFoldersChanged")
}

/// Remembers subfolder lists already read, so expanding again is instant.
@MainActor private enum SubfolderCache {
    static var values: [String: [FolderNode]] = [:]
}

/// A favorite that can't be reached: grayed out and not openable; the star still removes it.
private struct MissingFavoriteRow: View {
    let path: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let drive = ExternalVolumes.volumeName(inPath: path)
        let unplugged = drive.map { name in
            !(model.externalVolumes.map(\.path) + model.otherVolumes.map(\.path)).contains("/Volumes/" + name)
        } ?? false
        let isDriveRoot = drive.map { path == "/Volumes/" + $0 } ?? false
        let reason = !unplugged ? "Folder not found" : isDriveRoot ? "Not connected" : "\(drive ?? "") · not connected"
        HStack(spacing: 6) {
            Color.clear.frame(width: 26, height: 26)
            Image(systemName: unplugged ? "externaldrive" : "folder")
            VStack(alignment: .leading, spacing: 0) {
                Text(url.lastPathComponent).font(.system(size: 13)).lineLimit(1)
                Text(reason).font(.system(size: 11)).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { model.toggleFavorite(url) } label: { Image(systemName: "star.fill").font(.system(size: 11)) }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove from favorites")
        }
        .foregroundStyle(Theme.textDisabled)
        .padding(.vertical, 1).padding(.horizontal, 4)
        .help(path)
        .contextMenu { Button("Remove from Favorites") { model.toggleFavorite(url) } }
    }
}

/// A folder row: disclosure arrow, icon, name, photo count, favorite star on hover.
private struct FolderRow: View {
    let url: URL
    let depth: Int
    let expandable: Bool
    var title: String?
    var icon = "folder"
    /// Which list the row lives in. Favorites and Locations remember open folders separately,
    /// so opening a folder in one doesn't open it in the other.
    var scope = ""
    @Environment(AppModel.self) private var model
    @State private var children: [FolderNode] = []
    @State private var count: Int?
    /// nil until the folder has been read once; the arrow shows meanwhile.
    @State private var hasSubfolders: Bool?
    @State private var hovering = false

    private var expandKey: String { scope + url.path }
    private var expanded: Bool { model.expandedFolders.contains(expandKey) }
    private var isCurrent: Bool { model.selectedTab?.folderPath == FolderScanner.canonicalPath(url) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if expandable && hasSubfolders != false {
                    Button { toggle() } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold)).frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                } else { Color.clear.frame(width: 26, height: 26) }   // same height as rows with an arrow
                Image(systemName: icon).foregroundStyle(Theme.accent)
                Text(title ?? url.lastPathComponent).lineLimit(1).foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 4)
                if hovering || model.isFavorite(url) {
                    Button { model.toggleFavorite(url) } label: {
                        Image(systemName: model.isFavorite(url) ? "star.fill" : "star").font(.system(size: 11))
                            .foregroundStyle(model.isFavorite(url) ? Theme.star : Theme.textSecondary)
                    }.buttonStyle(.plain)
                    .accessibilityLabel(model.isFavorite(url) ? "Remove from favorites" : "Add to favorites")
                }
                if let count, count > 0 {
                    Text("\(count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                }
            }
            .font(.system(size: 13))
            .padding(.vertical, 1).padding(.horizontal, 4)
            .padding(.leading, Double(depth) * 14)
            .background((isCurrent || hovering) ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            // Click opens the folder here; Cmd+click opens it in a new tab.
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.command) { model.openInNewTab(url, reuse: false) }
                else { model.open(url) }
            }
            .contextMenu {
                Button("Open in New Tab") { model.openInNewTab(url, reuse: false) }
                FinderMenu(folder: url.path)
            }
            .task {
                hasSubfolders = SubfolderCache.values[url.path].map { !$0.isEmpty }
                loadChildren(show: expanded)       // was open when the app was last closed
                await loadCount()
            }
            // Folders can change outside the app (deleted in Finder): look again when the user comes back.
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .gallraFoldersChanged)) { _ in refresh() }

            if expanded {
                ForEach(children) { child in
                    FolderRow(url: child.url, depth: depth + 1, expandable: true, scope: scope)
                }
            }
        }
    }

    private func toggle() {
        if expanded { model.expandedFolders.remove(expandKey); return }
        model.expandedFolders.insert(expandKey)
        loadChildren(show: true)
    }

    /// Reads the subfolders (to know whether the arrow is needed) and, with `show`, lists them.
    private func loadChildren(show: Bool) {
        // Show the last list at once (if we've seen this folder), then refresh it.
        if show, let known = SubfolderCache.values[url.path] { children = known }
        let browser = model.browser
        let folder = url
        Task {
            let fresh = await Task.detached(priority: .userInitiated) { (try? browser.subfolders(of: folder)) ?? [] }.value
            SubfolderCache.values[folder.path] = fresh
            hasSubfolders = !fresh.isEmpty
            if show { children = fresh }
        }
    }

    private func refresh() {
        loadChildren(show: expanded)
        Task { await loadCount() }
    }

    private func loadCount() async {
        let browser = model.browser
        let folder = url
        count = await Task.detached(priority: .utility) { (try? browser.photos(in: folder))?.count }.value
    }
}
