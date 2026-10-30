import SwiftUI
import AppKit

/// The Gallra > Settings window: shortcuts to the macOS privacy pages, and browsing defaults.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Permissions") {
                Text("Gallra needs access to the folders your photos are in. macOS keeps these switches, so they open in System Settings.")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("Choose which folders Gallra can read") {
                    Button("Open Files and Folders…") { open("Privacy_FilesAndFolders") }
                }
                LabeledContent("Give access to everything, no per-folder prompts") {
                    Button("Open Full Disk Access…") { open("Privacy_AllFiles") }
                }
            }
            Section("Browsing") {
                Text("Defaults for folders that contain sub folders.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Include sub folders", isOn: $model.includeSubfolders)
                Picker("Layout", selection: $model.layoutByFolder) {
                    Text("Flat").tag(false)
                    Text("By folder").tag(true)
                }
                .pickerStyle(.segmented).fixedSize()
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Opens a pane of System Settings > Privacy & Security.
    private func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
