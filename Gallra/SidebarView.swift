import SwiftUI
import GallraCore

/// Favorites, Locations and an expandable folder tree.
struct SidebarView: View {
    let width: Double
    @Environment(AppModel.self) private var model

    private var locations: [URL] {
        var roots = [FileManager.default.homeDirectoryForCurrentUser]
        let volumes = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        // The boot volume shows up in /Volumes as a symlink to "/"; skip it.
        roots += volumes.filter { $0.resolvingSymlinksInPath().path != "/" }
        return roots
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if !model.favorites.isEmpty {
                    SectionTitle("Favorites")
                    ForEach(model.favorites, id: \.self) { path in
                        FolderRow(url: URL(fileURLWithPath: path, isDirectory: true), depth: 0, expandable: false)
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

/// A folder row: disclosure arrow, icon, name, photo count, favorite star on hover.
private struct FolderRow: View {
    let url: URL
    let depth: Int
    let expandable: Bool
    var title: String?
    @Environment(AppModel.self) private var model
    @State private var expanded = false
    @State private var children: [FolderNode] = []
    @State private var count: Int?
    @State private var hovering = false

    private var isCurrent: Bool { model.selectedTab?.folderPath == FolderScanner.canonicalPath(url) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if expandable {
                    Button { toggle() } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold)).frame(width: 14)
                    }.buttonStyle(.plain)
                } else { Spacer().frame(width: 14) }
                Image(systemName: "folder").foregroundStyle(Theme.textSecondary)
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
            .padding(.vertical, 4).padding(.horizontal, 6)
            .padding(.leading, Double(depth) * 14)
            .background((isCurrent || hovering) ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(count: 2) { model.openInNewTab(url) }
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.command) { model.openInNewTab(url) } else { model.open(url) }
            }
            .task { await loadCount() }

            if expanded {
                ForEach(children) { child in
                    FolderRow(url: child.url, depth: depth + 1, expandable: true)
                }
            }
        }
    }

    private func toggle() {
        expanded.toggle()
        if expanded {
            let browser = model.browser
            let folder = url
            Task {
                children = await Task.detached { (try? browser.subfolders(of: folder)) ?? [] }.value
            }
        }
    }

    private func loadCount() async {
        let browser = model.browser
        let folder = url
        count = await Task.detached { (try? browser.photos(in: folder))?.count }.value
    }
}
