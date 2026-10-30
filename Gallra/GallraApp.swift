import SwiftUI

/// App entry point.
@main
struct GallraApp: App {
    @State private var model = AppModel()
    @State private var updater = Updater()

    var body: some Scene {
        WindowGroup {
            ContentView().environment(model)
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))   // tabs share the row with the window buttons
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { model.newTab() }.keyboardShortcut("t")
                Button("Close Tab") { if let id = model.selectedTabID { model.closeTab(id) } }.keyboardShortcut("w")
                Button("Open Folder…") { model.chooseFolder(inNewTab: false) }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .sidebar) {
                Button(model.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") { model.sidebarVisible.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }
        Settings {
            SettingsView().environment(model)
        }
    }
}
