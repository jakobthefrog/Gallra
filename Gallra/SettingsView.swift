import SwiftUI
import AppKit

/// The Gallra > Settings window: shortcuts to the macOS privacy pages, and browsing defaults.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showCameraInfo") private var showCameraInfo = true
    @State private var cacheBytes: Int64?
    @State private var confirmClear = false

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
            Section("Viewer") {
                Toggle("Show camera settings (press I in the viewer)", isOn: $showCameraInfo)
            }
            Section("Cache") {
                Text("Previews and photo details Gallra saved to open folders faster. They are rebuilt as you browse. Your photos, ratings, favorites and hand-made groups are not touched.")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("Cache size") {
                    HStack {
                        Text(cacheBytes.map { $0.formatted(.byteCount(style: .file)) } ?? "Calculating…")
                            .foregroundStyle(.secondary)
                        Button("Clear cache…") { confirmClear = true }
                    }
                }
            }
        }
        .task { cacheBytes = await model.cacheBytes() }
        .confirmationDialog("Clear the cache?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear cache") {
                Task { await model.clearCache(); cacheBytes = await model.cacheBytes() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Folders will open more slowly once while Gallra rebuilds it. Your photos are not touched.")
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
