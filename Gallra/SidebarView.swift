import SwiftUI
import GallraCore

/// Favorites, Locations and an expandable folder tree.
struct SidebarView: View {
    let width: Double
    @Environment(AppModel.self) private var model

    private var locations: [URL] {
        var roots = [FileManager.default.homeDirectoryForCurrentUser]
        let volumes = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: [.volumeIsBrowsableKey],
            options: [.skipsHiddenFiles])) ?? []
        // The boot volume shows up in /Volumes as a symlink to "/"; skip it. Also skip volumes
        // Finder hides, such as the macOS Recovery partition.
        roots += volumes.filter {
            $0.resolvingSymlinksInPath().path != "/"
                && (try? $0.resourceValues(forKeys: [.volumeIsBrowsableKey]).volumeIsBrowsable) != false
                && !$0.lastPathComponent.hasPrefix("com.apple.")   // system mounts, e.g. Time Machine local snapshots
        }
        return roots
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if !model.favorites.isEmpty {
                    SectionTitle("Favorites")
                    ForEach(model.favorites, id: \.self) { path in
                        FolderRow(url: URL(fileURLWithPath: path, isDirectory: true), depth: 0, expandable: true, scope: "favorites:")
                    }
                }
                SectionTitle("Locations")
                ForEach(locations, id: \.self) { url in
                    FolderRow(url: url, depth: 0, expandable: true, title: url == locations.first ? "Mac (\(url.lastPathComponent))" : nil)
                }
            }
            .padding(8)
        }
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

/// Remembers subfolder lists already read, so expanding again is instant.
@MainActor private enum SubfolderCache {
    static var values: [String: [FolderNode]] = [:]
}

/// A folder row: disclosure arrow, icon, name, photo count, favorite star on hover.
private struct FolderRow: View {
    let url: URL
    let depth: Int
    let expandable: Bool
    var title: String?
    /// Which list the row lives in. Favorites and Locations remember open folders separately,
    /// so opening a folder in one doesn't open it in the other.
    var scope = ""
    @Environment(AppModel.self) private var model
    @State private var children: [FolderNode] = []
    @State private var count: Int?
    @State private var hovering = false

    private var expandKey: String { scope + url.path }
    private var expanded: Bool { model.expandedFolders.contains(expandKey) }
    private var isCurrent: Bool { model.selectedTab?.folderPath == FolderScanner.canonicalPath(url) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if expandable {
                    Button { toggle() } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold)).frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                } else { Spacer().frame(width: 26) }
                Image(systemName: "folder").foregroundStyle(Theme.accent)
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
            // One handler for click and double-click: a separate double-tap gesture makes SwiftUI
            // hold back every click (including the arrow) until the double-click window passes.
            .onTapGesture {
                if NSApp.currentEvent?.clickCount ?? 1 >= 2 || NSEvent.modifierFlags.contains(.command) {
                    model.openInNewTab(url)
                } else { model.open(url) }
            }
            .contextMenu {
                Button("Open in New Tab") { model.openInNewTab(url) }
                FinderMenu(folder: url.path)
            }
            .task {
                if expanded { loadChildren() }     // was open when the app was last closed
                await loadCount()
            }

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
        loadChildren()
    }

    private func loadChildren() {
        // Show the last list at once (if we've seen this folder), then refresh it.
        if let known = SubfolderCache.values[url.path] { children = known }
        let browser = model.browser
        let folder = url
        Task {
            let fresh = await Task.detached(priority: .userInitiated) { (try? browser.subfolders(of: folder)) ?? [] }.value
            SubfolderCache.values[folder.path] = fresh
            children = fresh
        }
    }

    private func loadCount() async {
        let browser = model.browser
        let folder = url
        count = await Task.detached(priority: .utility) { (try? browser.photos(in: folder))?.count }.value
    }
}
