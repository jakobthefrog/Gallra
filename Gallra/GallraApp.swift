import SwiftUI

/// App entry point.
@main
struct GallraApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView().environment(model)
        }
        .commands {
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
    }
}
