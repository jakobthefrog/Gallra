import SwiftUI
import GallraCore

/// Scrollable thumbnail grid. Single click selects; double click opens the viewer.
struct GridView: View {
    let tab: FolderTab
    private let gap: Double = 3
    @State private var pinchBase: Double?

    var body: some View {
        GeometryReader { geo in
            let cols = max(1, Int((geo.size.width - gap) / (tab.cellSize + gap)))
            ScrollViewReader { proxy in
                ScrollView {
                    if tab.grouping { NewGroupZone(tab: tab) }
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(tab.cellSize), spacing: gap), count: cols),
                              spacing: gap) {
                        if tab.sections.isEmpty {
                            ForEach(0..<tab.photos.count, id: \.self) { cell($0, in: nil) }
                        } else {
                            ForEach(tab.sections) { section in
                                Section {
                                    ForEach(section.range, id: \.self) { cell($0, in: section) }
                                } header: {
                                    SceneHeader(section: section, toggle: { tab.toggleCollapsed(section.id) },
                                                drop: { tab.drop($0, into: section.id) })
                                }
                            }
                        }
                    }
                    .padding(gap)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: tab.selection) { _, new in
                    if tab.photos.indices.contains(new) { proxy.scrollTo(tab.photos[new].id) }
                }
            }
            .onChange(of: cols, initial: true) { _, new in tab.columns = new }
            .gesture(MagnifyGesture()
                .onChanged { value in
                    let base = pinchBase ?? tab.cellSize
                    pinchBase = base
                    tab.cellSize = min(400, max(80, base * value.magnification))
                }
                .onEnded { _ in pinchBase = nil })
        }
        .background(Theme.canvas)
    }
}

extension GridView {
    @ViewBuilder fileprivate func cell(_ index: Int, in section: FolderTab.SceneSection?) -> some View {
        if tab.photos.indices.contains(index) {
            let photo = tab.photos[index]
            ThumbnailView(photo: photo, size: tab.cellSize, isSelected: index == tab.selection,
                          isMarked: tab.marked.contains(photo.id.path))
                .id(photo.id)
                .onTapGesture(count: 2) { tab.select(index); tab.openViewer() }
                .onTapGesture { NSEvent.modifierFlags.contains(.command) ? tab.toggleMark(index) : tab.select(index) }
                .draggable(tab.dragPayload(for: photo))
                .dropDestination(for: String.self) { items, _ in
                    guard let section else { return false }
                    return tab.drop(items, into: section.id)
                }
        }
    }
}

/// Thin header above a scene: "Scene · 5 photos · 14:32", best rating, collapse arrow.
private struct SceneHeader: View {
    let section: FolderTab.SceneSection
    let toggle: () -> Void
    let drop: ([String]) -> Bool
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: section.collapsed ? "chevron.right" : "chevron.down").font(.system(size: 9))
            Text(section.title)
            if section.best > 0 { Text(String(repeating: "★", count: section.best)).foregroundStyle(Theme.star) }
            Spacer()
        }
        .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 4).frame(height: 18).frame(maxWidth: .infinity)
        .background(targeted ? Theme.accent.opacity(0.35) : Theme.canvas)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .dropDestination(for: String.self) { items, _ in drop(items) } isTargeted: { targeted = $0 }
    }
}

/// Drop target at the top of the grouped grid: drag photos here to start a group of your own.
private struct NewGroupZone: View {
    let tab: FolderTab
    @State private var targeted = false

    var body: some View {
        Text("Drop photos here to start a new group")
            .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity).frame(height: 26)
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(targeted ? Theme.accent : Theme.line) }
            .background(targeted ? Theme.accent.opacity(0.2) : .clear)
            .padding(.horizontal, 4).padding(.top, 4)
            .dropDestination(for: String.self) { items, _ in tab.drop(items, into: nil) } isTargeted: { targeted = $0 }
    }
}
