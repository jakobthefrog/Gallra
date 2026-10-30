import SwiftUI
import GallraCore

/// Remembers camera info already read, so scrolling back doesn't re-read files.
@MainActor private enum CameraInfoCache {
    static var values: [String: CameraInfo] = [:]
}

/// Small card under a thumbnail: file name, then shutter, ISO, aperture and focal length.
struct CardCaption: View {
    let photo: Photo
    let width: Double
    @State private var info: CameraInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(photo.fileName).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
            Text(details).font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.textSecondary).lineLimit(1)
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

    /// "1/200 · ISO 400 · f/2.8 · 85 mm", with a dash for anything missing or not read yet.
    private var details: String {
        guard let info else { return "–" }
        let shutter = info.shutter.map { $0 >= 1 ? "\(Self.number($0)) s" : "1/\(Int((1 / max($0, 0.000001)).rounded()))" }
        return [shutter ?? "–",
                info.iso.map { "ISO \($0)" } ?? "–",
                info.aperture.map { "f/" + Self.number($0) } ?? "–",
                info.focalLength.map { "\(Int($0.rounded())) mm" } ?? "–"].joined(separator: " · ")
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}
