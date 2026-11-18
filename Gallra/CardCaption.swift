import SwiftUI
import GallraCore

/// Remembers camera info already read, so scrolling back doesn't re-read files.
@MainActor enum CameraInfoCache {
    static var values: [String: CameraInfo] = [:]
}

/// Small card under a thumbnail: file name, then date, time, shutter, aperture, ISO and focal length, one per row.
struct CardCaption: View {
    let photo: Photo
    let width: Double
    @State private var info: CameraInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(photo.fileName).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
            ForEach(Array(details.enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .frame(width: width, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 4))
        .task(id: photo.id) {
            let path = photo.id.path
            if let hit = CameraInfoCache.values[path] { info = hit; return }
            let url = photo.url
            let read = await Task.detached { PhotoMetadataReader().cameraInfo(url) }.value
            CameraInfoCache.values[path] = read
            info = read
        }
    }

    /// ["2026-11-13", "14:32", "1/200", "f/2.8", "ISO 400", "85 mm"], with a dash for anything missing or not read yet.
    private var details: [String] {
        let info = info ?? CameraInfo()
        return [ShotDetails.date(photo), ShotDetails.time(photo), ShotDetails.shutter(info),
                ShotDetails.aperture(info), ShotDetails.iso(info), ShotDetails.focalLength(info)].map { $0 ?? "–" }
    }
}
