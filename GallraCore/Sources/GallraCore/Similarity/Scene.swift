import Foundation

/// A run of similar photos taken close together in time. Photos are in time order.
public struct PhotoScene: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let photos: [PhotoID]
    /// Capture time of the first photo, if known.
    public let start: Date?
    /// Set for groups the user made by hand; nil for groups found automatically.
    public let manualID: String?

    public init(id: Int, photos: [PhotoID], start: Date?, manualID: String? = nil) {
        self.id = id
        self.photos = photos
        self.start = start
        self.manualID = manualID
    }
}

/// How strictly photos are grouped. The defaults are conservative: only clearly-the-same scenes.
public struct SceneSettings: Sendable, Equatable {
    /// A longer pause between two shots starts a new scene. Secondary check: how the shots look is what matters most.
    public var maxGap: TimeInterval
    /// Vision feature-print distance above which two neighbouring shots are different scenes.
    public var maxDistance: Float

    public init(maxGap: TimeInterval = 180, maxDistance: Float = 0.5) {
        self.maxGap = maxGap
        self.maxDistance = maxDistance
    }
}

/// Splits photos (already in time order) into scenes. Pure logic, no Vision or files.
public enum SceneClusterer {
    /// Returns the scene number (0, 1, 2...) of each item.
    /// `distance(i, j)` is the visual distance between items, or nil if unknown (then: new scene).
    public static func cluster(times: [Date?], settings: SceneSettings = SceneSettings(),
                               distance: (Int, Int) -> Float?) -> [Int] {
        var result: [Int] = []
        var scene = 0
        for i in times.indices {
            if i > 0 {
                var split = false
                if let a = times[i - 1], let b = times[i], b.timeIntervalSince(a) > settings.maxGap { split = true }
                if !split {
                    if let d = distance(i - 1, i) { split = d > settings.maxDistance } else { split = true }
                }
                if split { scene += 1 }
            }
            result.append(scene)
        }
        return result
    }
}
