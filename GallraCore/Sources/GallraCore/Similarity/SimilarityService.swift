import Foundation
import Vision

/// Groups photos into scenes: Vision feature prints of the small previews plus capture-time
/// proximity. Prints are cached in the catalog, so each photo is analysed once. Read-only.
public actor SimilarityService {
    private let previews: PreviewService
    private let catalog: Catalog
    private var observations: [String: VNFeaturePrintObservation] = [:]

    public init(previews: PreviewService, catalog: Catalog) {
        self.previews = previews
        self.catalog = catalog
    }

    /// Scenes for `photos`, in time order. `progress(done, total)` is called as prints are made.
    public func scenes(for photos: [Photo], settings: SceneSettings = SceneSettings(),
                       progress: (@Sendable (Int, Int) -> Void)? = nil) async -> [PhotoScene] {
        let ordered = photos.sorted {
            let a = $0.captureDate ?? $0.modified, b = $1.captureDate ?? $1.modified
            return a == b ? $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending : a < b
        }
        var done = 0
        for photo in ordered {
            if Task.isCancelled { return [] }
            _ = await observation(for: photo)
            done += 1
            progress?(done, ordered.count)
        }
        let keys = ordered.map { $0.id.path }
        let numbers = SceneClusterer.cluster(times: ordered.map(\.captureDate), settings: settings) { i, j in
            guard let a = self.observations[keys[i]], let b = self.observations[keys[j]] else { return nil }
            var distance: Float = 0
            return (try? a.computeDistance(&distance, to: b)) != nil ? distance : nil
        }
        var grouped: [Int: [Photo]] = [:]
        for (photo, n) in zip(ordered, numbers) { grouped[n, default: []].append(photo) }
        return grouped.keys.sorted().map { n in
            let list = grouped[n]!
            return PhotoScene(id: n, photos: list.map(\.id), start: list.first?.captureDate)
        }
    }

    /// Distance between two photos' prints (for tuning and tests).
    public func distance(_ a: Photo, _ b: Photo) async -> Float? {
        guard let x = await observation(for: a), let y = await observation(for: b) else { return nil }
        var d: Float = 0
        return (try? x.computeDistance(&d, to: y)) != nil ? d : nil
    }

    private func observation(for photo: Photo) async -> VNFeaturePrintObservation? {
        let key = photo.id.path
        if let hit = observations[key] { return hit }
        if let data = try? await catalog.featurePrint(id: key, fileSize: photo.fileSize),
           let obs = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data) {
            observations[key] = obs
            return obs
        }
        guard let jpeg = try? await previews.preview(for: photo, size: .thumbnail),
              let data = await Task.detached(priority: .utility, operation: { SimilarityService.makePrint(jpeg) }).value,
              let obs = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
        else { return nil }
        try? await catalog.saveFeaturePrint(id: key, fileSize: photo.fileSize, data: data)
        observations[key] = obs
        return obs
    }

    /// Archived feature print of a JPEG, or nil if Vision fails.
    private nonisolated static func makePrint(_ jpeg: Data) -> Data? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(data: jpeg)
        guard (try? handler.perform([request])) != nil,
              let result = request.results?.first else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: result, requiringSecureCoding: true)
    }
}
