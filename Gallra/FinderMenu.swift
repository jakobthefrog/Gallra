import SwiftUI
import GallraCore

/// Right-click items that open a photo or folder in Finder.
/// Use `photo` for a photo, `folder` for a folder; pass both to offer both.
struct FinderMenu: View {
    var photo: String?
    var folder: String?

    var body: some View {
        if let photo { Button("Show Photo in Finder") { FinderReveal.reveal(path: photo) } }
        if let folder { Button("Show Folder in Finder") { FinderReveal.reveal(path: folder) } }
    }
}
