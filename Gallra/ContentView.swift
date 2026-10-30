import SwiftUI
import GallraCore

/// Main window: tab bar, sidebar, and the selected tab's grid or viewer.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            TabBarView()
            HStack(spacing: 0) {
                if model.sidebarVisible {
                    SidebarView()
                    Theme.line.frame(width: 1)
                }
                if let tab = model.selectedTab {
                    TabContentView(tab: tab).id(tab.id)
                }
            }
        }
        .background(Theme.window)
        .preferredColorScheme(.dark)
        .frame(minWidth: 700, minHeight: 450)
    }
}

/// Toolbar + content + status bar for one tab, with keyboard handling.
struct TabContentView: View {
    let tab: FolderTab
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if tab.mode == .grid && tab.folder != nil { toolbar }
            ZStack {
                Theme.canvas
                content
            }
            statusBar
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(phases: [.down, .repeat], action: handleKey)
    }

    @ViewBuilder private var content: some View {
        if tab.folder == nil {
            message("Choose a folder from the sidebar, or press Cmd+O.")
        } else if let error = tab.errorMessage {
            message(error)
        } else if tab.isLoading && tab.photos.isEmpty {
            ProgressView().controlSize(.small)
        } else if tab.photos.isEmpty {
            message("No supported photos in this folder.")
        } else if tab.mode == .viewer {
            ViewerView(tab: tab)
        } else {
            GridView(tab: tab)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
    }

    private var toolbar: some View {
        @Bindable var tab = tab
        return HStack(spacing: 8) {
            Spacer()
            Image(systemName: "photo").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
            Slider(value: $tab.cellSize, in: 80...400).frame(width: 140).tint(Theme.accent)
                .accessibilityLabel("Thumbnail size")
            Image(systemName: "photo").font(.system(size: 16)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(Theme.raised)
    }

    private var statusBar: some View {
        HStack {
            Text(tab.folder == nil ? "" : "\(tab.photos.count) photos · \(tab.folder?.path ?? "")")
                .lineLimit(1).truncationMode(.middle)
            Spacer()
        }
        .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 12).frame(height: 24)
        .background(Theme.window)
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !press.modifiers.contains(.command) else { return .ignored }
        let viewer = tab.mode == .viewer
        switch press.key {
        case .leftArrow: tab.move(by: -1)
        case .rightArrow: tab.move(by: 1)
        case .upArrow: viewer ? tab.move(by: -1) : tab.move(by: -tab.columns)
        case .downArrow: viewer ? tab.move(by: 1) : tab.move(by: tab.columns)
        case .space, .return: viewer ? () : tab.openViewer()
        case .escape: if viewer { tab.closeViewer() } else { return .ignored }
        default:
            switch press.characters.lowercased() {
            case "z" where viewer: tab.zoom100.toggle()
            case "f" where viewer: tab.showFilmstrip.toggle()
            default: return .ignored
            }
        }
        return .handled
    }
}
