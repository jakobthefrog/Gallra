import Foundation

/// Which photos the grid shows, by star rating. A missing rating field counts as no stars.
public enum RatingFilter: String, CaseIterable, Codable, Sendable {
    case all, oneStar, twoStars, threeStars, unrated, anyStars

    public func matches(_ photo: Photo) -> Bool {
        let stars = photo.rating ?? 0
        switch self {
        case .all: return true
        case .oneStar: return stars == 1
        case .twoStars: return stars == 2
        case .threeStars: return stars == 3
        case .unrated: return stars == 0
        case .anyStars: return stars > 0
        }
    }

    public func apply(to photos: [Photo]) -> [Photo] { photos.filter(matches) }

    public var label: String {
        switch self {
        case .all: "All"
        case .oneStar: "1★"
        case .twoStars: "2★"
        case .threeStars: "3★"
        case .unrated: "No stars"
        case .anyStars: "Any stars"
        }
    }
}
