import SwiftUI
import GallraCore

/// One tab: a folder, its photos, the selection, and whether the grid or the viewer is showing.
@MainActor
@Observable
final class FolderTab: Identifiable {
    enum Mode { case grid, viewer, compare }

    let id = UUID()
    private unowned let model: AppModel
    private var watchTask: Task<Void, Never>?

    var folder: URL?
    /// Every photo in the folder; `photos` is the part that passes `filter`.
    var allPhotos: [Photo] = [] { didSet { applyFilter() } }
    private(set) var photos: [Photo] = []
    var filter: RatingFilter = .all { didSet { applyFilter() } }
    /// Short message about the last action (shown in the status bar for a few seconds).
    var notice: String?
    private var noticeTask: Task<Void, Never>?
    private var writeChain: Task<Void, Never>?
    var isLoading = false
    var errorMessage: String?
    var selection = 0
    var mode: Mode = .grid
    var cellSize: Double = 160
    var showFilmstrip = true
    var zoom100 = false
    /// Photos marked with Cmd-click or Shift+arrows (by path), used to pick a compare pair.
    var marked: Set<String> = []
    var compare: CompareState?

    /// Number of columns last laid out by the grid (set by the view, used for up/down keys).
    var columns = 1

    var folderPath: String? { folder.map(FolderScanner.canonicalPath) }
    var title: String { folder?.lastPathComponent ?? "New Tab" }
    var currentPhoto: Photo? { photos.indices.contains(selection) ? photos[selection] : nil }

    init(model: AppModel) { self.model = model }

    func open(_ folder: URL) {
        watchTask?.cancel()
        self.folder = folder
        allPhotos = []
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

    func reload() {
        guard let folder, let scanner = model.scanner else { return }
        Task {
            do {
                let found = try await scanner.scan(folder)
                // Match by path: a rating write replaces the file, which can change its file number.
                let keep = currentPhoto?.id.path
                allPhotos = found
                selection = keep.flatMap { path in photos.firstIndex { $0.id.path == path } }
                    ?? min(selection, max(photos.count - 1, 0))
                errorMessage = nil
            } catch {
                errorMessage = "Could not read this folder."
            }
            isLoading = false
        }
    }

    private func applyFilter() {
        let keep = currentPhoto?.id.path
        photos = filter.apply(to: allPhotos)
        if let keep, let index = photos.firstIndex(where: { $0.id.path == keep }) { selection = index }
        else { selection = min(selection, max(photos.count - 1, 0)) }
    }

    func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { notice = nil }
        }
    }

    // MARK: Cull actions

    /// Sets the current photo's star rating (0 clears). Shown at once; written to the file in
    /// the background, one write at a time. Put back with a message if the write fails.
    func setRating(_ stars: Int) {
        guard let photo = targetPhoto, photo.rating != stars else { return }
        update(photo.id.path) { $0.rating = stars }
        let writer = model.ratingWriter
        let previous = photo.rating
        let path = photo.id.path
        let before = writeChain
        writeChain = Task { [weak self] in
            await before?.value
            let result = await Task.detached { Result { try writer.write(rating: stars, to: URL(fileURLWithPath: path)) } }.value
            guard let self else { return }
            if case .failure(let error) = result {
                self.update(path) { $0.rating = previous }
                if case RatingError.noRatingField = error {
                    self.showNotice("\(URL(fileURLWithPath: path).lastPathComponent) has no rating field; left unchanged.")
                } else {
                    self.showNotice("Could not write rating (file left unchanged).")
                }
            }
            self.reload()
        }
    }

    private func update(_ path: String, _ change: (inout Photo) -> Void) {
        guard let index = allPhotos.firstIndex(where: { $0.id.path == path }) else { return }
        change(&allPhotos[index])
    }

    /// Moves the current photo to the Rejected folder (undo with Cmd+Z).
    func rejectCurrent() {
        guard let photo = targetPhoto else { return }
        reject([photo])
    }

    /// The photo that rating and reject keys act on: the active compare pane, else the current photo.
    private var targetPhoto: Photo? {
        if mode == .compare, let compare {
            return allPhotos.first { $0.id.path == compare.paths[compare.active] }
        }
        return currentPhoto
    }

    /// Photos in the current view that have no stars.
    var unratedInView: [Photo] { photos.filter { ($0.rating ?? 0) == 0 } }

    func rejectUnrated() { reject(unratedInView) }

    private func reject(_ list: [Photo]) {
        guard !list.isEmpty else { return }
        let (batch, failures) = RejectService().reject(list)
        if !batch.isEmpty { model.undoStack.append(batch) }
        let gone = Set(batch.files.map { $0.original.path })
        allPhotos.removeAll { gone.contains($0.id.path) }
        if mode == .viewer && photos.isEmpty { mode = .grid }
        if mode == .compare { closeCompare() }
        marked.subtract(gone)
        var text = "Moved \(batch.files.count) to \(FolderBrowser.rejectedFolderName). Cmd+Z to undo."
        if !failures.isEmpty { text += " \(failures.count) could not be moved." }
        showNotice(text)
        reload()
    }

    // MARK: Navigation

    func move(by delta: Int) {
        guard !photos.isEmpty else { return }
        select(selection + delta)
    }

    func select(_ index: Int) {
        guard !photos.isEmpty else { return }
        if mode == .grid { marked = [] }
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

    // MARK: Compare

    /// Marked photos if exactly two are marked, else the current photo and its neighbour.
    private var comparePair: [Photo]? {
        let picked = photos.filter { marked.contains($0.id.path) }
        if picked.count == 2 { return picked }
        guard photos.count >= 2, let current = currentPhoto else { return nil }
        let other = selection + 1 < photos.count ? photos[selection + 1] : photos[selection - 1]
        return [current, other].sorted { photos.firstIndex(of: $0)! < photos.firstIndex(of: $1)! }
    }

    func openCompare() {
        guard let pair = comparePair else { showNotice("Need at least two photos to compare."); return }
        compare = CompareState(paths: pair.map(\.id.path))
        mode = .compare
    }

    func closeCompare() { compare = nil; mode = .grid }

    /// Cmd-click: add or remove a photo from the marked set.
    func toggleMark(_ index: Int) {
        guard photos.indices.contains(index) else { return }
        // Make sure the previously selected photo counts as the first mark.
        if marked.isEmpty, let current = currentPhoto { marked.insert(current.id.path) }
        let path = photos[index].id.path
        if marked.contains(path) { marked.remove(path) } else { marked.insert(path) }
        selection = index
    }

    /// Shift+arrow: move the selection and mark both the old and the new photo.
    func extendMark(by delta: Int) {
        guard let from = currentPhoto else { return }
        marked.insert(from.id.path)
        move(by: delta)
        if let to = currentPhoto { marked.insert(to.id.path) }
    }

    private func prefetchNeighbours() {
        let range = max(selection - 2, 0)...min(selection + 3, photos.count - 1)
        model.images.prefetch(range.map { photos[$0] }, size: .full)
    }
}
