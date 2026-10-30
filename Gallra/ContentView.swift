import SwiftUI
import GallraCore

/// Placeholder view proving the app can call into `GallraCore`.
struct ContentView: View {
    var body: some View {
        Text(GallraCore.greeting)
            .padding(40)
    }
}
