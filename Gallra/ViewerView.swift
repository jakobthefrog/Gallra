import SwiftUI
import GallraCore

/// Single-photo viewer: fit-to-window or 100%, fading overlay, optional filmstrip.
struct ViewerView: View {
    let tab: FolderTab
    @Environment(AppModel.self) private var model
    @State private var image: NSImage?
    @AppStorage("showCameraInfo") private var showCameraInfo = true
    @AppStorage("focusPeaking") private var peakingOn = false
    @State private var peaking: NSImage?
    /// Crisp overlay for just the visible area, used when zoomed in.
    @State private var detail: (image: NSImage, region: CGRect)?
    @State private var overlayVisible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.canvas
                photoArea
                overlay.opacity(overlayVisible ? 1 : 0).animation(.easeOut(duration: 0.3), value: overlayVisible)
                // Camera details stay on screen (toggle with I); only the name and counter fade.
                if showCameraInfo {
                    cameraPanel.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .allowsHitTesting(false)
                }
                peakingButton.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .onContinuousHover { phase in
                if case .active = phase { showOverlay() }
            }
            .contextMenu { FinderMenu(photo: tab.currentPhoto?.id.path, folder: tab.folderPath) }
            if tab.showFilmstrip { FilmstripView(tab: tab) }
        }
        .task(id: PeakingKey(photo: tab.currentPhoto?.id, on: peakingOn)) {
            // Focus peaking: clear the old overlay at once, then compute the new one in the background.
            peaking = nil
            detail = nil
            guard peakingOn, let photo = tab.currentPhoto else { return }
            peaking = await model.images.peakingOverlay(for: photo)
        }
        .task(id: tab.currentPhoto?.id) {
            guard let photo = tab.currentPhoto else { return }
            if let hit = model.images.cached(photo, size: .full) { image = hit; return }
            // Show the (usually cached) thumbnail right away so the right photo is on screen
            // while the big one loads. The short delay means photos you fly past never load.
            if let thumb = model.images.cached(photo, size: .thumbnail) { image = thumb }
            if let loaded = await model.images.image(photo, size: .full, delay: .milliseconds(70)) { image = loaded }
        }
    }

    @ViewBuilder private var photoArea: some View {
        if let image {
            let zoom = tab.viewerZoom
            let backingScale = NSScreen.main?.backingScaleFactor ?? 2
            GeometryReader { geo in
                let visible = Self.visibleRect(zoom, pane: geo.size)
                let zoomedIn = (zoom.layout(0)?.size.width ?? 0) * backingScale > 2400
                let covered = visible.map { v in detail?.region.contains(v) ?? false } ?? false
                ZStack {
                    if let layout = zoom.layout(0) {
                        Image(nsImage: image).resizable()
                            .overlay { peakingLayer(visible: visible, zoomedIn: zoomedIn) }
                            .frame(width: layout.size.width, height: layout.size.height)
                            .offset(layout.shift)
                    } else {
                        Image(nsImage: image).resizable().scaledToFit()
                            .overlay { peakingLayer(visible: visible, zoomedIn: zoomedIn) }
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
                // When zoomed in, re-analyse just the visible area at full detail (after a short pause).
                .task(id: DetailKey(photo: tab.currentPhoto?.id, wanted: peakingOn && zoomedIn && !covered,
                                    area: Self.rounded(visible))) {
                    guard peakingOn, zoomedIn, !covered, let visible, let photo = tab.currentPhoto else { return }
                    try? await Task.sleep(for: .milliseconds(250))
                    if Task.isCancelled { return }
                    let margin = visible.insetBy(dx: -visible.width * 0.25, dy: -visible.height * 0.25)
                        .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                    if let result = await model.images.peakingDetail(for: photo, region: margin) { detail = result }
                }
                .onChange(of: geo.size, initial: true) { _, size in zoom.setMetrics(0, pane: size, image: image.size) }
                .onChange(of: image) { _, new in zoom.setMetrics(0, pane: geo.size, image: new.size) }
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    /// Focus-peaking colour layer; sits exactly on the photo so it follows zoom and pan.
    /// Zoomed in, the crisp detail layer replaces the whole-photo one while it covers what you see.
    @ViewBuilder private func peakingLayer(visible: CGRect?, zoomedIn: Bool) -> some View {
        if peakingOn {
            if zoomedIn, let detail, let visible, detail.region.contains(visible) {
                GeometryReader { g in
                    Image(nsImage: detail.image).resizable().interpolation(.none)
                        .frame(width: detail.region.width * g.size.width, height: detail.region.height * g.size.height)
                        .offset(x: detail.region.minX * g.size.width, y: detail.region.minY * g.size.height)
                }
                .allowsHitTesting(false)
            } else if let peaking {
                Image(nsImage: peaking).resizable().interpolation(.low).allowsHitTesting(false)
            }
        }
    }

    /// Part of the photo currently on screen, as fractions (0...1) of the photo.
    private static func visibleRect(_ zoom: CompareState, pane: CGSize) -> CGRect? {
        guard let size = zoom.layout(0)?.size, size.width > 0, size.height > 0 else { return nil }
        let c = zoom.viewport.center(forPane: 0)
        let w = min(1, pane.width / size.width), h = min(1, pane.height / size.height)
        return CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
    }

    private static func rounded(_ r: CGRect?) -> CGRect? {
        r.map { CGRect(x: ($0.minX * 100).rounded() / 100, y: ($0.minY * 100).rounded() / 100,
                       width: ($0.width * 100).rounded() / 100, height: ($0.height * 100).rounded() / 100) }
    }

    private struct DetailKey: Hashable { let photo: Photo.ID?; let wanted: Bool; let area: CGRect? }

    /// Small on/off chip for focus peaking (also the P key).
    private var peakingButton: some View {
        Button { peakingOn.toggle() } label: {
            HStack(spacing: 6) {
                Circle().fill(peakingOn ? Theme.reject : Theme.textDisabled).frame(width: 8, height: 8)
                Text("Peaking").foregroundStyle(peakingOn ? Theme.textPrimary : Theme.textSecondary)
                Text("P").foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 4)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.line))
            }
            .font(.system(size: 11))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("Highlight in-focus edges (P)")
    }

    private struct PeakingKey: Hashable { let photo: Photo.ID?; let on: Bool }

    private var overlay: some View {
        VStack {
            Spacer()
            Text("\(tab.selection + 1) / \(tab.photos.count)")
                .font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(12)
        .allowsHitTesting(false)
    }

    /// Small semi-transparent card with the file name and shooting details of the current photo.
    @ViewBuilder private var cameraPanel: some View {
        let info = tab.cameraInfo
        if let photo = tab.currentPhoto {
            let rows = ShotDetails.rows(photo, info).compactMap { row in row.value.map { (row.label, $0) } }
            VStack(alignment: .leading, spacing: 3) {
                (Text(photo.fileName).foregroundStyle(.white) + Text(starText).foregroundStyle(Theme.star)).padding(.bottom, 2)
                ForEach(rows, id: \.0) { label, value in
                    HStack(spacing: 10) {
                        Text(label).foregroundStyle(Theme.accent)
                        Spacer(minLength: 16)
                        Text(value).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .font(.system(size: 11).monospacedDigit())
            .fixedSize()   // as wide as the longest line
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
                        ThumbnailView(photo: photo, size: 48, isSelected: false, hoverBorder: false)
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
                            .contextMenu { FinderMenu(photo: photo.id.path, folder: tab.folderPath) }
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
