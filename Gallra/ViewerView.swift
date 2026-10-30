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
            let zoom = tab.viewerZoom
            let backingScale = NSScreen.main?.backingScaleFactor ?? 2
            GeometryReader { geo in
                ZStack {
                    if let layout = zoom.layout(0) {
                        Image(nsImage: image).resizable()
                            .frame(width: layout.size.width, height: layout.size.height)
                            .offset(layout.shift)
                    } else {
                        Image(nsImage: image).resizable().scaledToFit()
                    }
                }
                .allowsHitTesting(false)   // display only; the layer below takes the mouse
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                // Double-click zooms to 100% where you clicked (and back); drag, scroll and pinch pan and zoom.
                .overlay {
                    PaneInteraction(
                        onPan: { movement, _ in zoom.pan(pane: 0, movement: movement, independent: false) },
                        onZoom: { factor, point in zoom.zoom(pane: 0, factor: factor, at: point) },
                        onClick: {},
                        onDoubleClick: { zoom.toggleActualSize(backingScale: backingScale, at: $0) })
                }
                .onChange(of: geo.size, initial: true) { _, size in zoom.setMetrics(0, pane: size, image: image.size) }
                .onChange(of: image) { _, new in zoom.setMetrics(0, pane: geo.size, image: new.size) }
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private var overlay: some View {
        VStack {
            HStack {
                Text((tab.currentPhoto?.fileName ?? "") + starText)
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
        .overlay(alignment: .bottomLeading) { cameraPanel.padding(12) }
        .allowsHitTesting(false)
    }

    /// Small semi-transparent card with the shooting details of the current photo.
    @ViewBuilder private var cameraPanel: some View {
        let info = tab.cameraInfo
        let rows: [(String, String)] = [
            ("Lens", info.lens),
            ("Focal length", info.focalLength.map { "\(Int($0.rounded())) mm" }),
            ("Aperture", info.aperture.map { "f/" + Self.number($0) }),
            ("Shutter", info.shutter.flatMap { $0 > 0 ? ($0 >= 1 ? Self.number($0) + " s" : "1/\(Int((1 / $0).rounded())) s") : nil }),
            ("ISO", info.iso.map(String.init)),
        ].compactMap { label, value in value.map { (label, $0) } }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(rows, id: \.0) { label, value in
                    HStack(spacing: 10) {
                        Text(label).foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 16)
                        Text(value).foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .font(.system(size: 11).monospacedDigit())
            .fixedSize()   // as wide as the longest line (usually the lens name)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private var starText: String {
        let stars = tab.currentPhoto?.rating ?? 0
        return stars > 0 ? "  " + String(repeating: "★", count: stars) : ""
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
    @State private var position = ScrollPosition()
    @State private var offsetX: CGFloat = 0
    @State private var maxOffsetX: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(Array(tab.photos.enumerated()), id: \.element.id) { index, photo in
                        ThumbnailView(photo: photo, size: 48, isSelected: false)
                            .opacity(index == tab.selection ? 1 : 0.65)
                            .overlay { if index == tab.selection { RoundedRectangle(cornerRadius: 4).stroke(Theme.accent, lineWidth: 2) } }
                            .overlay(alignment: .bottomLeading) {
                                if let stars = photo.rating, stars > 0 {
                                    Text(String(repeating: "★", count: stars))
                                        .font(.system(size: 8)).foregroundStyle(Theme.star)
                                        .padding(.horizontal, 3).padding(.vertical, 1)
                                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 2))
                                        .padding(2)
                                }
                            }
                            .id(photo.id)
                            .onTapGesture { tab.select(index) }
                    }
                }.padding(.horizontal, 8)
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: [CGFloat].self) { geo in
                [geo.contentOffset.x, max(geo.contentSize.width - geo.containerSize.width, 0)]
            } action: { _, new in offsetX = new[0]; maxOffsetX = new[1] }
            .background(WheelCatcher { delta in
                position.scrollTo(x: min(max(offsetX - delta, 0), maxOffsetX))
            })
            .onChange(of: tab.selection, initial: true) { _, new in
                if tab.photos.indices.contains(new) { proxy.scrollTo(tab.photos[new].id, anchor: .center) }
            }
        }
        .frame(height: 56)
        .background(Theme.window)
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }
}

/// Turns a plain (vertical) mouse-wheel turn over this view into a callback, so a horizontal
/// strip can be scrolled with an ordinary mouse. Sideways trackpad swipes are left to the strip.
private struct WheelCatcher: NSViewRepresentable {
    let onWheel: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView { Catcher() }
    func updateNSView(_ view: NSView, context: Context) { (view as? Catcher)?.onWheel = onWheel }

    final class Catcher: NSView {
        var onWheel: ((CGFloat) -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }   // never steals clicks

        override func viewDidMoveToWindow() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)),
                      abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return event }
                let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
                self.onWheel?(delta)
                return nil
            }
        }
    }
}
