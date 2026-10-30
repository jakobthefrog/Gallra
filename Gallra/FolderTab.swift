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
    var allPhotos: [Photo] = [] {
        didSet { applyFilter(); if grouping { refreshScenes() }; if wantsCameraInfo { loadAllCameraInfo() } }
    }
    private(set) var photos: [Photo] = []
    var filter: RatingFilter = .all { didSet { applyFilter() } }
    /// Filter by lens, aperture, shutter, ISO and focal length (needs `loadAllCameraInfo`).
    var cameraFilter = CameraFilter() { didSet { applyFilter() } }
    /// The values present in this folder, offered as choices in the filter panel.
    private(set) var choices = CameraChoices()
    /// (done, total) while camera info is being read for the whole folder.
    private(set) var cameraLoad: (Int, Int)?
    private var wantsCameraInfo = false
    private var cameraScanTask: Task<Void, Never>?
    /// Short message about the last action (shown in the status bar for a few seconds).
    var notice: String?
    var noticeUndoable = false
    var noticeIsError = false
    private var noticeTask: Task<Void, Never>?
    private var writeChain: Task<Void, Never>?
    var isLoading = false
    var errorMessage: String?
    var selection = 0 { didSet { if selection != oldValue { loadCameraInfo() } } }
    /// True after a click on empty space or Esc: no photo is selected, though `selection` remembers
    /// where it was so arrow keys carry on from there. Rating and reject keys do nothing then.
    private(set) var isDeselected = false { didSet { if isDeselected != oldValue { loadCameraInfo() } } }
    /// Shooting details of the selected photo (empty until read).
    private(set) var cameraInfo = CameraInfo()
    private var cameraTask: Task<Void, Never>?
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
    var currentPhoto: Photo? { !isDeselected && photos.indices.contains(selection) ? photos[selection] : nil }

    init(model: AppModel) { self.model = model }

    func open(_ folder: URL) {
        watchTask?.cancel()
        self.folder = folder
        cameraFilter = CameraFilter()
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

    // MARK: Scene grouping

    /// A scene header and the part of `photos` it covers (empty range when collapsed).
    struct SceneSection: Identifiable {
        let id: String            // path of the scene's first photo
        let title: String
        let best: Int             // highest star rating in the scene
        let collapsed: Bool
        let range: Range<Int>
    }

    var grouping = false {
        didSet {
            if grouping { refreshScenes() } else { groupTask?.cancel(); groupProgress = nil }
            applyFilter()
        }
    }
    private(set) var sections: [SceneSection] = []
    /// (done, total) while feature prints are being made.
    var groupProgress: (Int, Int)?
    private var scenes: [PhotoScene] = []       // automatic scenes with the user's groups applied
    private var autoScenes: [PhotoScene] = []
    private var manual: [String: String] = [:]  // photo path -> hand-made group id
    private var groupedPaths: Set<String> = []
    private var collapsed: Set<String> = []
    private var groupTask: Task<Void, Never>?

    func toggleCollapsed(_ sectionID: String) {
        if collapsed.contains(sectionID) { collapsed.remove(sectionID) } else { collapsed.insert(sectionID) }
        applyFilter()
    }

    /// Works out the scenes in the background (view only; no file is touched).
    private func refreshScenes() {
        let paths = Set(allPhotos.map(\.id.path))
        guard let similarity = model.similarity, !paths.isEmpty, paths != groupedPaths else { return }
        groupedPaths = paths
        groupTask?.cancel()
        let photos = allPhotos
        let catalog = model.catalog
        let folderPath = self.folderPath
        groupTask = Task { [weak self] in
            if let catalog, let folderPath, let saved = try? await catalog.manualGroups(inFolder: folderPath) {
                self?.manual = saved
            }
            let found = await similarity.scenes(for: photos) { done, total in
                Task { @MainActor in self?.groupProgress = done < total ? (done, total) : nil }
            }
            guard !Task.isCancelled, let self else { return }
            self.groupProgress = nil
            self.autoScenes = found
            self.rearrange()
        }
    }

    private func rearrange() {
        scenes = SceneArranger.apply(manual: manual, photos: allPhotos, to: autoScenes)
        applyFilter()
    }

    /// Undo of a grouping action: puts the earlier group assignments back.
    func restoreGrouping(previous: [String: String], unassigned: [String]) {
        for path in unassigned { manual[path] = nil }
        manual.merge(previous) { _, new in new }
        rearrange()
        guard let folderPath else { return }
        let catalog = model.catalog
        Task {
            try? await catalog?.removeManualGroups(paths: unassigned)
            try? await catalog?.setManualGroups(previous, folder: folderPath)
        }
    }

    /// What a drag of `photo` carries: all marked photos if it is one of them, else just itself.
    func dragPayload(for photo: Photo) -> String {
        let paths = marked.contains(photo.id.path) ? Array(marked) : [photo.id.path]
        return paths.joined(separator: "\n")
    }

    /// Drop handler: moves the dragged photos into the scene `sectionID`, or into a new group (nil).
    @discardableResult
    func drop(_ items: [String], into sectionID: String?) -> Bool {
        guard grouping, let folderPath else { return false }
        let known = Set(allPhotos.map(\.id.path))
        let moving = items.flatMap { $0.split(separator: "\n").map(String.init) }.filter(known.contains)
        guard !moving.isEmpty else { return false }
        var assignments: [String: String] = [:]
        var group = UUID().uuidString
        if let sectionID, let target = scenes.first(where: { $0.photos.first?.path == sectionID }) {
            if Set(moving).isSubset(of: Set(target.photos.map(\.path))) { return false }   // already there
            if let existing = target.manualID { group = existing }
            else { for id in target.photos { assignments[id.path] = group } }   // scene becomes a hand-made group
        }
        for path in moving { assignments[path] = group }
        let previous = assignments.keys.reduce(into: [String: String]()) { if let old = manual[$1] { $0[$1] = old } }
        model.undoStack.append(.grouping(tab: id, previous: previous,
                                         unassigned: assignments.keys.filter { manual[$0] == nil }))
        manual.merge(assignments) { _, new in new }
        rearrange()
        showNotice(sectionID == nil ? "Started a new group with \(moving.count) photo\(moving.count == 1 ? "" : "s")."
                                    : "Moved \(moving.count) photo\(moving.count == 1 ? "" : "s") to the group.")
        let catalog = model.catalog
        Task { try? await catalog?.setManualGroups(assignments, folder: folderPath) }
        return true
    }

    private func applyFilter() {
        let keep = currentPhoto?.id.path
        var ordered = filter.apply(to: allPhotos)
        if cameraFilter.isActive {
            ordered = ordered.filter { cameraFilter.matches(CameraInfoCache.values[$0.id.path]) }
        }
        sections = []
        if grouping && !scenes.isEmpty {
            var place: [String: (scene: Int, pos: Int)] = [:]
            for (n, scene) in scenes.enumerated() {
                for (pos, id) in scene.photos.enumerated() { place[id.path] = (n, pos) }
            }
            ordered.sort {
                let a = place[$0.id.path] ?? (Int.max, 0), b = place[$1.id.path] ?? (Int.max, 0)
                return a.0 != b.0 ? a.0 < b.0 : a.1 < b.1
            }
            var visible: [Photo] = []
            var i = 0
            while i < ordered.count {
                guard let n = place[ordered[i].id.path]?.scene else { visible.append(ordered[i]); i += 1; continue }
                var j = i
                while j < ordered.count, place[ordered[j].id.path]?.scene == n { j += 1 }
                let members = Array(ordered[i..<j])
                let id = scenes[n].photos[0].path
                let isCollapsed = collapsed.contains(id)
                let start = visible.count
                if !isCollapsed { visible += members }
                var title = "Scene · \(members.count) photo\(members.count == 1 ? "" : "s")"
                if let date = members[0].captureDate { title += " · " + date.formatted(date: .omitted, time: .shortened) }
                sections.append(SceneSection(id: id, title: title, best: members.compactMap(\.rating).max() ?? 0,
                                             collapsed: isCollapsed, range: start..<visible.count))
                i = j
            }
            ordered = visible
        }
        photos = ordered
        if let keep, let index = photos.firstIndex(where: { $0.id.path == keep }) { selection = index }
        else { selection = min(selection, max(photos.count - 1, 0)) }
        loadCameraInfo()
    }

    /// Reads the selected photo's lens, aperture, shutter and ISO in the background.
    private func loadCameraInfo() {
        cameraTask?.cancel()
        guard let url = currentPhoto?.url else { cameraInfo = CameraInfo(); return }
        if let hit = CameraInfoCache.values[url.path] { cameraInfo = hit; return }
        cameraTask = Task { [weak self] in
            let info = await Task.detached { PhotoMetadataReader().cameraInfo(url) }.value
            CameraInfoCache.values[url.path] = info
            if !Task.isCancelled { self?.cameraInfo = info }
        }
    }

    /// Reads camera info (EXIF, read-only) for every photo in the folder, a batch at a time,
    /// so the filter panel can offer choices and the grid can be filtered by them.
    func loadAllCameraInfo() {
        wantsCameraInfo = true
        refreshChoices()
        let missing = allPhotos.map(\.url).filter { CameraInfoCache.values[$0.path] == nil }
        cameraScanTask?.cancel()
        guard !missing.isEmpty else { cameraLoad = nil; return }
        cameraScanTask = Task { [weak self] in
            var done = 0
            for start in stride(from: 0, to: missing.count, by: 24) {
                let batch = Array(missing[start..<min(start + 24, missing.count)])
                let read = await Task.detached { batch.map { ($0.path, PhotoMetadataReader().cameraInfo($0)) } }.value
                guard !Task.isCancelled, let self else { return }
                for (path, info) in read { CameraInfoCache.values[path] = info }
                done += batch.count
                self.cameraLoad = (done, missing.count)
                self.refreshChoices()
                if self.cameraFilter.isActive { self.applyFilter() }
            }
            self?.cameraLoad = nil
        }
    }

    private func refreshChoices() {
        choices = CameraChoices(allPhotos.compactMap { CameraInfoCache.values[$0.id.path] })
    }

    /// Shows a toast. `undoable` adds an Undo button and keeps it up for 8 s instead of 4.
    func showNotice(_ text: String, undoable: Bool = false, isError: Bool = false) {
        notice = text
        noticeUndoable = undoable
        noticeIsError = isError
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(undoable ? 8 : 4))
            if !Task.isCancelled { notice = nil }
        }
    }

    // MARK: Cull actions

    /// Sets the current photo's star rating (0 clears; pressing the same rating again clears it). Shown at once; written to the file in
    /// the background, one write at a time. Put back with a message if the write fails.
    func setRating(_ requested: Int) {
        guard let photo = targetPhoto else { return }
        // Pressing the rating the photo already has clears it.
        let stars = requested > 0 && photo.rating == requested ? 0 : requested
        guard photo.rating != stars else { return }
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
                    self.showNotice("\(URL(fileURLWithPath: path).lastPathComponent) has no rating field; left unchanged.", isError: true)
                } else {
                    self.showNotice("Could not write rating (file left unchanged).", isError: true)
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
        if !batch.isEmpty { model.undoStack.append(.reject(batch)) }
        let gone = Set(batch.files.map { $0.original.path })
        allPhotos.removeAll { gone.contains($0.id.path) }
        if mode == .viewer && photos.isEmpty { mode = .grid }
        if mode == .compare { closeCompare() }
        marked.subtract(gone)
        var text = "Moved \(batch.files.count) photo\(batch.files.count == 1 ? "" : "s") to Rejected · Undo (Cmd+Z)"
        if !failures.isEmpty { text += " \(failures.count) could not be moved." }
        showNotice(text, undoable: !batch.isEmpty, isError: batch.isEmpty)
        reload()
    }

    // MARK: Navigation

    func move(by delta: Int) {
        guard !photos.isEmpty else { return }
        select(selection + delta)
    }

    /// Up (`rows` = -1) or down (`rows` = 1) in the grid. In the grouped grid every scene
    /// starts a fresh row, so a short last row is handled per scene instead of by a fixed step.
    func moveVertically(_ rows: Int) {
        guard !photos.isEmpty else { return }
        let cols = max(columns, 1)
        let shown = sections.filter { !$0.range.isEmpty }
        guard let at = shown.firstIndex(where: { $0.range.contains(selection) }) else {
            move(by: rows * cols)       // ungrouped grid
            return
        }
        let range = shown[at].range
        let offset = selection - range.lowerBound
        let row = offset / cols, col = offset % cols
        if rows > 0 {
            if (row + 1) * cols < range.count {
                select(range.lowerBound + min((row + 1) * cols + col, range.count - 1))
            } else if at + 1 < shown.count {
                let next = shown[at + 1].range
                select(next.lowerBound + min(col, next.count - 1))
            }
        } else if row > 0 {
            select(range.lowerBound + (row - 1) * cols + col)
        } else if at > 0 {
            let prev = shown[at - 1].range
            let lastRow = (prev.count - 1) / cols
            select(prev.lowerBound + min(lastRow * cols + col, prev.count - 1))
        }
    }

    /// Clears the selection and any marks (click on empty grid space, or Esc).
    func deselect() {
        marked = []
        isDeselected = true
    }

    func select(_ index: Int) {
        guard !photos.isEmpty else { return }
        isDeselected = false
        if mode == .grid { marked = [] }
        selection = min(max(index, 0), photos.count - 1)
        if mode == .viewer { zoom100 = false; prefetchNeighbours() }
    }

    func openViewer() {
        isDeselected = false
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
        isDeselected = false
        guard let pair = comparePair else { showNotice("Need at least two photos to compare."); return }
        compare = CompareState(paths: pair.map(\.id.path))
        mode = .compare
    }

    func closeCompare() { compare = nil; mode = .grid }

    /// Cmd-click: add or remove a photo from the marked set.
    func toggleMark(_ index: Int) {
        guard photos.indices.contains(index) else { return }
        isDeselected = false
        // Make sure the previously selected photo counts as the first mark.
        if marked.isEmpty, let current = currentPhoto { marked.insert(current.id.path) }
        let path = photos[index].id.path
        if marked.contains(path) { marked.remove(path) } else { marked.insert(path) }
        selection = index
    }

    /// Shift+arrow: move the selection and mark both the old and the new photo.
    func extendMark(by delta: Int) {
        guard let from = currentPhoto else { move(by: delta); return }
        marked.insert(from.id.path)
        move(by: delta)
        if let to = currentPhoto { marked.insert(to.id.path) }
    }

    private func prefetchNeighbours() {
        let range = max(selection - 2, 0)...min(selection + 3, photos.count - 1)
        model.images.prefetch(range.map { photos[$0] }, size: .full)
    }
}
