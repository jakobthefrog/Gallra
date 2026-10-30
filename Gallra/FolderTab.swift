import SwiftUI
import GallraCore

/// One tab: a folder, its photos, the selection, and whether the grid or the viewer is showing.
@MainActor
@Observable
final class FolderTab: Identifiable {
    enum Mode { case grid, viewer }

    let id = UUID()
    private unowned let model: AppModel
    private var watchTask: Task<Void, Never>?

    var folder: URL?
    var photos: [Photo] = []
    var isLoading = false
    var errorMessage: String?
    var selection = 0
    var mode: Mode = .grid
    var cellSize: Double = 160
    var showFilmstrip = true
    var zoom100 = false

    /// Number of columns last laid out by the grid (set by the view, used for up/down keys).
    var columns = 1

    var folderPath: String? { folder.map(FolderScanner.canonicalPath) }
    var title: String { folder?.lastPathComponent ?? "New Tab" }
    var currentPhoto: Photo? { photos.indices.contains(selection) ? photos[selection] : nil }

    init(model: AppModel) { self.model = model }

    func open(_ folder: URL) {
        watchTask?.cancel()
        self.folder = folder
        photos = []
        selection = 0
        mode = .grid
        errorMessage = nil
        isLoading = true
        reload()
        let browser = model.browser
        watchTask = Task { [weak self] in
            for await _ in browser.changes(in: folder) {
                try? await Task.sleep(for: .milliseconds(400))   // let bursts of changes settle
                self?.reload()
            }
        }
    }

    func close() { watchTask?.cancel() }

    private func reload() {
        guard let folder, let scanner = model.scanner else { return }
        Task {
            do {
                let found = try await scanner.scan(folder)
                let keep = currentPhoto?.id
                photos = found
                selection = keep.flatMap { id in found.firstIndex { $0.id == id } } ?? min(selection, max(found.count - 1, 0))
                errorMessage = nil
            } catch {
                errorMessage = "Could not read this folder."
            }
            isLoading = false
        }
    }

    // MARK: Navigation

    func move(by delta: Int) {
        guard !photos.isEmpty else { return }
        select(selection + delta)
    }

    func select(_ index: Int) {
        guard !photos.isEmpty else { return }
        selection = min(max(index, 0), photos.count - 1)
        if mode == .viewer { zoom100 = false; prefetchNeighbours() }
    }

    func openViewer() {
        guard currentPhoto != nil else { return }
        mode = .viewer
        zoom100 = false
        prefetchNeighbours()
    }

    func closeViewer() { mode = .grid; zoom100 = false }

    private func prefetchNeighbours() {
        let range = max(selection - 2, 0)...min(selection + 3, photos.count - 1)
        model.images.prefetch(range.map { photos[$0] }, size: .full)
    }
}
