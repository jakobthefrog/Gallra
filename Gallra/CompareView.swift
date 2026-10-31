import SwiftUI
import AppKit
import GallraCore

/// State of one compare session: the two photos, the active pane, and the linked zoom/pan.
@MainActor
@Observable
final class CompareState {
    struct Metrics { var pane: CGSize; var image: CGSize }

    /// File paths of the two photos being compared.
    let paths: [String]
    var active = 0
    private(set) var viewport = LinkedViewport()
    private var metrics: [Metrics?] = [nil, nil]

    init(paths: [String]) { self.paths = paths }

    func setMetrics(_ pane: Int, pane size: CGSize, image: CGSize) { metrics[pane] = Metrics(pane: size, image: image) }

    /// Size of the whole photo when it fits the pane.
    private func fit(_ pane: Int) -> CGSize? {
        guard let m = metrics[pane], m.image.width > 0, m.image.height > 0, m.pane.width > 0 else { return nil }
        let s = min(m.pane.width / m.image.width, m.pane.height / m.image.height)
        return CGSize(width: m.image.width * s, height: m.image.height * s)
    }

    /// Size the photo is drawn at, and where its centre sits relative to the pane centre.
    func layout(_ pane: Int) -> (size: CGSize, shift: CGSize)? {
        guard let f = fit(pane) else { return nil }
        let size = CGSize(width: f.width * viewport.zoom, height: f.height * viewport.zoom)
        let c = viewport.center(forPane: pane)
        return (size, CGSize(width: (0.5 - c.x) * size.width, height: (0.5 - c.y) * size.height))
    }

    /// Screen zoom of `pane` in percent (100 = one image pixel per screen pixel).
    func percent(_ pane: Int, backingScale: CGFloat) -> Int {
        guard let f = fit(pane), let m = metrics[pane] else { return 0 }
        return Int((f.width * viewport.zoom * backingScale / m.image.width * 100).rounded())
    }

    private func clamp() {
        let visible = (0..<2).map { pane -> CGSize in
            guard let f = fit(pane), let m = metrics[pane] else { return CGSize(width: 1, height: 1) }
            return CGSize(width: m.pane.width / (f.width * viewport.zoom),
                          height: m.pane.height / (f.height * viewport.zoom))
        }
        viewport.clamp(visible: visible)
    }

    /// `movement`: how far the user dragged the content, in points.
    func pan(pane: Int, movement: CGSize, independent: Bool) {
        guard let f = fit(pane) else { return }
        let d = CGSize(width: -movement.width / (f.width * viewport.zoom),
                       height: -movement.height / (f.height * viewport.zoom))
        viewport.pan(byFraction: d, pane: pane, independent: independent)
        clamp()
    }

    /// `at`: cursor position relative to the pane centre, in points.
    func zoom(pane: Int, factor: Double, at: CGPoint) {
        guard let f = fit(pane) else { return }
        viewport.setZoom(viewport.zoom * factor, anchor: CGSize(width: at.x / f.width, height: at.y / f.height))
        clamp()
    }

    /// Back to the whole photo.
    func resetZoom() { viewport.reset() }

    /// Z: toggle between whole photo and 100% of the active pane's photo.
    /// `at`: where to zoom in, relative to the active pane's centre in points (default: centre).
    func toggleActualSize(backingScale: CGFloat, at: CGPoint = .zero) {
        guard let f = fit(active), let m = metrics[active] else { return }
        let target = m.image.width / (backingScale * f.width)
        if abs(viewport.zoom - target) < 0.01 || target <= 1 { viewport.reset() }
        else { viewport.setZoom(target, anchor: CGSize(width: at.x / f.width, height: at.y / f.height)) }
        clamp()
    }
}

/// Two photos side by side with linked zoom and pan.
struct CompareView: View {
    let tab: FolderTab
    let state: CompareState

    var body: some View {
        HStack(spacing: 0) {
            ComparePane(tab: tab, state: state, pane: 0)
            Theme.line.frame(width: 1)
            ComparePane(tab: tab, state: state, pane: 1)
        }
        .overlay(alignment: .bottom) {
            Text("\(state.percent(state.active, backingScale: NSScreen.main?.backingScaleFactor ?? 2))%")
                .font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                .padding(10).allowsHitTesting(false)
        }
    }
}

