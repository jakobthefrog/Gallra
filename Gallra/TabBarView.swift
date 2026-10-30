import SwiftUI

/// Row of folder tabs with a close button each and a "+" button.
struct TabBarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(model.tabs) { tab in TabItem(tab: tab) }
                }
            }
            Button { model.newTab() } label: { Image(systemName: "plus").frame(width: 28, height: 28) }
                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                .accessibilityLabel("New tab")
            Spacer(minLength: 0)
        }
        .frame(height: 30)
        .background(Theme.canvas)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }
}

private struct TabItem: View {
    let tab: FolderTab
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    private var active: Bool { model.selectedTabID == tab.id }

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.title).font(.system(size: 12)).lineLimit(1)
                .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
            Button { model.closeTab(tab.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                .opacity(active || hovering ? 1 : 0)
                .accessibilityLabel("Close tab")
        }
        .padding(.horizontal, 12).frame(minWidth: 100, maxWidth: 200, minHeight: 30)
        .background(active ? Theme.window : (hovering ? Theme.hover : .clear))
        .overlay(alignment: .top) { if active { Theme.accent.frame(height: 2) } }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.selectedTabID = tab.id }
    }
}
