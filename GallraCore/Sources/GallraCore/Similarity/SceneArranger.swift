import Foundation

/// Applies the user's hand-made groups on top of the automatic scenes. Pure logic.
public enum SceneArranger {
    /// `manual` maps a photo's file path to the id of the group the user put it in.
    /// Those photos leave their automatic scene (emptied scenes disappear) and form the manual
    /// groups. Result is in time order, numbered 0, 1, 2...; photos inside a scene are in time order.
    public static func apply(manual: [String: String], photos: [Photo], to auto: [PhotoScene]) -> [PhotoScene] {
        let byPath = Dictionary(photos.map { ($0.id.path, $0) }, uniquingKeysWith: { a, _ in a })
        func time(_ p: Photo) -> Date { p.captureDate ?? p.modified }
        func inOrder(_ list: [Photo]) -> [Photo] {
            list.sorted { time($0) == time($1) ? $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
                                                : time($0) < time($1) }
        }

        var entries: [(start: Date?, ids: [PhotoID], manualID: String?)] = []
        for scene in auto {
            let ids = scene.photos.filter { manual[$0.path] == nil }
            if ids.isEmpty { continue }
            entries.append((byPath[ids[0].path]?.captureDate ?? scene.start, ids, nil))
        }
        var groups: [String: [Photo]] = [:]
        for (path, group) in manual { if let photo = byPath[path] { groups[group, default: []].append(photo) } }
        for (group, members) in groups {
            let sorted = inOrder(members)
            entries.append((sorted[0].captureDate, sorted.map(\.id), group))
        }
        let ordered = entries.enumerated().sorted { a, b in
            switch (a.element.start, b.element.start) {
            case let (x?, y?): return x == y ? a.offset < b.offset : x < y
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.offset < b.offset
            }
        }
        return ordered.enumerated().map { n, e in
            PhotoScene(id: n, photos: e.element.ids, start: e.element.start, manualID: e.element.manualID)
        }
    }
}
