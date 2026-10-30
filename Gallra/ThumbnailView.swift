import SwiftUI
import GallraCore

/// One grid cell: a thumbnail on a placeholder, with filename on hover or selection.
struct ThumbnailView: View {
    let photo: Photo
    let size: Double
    let isSelected: Bool
    var isMarked = false
    @Environment(AppModel.self) private var model
    @State private var image: NSImage?
    @State private var failed = false
    @State private var hovering = false

    var body: some View {
        ZStack {
            Theme.raised.opacity(image == nil ? 1 : 0)
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if failed {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.textSecondary)
                    Text(photo.fileName).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }.padding(4)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottom) {
            if hovering || isSelected {
                Text(photo.fileName)
                    .font(.system(size: 11)).foregroundStyle(.white).lineLimit(1)
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            }
        }
        .overlay(alignment: .topLeading) {
            if let stars = photo.rating, stars > 0, size >= 80 {
                Text(String(repeating: "★", count: stars))
                    .font(.system(size: 11)).foregroundStyle(.yellow)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
                    .padding(4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay { if isSelected || isMarked { RoundedRectangle(cornerRadius: 4).stroke(Theme.accent, lineWidth: isSelected ? 2 : 1).opacity(isSelected ? 1 : 0.7) } }
        .overlay(alignment: .topTrailing) { if isMarked { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).padding(4) } }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .task(id: photo.id) {
            if let hit = model.images.cached(photo, size: .thumbnail) { image = hit; return }
            image = await model.images.image(photo, size: .thumbnail)
            failed = image == nil
        }
        .accessibilityLabel(photo.fileName)
    }
}
