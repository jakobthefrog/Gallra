import SwiftUI

/// One-screen introduction shown the first time Gallra opens.
struct WelcomeView: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Gallra").font(.system(size: 20, weight: .semibold))
            Text("Fast photo culling for Canon CR3 and Hasselblad 3FR files.")
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 8) {
                line("Pick a folder in the sidebar. Arrows move, Space opens the viewer, Esc goes back.")
                line("Press 1, 2 or 3 to rate a photo (0 clears). The rating is written into the RAW file.")
                line("Press Backspace to move a photo to a \"Gallra Rejected\" folder next to it. Nothing is deleted; Cmd+Z undoes it.")
                line("Gallra changes your files in only those two ways.")
            }
            Text("Gallra is not notarized by Apple. If macOS blocks a new version, allow it under System Settings → Privacy & Security → Open Anyway.")
                .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            HStack { Spacer(); Button("Get started", action: dismiss).keyboardShortcut(.defaultAction) }
        }
        .font(.system(size: 13))
        .padding(24).frame(width: 460)
        .background(Theme.window)
        .preferredColorScheme(.dark)
    }

    private func line(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) { Text("•"); Text(text) }
    }
}
