import SwiftUI
import GallraCore

/// Single-photo viewer: fit-to-window or 100%, fading overlay, optional filmstrip.
struct ViewerView: View {
    let tab: FolderTab
    @Environment(AppModel.self) private var model
    @State private var image: NSImage?
    @State private var overlayVisible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.canvas
                photoArea
                overlay.opacity(overlayVisible ? 1 : 0).animation(.easeOut(duration: 0.3), value: overlayVisible)
            }
            .onContinuousHover { phase in
                if case .active = phase { showOverlay() }
            }
            if tab.showFilmstrip { FilmstripView(tab: tab) }
        }
        .task(id: tab.currentPhoto?.id) {
            guard let photo = tab.currentPhoto else { return }
            if let hit = model.images.cached(photo, size: .full) { image = hit; return }
            // Keep the previous image on screen until the new one is ready (no flash).
            if let loaded = await model.images.image(photo, size: .full) { image = loaded }
        }
    }

    @ViewBuilder private var photoArea: some View {
        if let image {
            if tab.zoom100 {
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image).resizable()
                        .frame(width: image.size.width / scale, height: image.size.height / scale)
                }
            } else {
                Image(nsImage: image).resizable().scaledToFit()
                    .onTapGesture { tab.zoom100 = true }
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private var overlay: some View {
        VStack {
            HStack {
                Text(tab.currentPhoto?.fileName ?? "")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textPrimary)
                    .padding(8).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                Spacer()
            }
            Spacer()
            Text("\(tab.selection + 1) / \(tab.photos.count)")
                .font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .allowsHitTesting(false)
    }

    private func showOverlay() {
        overlayVisible = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { overlayVisible = false }
        }
    }
}

/// 64 pt strip of thumbnails along the bottom; keeps the current photo centered.
struct FilmstripView: View {
    let tab: FolderTab

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(Array(tab.photos.enumerated()), id: \.element.id) { index, photo in
                        ThumbnailView(photo: photo, size: 64, isSelected: false)
                            .opacity(index == tab.selection ? 1 : 0.7)
                            .overlay { if index == tab.selection { RoundedRectangle(cornerRadius: 4).stroke(Theme.accent, lineWidth: 2) } }
                            .id(photo.id)
                            .onTapGesture { tab.select(index) }
                    }
                }.padding(.horizontal, 8)
            }
            .onChange(of: tab.selection, initial: true) { _, new in
                if tab.photos.indices.contains(new) { proxy.scrollTo(tab.photos[new].id, anchor: .center) }
            }
        }
        .frame(height: 72)
        .background(Theme.window)
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }
}
