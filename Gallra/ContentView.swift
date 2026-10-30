import SwiftUI
import GallraCore

/// Main window: tab bar, sidebar, and the selected tab's grid or viewer.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("sidebarWidth") private var sidebarWidth = 260.0

    var body: some View {
        VStack(spacing: 0) {
            Theme.line.frame(height: 1)   // divider under the tab row
            GeometryReader { geo in
                HStack(spacing: 0) {
                    if model.sidebarVisible {
                        SidebarView(width: min(max(sidebarWidth, 160), max(160, geo.size.width * 0.5)))
                        Theme.line.frame(width: 1)
                            .overlay(SidebarResizeHandle(width: $sidebarWidth))
                    }
                    if let tab = model.selectedTab {
                        TabContentView(tab: tab).id(tab.id)
                    }
                }
            }
        }
        .background(Theme.window)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .frame(minWidth: 700, minHeight: 450)
        .toolbar {
            TabsToolbarItem()
        }
        .toolbarBackground(Theme.canvas, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
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
    @State private var showCameraFilters = false
    @AppStorage("showCardDetails") private var showCardDetails = false

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
            HStack(spacing: 0) {
                ForEach(RatingFilter.allCases, id: \.self) { option in
                    let on = tab.filter == option
                    Text(option.label).font(.system(size: 11)).padding(.horizontal, 8).frame(height: 20)
                        .foregroundStyle(on ? Theme.onAccent : Theme.textSecondary)
                        .background(on ? Theme.accent : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture { tab.filter = option }
                        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1) }
            Button("Group") { tab.grouping.toggle() }
                .controlSize(.small)
                .tint(tab.grouping ? Theme.accent : nil)
                .buttonStyle(.bordered)
                .help("Group similar photos into scenes (G)")
                .accessibilityAddTraits(tab.grouping ? .isSelected : [])
            Button(tab.cameraFilter.isActive ? "Filters (\(tab.cameraFilter.activeCount))" : "Filters") { showCameraFilters.toggle() }
                .controlSize(.small)
                .popover(isPresented: $showCameraFilters, arrowEdge: .bottom) { CameraFilterPanel(tab: tab) }
            Button("Move unrated (\(tab.unratedInView.count))…") { confirmUnrated = true }
                .disabled(tab.unratedInView.isEmpty)
                .controlSize(.small)
            Spacer()
            Picker("Thumbnail view", selection: $showCardDetails) {
                Image(systemName: "square.grid.2x2").tag(false).help("Thumbnails only")
                Image(systemName: "rectangle.grid.1x2").tag(true).help("Cards with file name and camera settings")
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 70).controlSize(.small)
            .accessibilityLabel("Thumbnail view")
            Image(systemName: "photo").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
            Slider(value: $tab.cellSize, in: 80...400).frame(width: 140).tint(Theme.accent)
                .accessibilityLabel("Thumbnail size")
            Image(systemName: "photo").font(.system(size: 16)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 8).frame(height: 30)
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
            if let photo = tab.currentPhoto {
                Text(([photo.fileName, tab.cameraInfo.summary].filter { !$0.isEmpty }).joined(separator: " · "))
                    .lineLimit(1).truncationMode(.tail)
            }
        }
        .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 12).frame(height: 22)
        .background(Theme.window)
        .overlay(alignment: .top) { Theme.line.frame(height: 1) }
    }

    private var countText: String {
        tab.filter == .all && !tab.cameraFilter.isActive ? "\(tab.photos.count) photos" : "\(tab.photos.count) of \(tab.allPhotos.count) photos"
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
        case .delete, .deleteForward: tab.rejectCurrent()
        default:
            switch press.characters.lowercased() {
            case "z" where viewer: tab.zoom100.toggle()
            case "f" where viewer: tab.showFilmstrip.toggle()
            case "0", "1", "2", "3": tab.setRating(Int(press.characters)!)
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
        if press.key == .delete || press.key == .deleteForward { tab.rejectCurrent(); return .handled }
        switch press.characters.lowercased() {
        case "z": compare.toggleActualSize(backingScale: NSScreen.main?.backingScaleFactor ?? 2)
        case "0", "1", "2", "3": tab.setRating(Int(press.characters)!)
        default: return .ignored
        }
        return .handled
    }
}

/// The tab bar as a window-toolbar item, without the rounded pill newer macOS draws around items.
private struct TabsToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .navigation) { tabs }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { tabs }
        }
    }

    private var tabs: some View { TabBarView().frame(minWidth: 300, maxWidth: .infinity) }
}

/// Thin invisible strip on the sidebar edge; drag to resize.
private struct SidebarResizeHandle: View {
    @Binding var width: Double
    @State private var startWidth: Double?

    var body: some View {
        Color.clear.frame(width: 9).contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    let start = startWidth ?? width
                    startWidth = start
                    width = min(max(start + drag.translation.width, 160), 600)
                }
                .onEnded { _ in startWidth = nil })
    }
}
