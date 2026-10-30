import SwiftUI
import GallraCore

/// Scrollable thumbnail grid. Single click selects; double click opens the viewer.
struct GridView: View {
    let tab: FolderTab
    private let gap: Double = 4
    @State private var pinchBase: Double?

    var body: some View {
        GeometryReader { geo in
            let cols = max(1, Int((geo.size.width - gap) / (tab.cellSize + gap)))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(tab.cellSize), spacing: gap), count: cols),
                              spacing: gap) {
                        ForEach(Array(tab.photos.enumerated()), id: \.element.id) { index, photo in
                            ThumbnailView(photo: photo, size: tab.cellSize, isSelected: index == tab.selection)
                                .id(photo.id)
                                .onTapGesture(count: 2) { tab.select(index); tab.openViewer() }
                                .onTapGesture { tab.select(index) }
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
