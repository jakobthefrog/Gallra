import SwiftUI
import GallraCore

/// Main window: tab bar, sidebar, and the selected tab's grid or viewer.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    var body: some View {
        VStack(spacing: 0) {
            TabBarView()
            GeometryReader { geo in
                HStack(spacing: 0) {
                    if model.sidebarVisible {
                        // 10% of the window, but never too narrow to read folder names.
                        SidebarView(width: max(140, geo.size.width * 0.10))
                        Theme.line.frame(width: 1)
                    }
                    if let tab = model.selectedTab {
                        TabContentView(tab: tab).id(tab.id)
                    }
                }
            }
        }
        .background(Theme.window)
        .preferredColorScheme(.dark)
        .frame(minWidth: 700, minHeight: 450)
        .sheet(isPresented: .init(get: { !hasSeenWelcome }, set: { hasSeenWelcome = !$0 })) {
            WelcomeView { hasSeenWelcome = true }
        }
    }
}

/// Toolbar + content + status bar for one tab, with keyboard handling.
struct TabContentView: View {
    let tab: FolderTab
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool
    @State private var confirmUnrated = false

    var body: some View {
        VStack(spacing: 0) {
            if tab.mode == .grid && tab.folder != nil { toolbar }
            ZStack {
                Theme.canvas
                content
            }
            .overlay(alignment: .bottom) { toast }
            statusBar
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(phases: [.down, .repeat], action: handleKey)
        .confirmationDialog("Move \(tab.unratedInView.count) unrated photos to \(FolderBrowser.rejectedFolderName)?",
                            isPresented: $confirmUnrated, titleVisibility: .visible) {
            Button("Move") { tab.rejectUnrated() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Files are moved, not deleted. Cmd+Z undoes it.")
        }
    }

    @ViewBuilder private var content: some View {
        if tab.folder == nil {
            message("Choose a folder from the sidebar, or press Cmd+O.")
        } else if let error = tab.errorMessage {
            message(error)
        } else if tab.isLoading && tab.photos.isEmpty {
            ProgressView().controlSize(.small)
        } else if tab.allPhotos.isEmpty {
            message("No supported photos in this folder.")
        } else if tab.photos.isEmpty {
            message("No photos match this filter.")
        } else if tab.mode == .compare, let compare = tab.compare {
            CompareView(tab: tab, state: compare)
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
            Picker("Filter", selection: $tab.filter) {
                ForEach(RatingFilter.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 380)
            Button("Move unrated (\(tab.unratedInView.count))…") { confirmUnrated = true }
                .disabled(tab.unratedInView.isEmpty)
                .controlSize(.small)
            Spacer()
            Image(systemName: "photo").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
            Slider(value: $tab.cellSize, in: 80...400).frame(width: 140).tint(Theme.accent)
                .accessibilityLabel("Thumbnail size")
            Image(systemName: "photo").font(.system(size: 16)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(Theme.raised)
    }

    /// Short message at the bottom of the content; has an Undo button after a move.
    @ViewBuilder private var toast: some View {
        if let notice = tab.notice {
            HStack(spacing: 12) {
                Text(notice).lineLimit(2)
                    .foregroundStyle(tab.noticeIsError ? Theme.reject : Theme.textPrimary)
                if tab.noticeUndoable {
                    Button("Undo") { model.undoLast() }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1) }
            .padding(.bottom, 16)
            .transition(.opacity)
        }
    }

    private var statusBar: some View {
        HStack {
            Text(tab.folder == nil ? "" : "\(countText) · \(tab.folder?.path ?? "")")
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            if let (done, total) = tab.groupProgress { Text("Grouping \(done)/\(total)…") }
        }
        .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 12).frame(height: 24)
        .background(Theme.window)
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }

    private var countText: String {
        tab.filter == .all ? "\(tab.photos.count) photos" : "\(tab.photos.count) of \(tab.allPhotos.count) photos"
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers == .command, press.characters.lowercased() == "z" {
            model.undoLast(); return .handled
        }
        guard !press.modifiers.contains(.command) else { return .ignored }
        let viewer = tab.mode == .viewer
        if tab.mode == .compare { return handleCompareKey(press) }
        if press.modifiers == .shift, press.key == .leftArrow || press.key == .rightArrow, !viewer {
            tab.extendMark(by: press.key == .leftArrow ? -1 : 1); return .handled
        }
        switch press.key {
        case .leftArrow: tab.move(by: -1)
        case .rightArrow: tab.move(by: 1)
        case .upArrow: viewer ? tab.move(by: -1) : tab.moveVertically(-1)
        case .downArrow: viewer ? tab.move(by: 1) : tab.moveVertically(1)
        case .space, .return: viewer ? () : tab.openViewer()
        case .escape: if viewer { tab.closeViewer() } else { return .ignored }
        default:
            switch press.characters.lowercased() {
            case "z" where viewer: tab.zoom100.toggle()
            case "f" where viewer: tab.showFilmstrip.toggle()
            case "0", "1", "2", "3": tab.setRating(Int(press.characters)!)
            case "x": tab.rejectCurrent()
            case "c": tab.openCompare()
            case "g": tab.grouping.toggle()
            default: return .ignored
            }
        }
        return .handled
    }

    private func handleCompareKey(_ press: KeyPress) -> KeyPress.Result {
        guard let compare = tab.compare else { return .ignored }
        if press.key == .escape { tab.closeCompare(); return .handled }
        if press.key == .tab { compare.active = 1 - compare.active; return .handled }
        switch press.characters.lowercased() {
        case "z": compare.toggleActualSize(backingScale: NSScreen.main?.backingScaleFactor ?? 2)
        case "0", "1", "2", "3": tab.setRating(Int(press.characters)!)
        case "x": tab.rejectCurrent()
        default: return .ignored
        }
        return .handled
    }
}