private struct ComparePane: View {
    let tab: FolderTab
    let state: CompareState
    let pane: Int
    @Environment(AppModel.self) private var model
    @State private var image: NSImage?

    private var photo: Photo? { tab.allPhotos.first { $0.id.path == state.paths[pane] } }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.canvas
                if let image, let layout = state.layout(pane) {
                    Image(nsImage: image).resizable()
                        .frame(width: layout.size.width, height: layout.size.height)
                        .offset(layout.shift)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .allowsHitTesting(false)   // display only; the pane-sized layer below takes the mouse
            // Pin the layout box to the pane: a zoomed photo is bigger than the pane, and without
            // this the box grows, drifts to the top-left and its mouse area covers the other pane.
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            // Added after the frame so the mouse area is exactly the pane. Inside the ZStack it grew
            // with the zoomed photo and, in the right pane, covered the left pane and stole its clicks.
            .overlay {
                PaneInteraction(
                    onPan: { state.pan(pane: pane, movement: $0, independent: $1) },
                    onZoom: { state.zoom(pane: pane, factor: $0, at: $1) },
                    onClick: { state.active = pane },
                    onDoubleClick: { state.active = pane; state.toggleActualSize(backingScale: NSScreen.main?.backingScaleFactor ?? 2, at: $0) })
            }
            .overlay(alignment: .topLeading) { header }
            .contextMenu { FinderMenu(photo: photo?.id.path, folder: tab.folderPath) }
            .overlay(alignment: .top) { if state.active == pane { Theme.accent.frame(height: 2) } }
            .onChange(of: geo.size, initial: true) { _, _ in publishMetrics(geo.size) }
            .onChange(of: image) { _, _ in publishMetrics(geo.size) }
        }
        .task(id: state.paths[pane]) {
            guard let photo else { return }
            image = await model.images.image(photo, size: .full)
        }
    }

    private func publishMetrics(_ size: CGSize) {
        guard let image else { return }
        state.setMetrics(pane, pane: size, image: image.size)
    }

    private var header: some View {
        let stars = photo?.rating ?? 0
        return Text((photo?.fileName ?? "") + (stars > 0 ? "  " + String(repeating: "★", count: stars) : ""))
            .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary)
            .padding(6).background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .padding(8).allowsHitTesting(false)
    }
}

/// Transparent AppKit view that turns mouse, trackpad and pinch input into pan and zoom.
/// Drag or two-finger scroll pans; pinch or Cmd+scroll zooms; Option makes the pan independent.
struct PaneInteraction: NSViewRepresentable {
    var onPan: (CGSize, Bool) -> Void
    var onZoom: (Double, CGPoint) -> Void
    var onClick: () -> Void
    var onDoubleClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> InteractionView { InteractionView() }
    func updateNSView(_ view: InteractionView, context: Context) {
        view.onPan = onPan; view.onZoom = onZoom; view.onClick = onClick; view.onDoubleClick = onDoubleClick
    }

    final class InteractionView: NSView {
        var onPan: (CGSize, Bool) -> Void = { _, _ in }
        var onZoom: (Double, CGPoint) -> Void = { _, _ in }
        var onClick: () -> Void = {}
        var onDoubleClick: (CGPoint) -> Void = { _ in }
        override var isFlipped: Bool { true }

        private func fromCentre(_ event: NSEvent) -> CGPoint {
            let p = convert(event.locationInWindow, from: nil)
            return CGPoint(x: p.x - bounds.midX, y: p.y - bounds.midY)
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { onDoubleClick(fromCentre(event)) } else { onClick() }
        }
        override func mouseDragged(with event: NSEvent) {
            onPan(CGSize(width: event.deltaX, height: event.deltaY), event.modifierFlags.contains(.option))
        }
        override func scrollWheel(with event: NSEvent) {
            let k: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            if event.modifierFlags.contains(.command) {
                onZoom(exp(Double(event.scrollingDeltaY * k) * 0.01), fromCentre(event))
            } else {
                onPan(CGSize(width: event.scrollingDeltaX * k, height: event.scrollingDeltaY * k),
                      event.modifierFlags.contains(.option))
            }
        }
        override func magnify(with event: NSEvent) {
            onZoom(1 + Double(event.magnification), fromCentre(event))
        }
    }
}
