import SwiftUI

/// What the update window is showing right now. Each case carries the callbacks Sparkle needs.
enum UpdatePhase {
    case checking(cancel: () -> Void)
    case found(version: String, notes: String?, reply: (UpdateChoice) -> Void)
    case message(title: String, detail: String, done: () -> Void)
    case downloading(progress: Double?, cancel: () -> Void)
    case extracting(progress: Double)
    case ready(reply: (UpdateChoice) -> Void)
    case installing
}

/// The user's answer to "update available" (kept free of Sparkle types so views stay simple).
enum UpdateChoice { case install, later, skip }

/// Holds the current phase; the view redraws when it changes.
@MainActor @Observable
final class UpdateModel {
    var phase: UpdatePhase = .installing
    /// Called when the user closes the window with the red button.
    var closed: () -> Void = {}
}

/// Update window content. For a new version it shows Lille Preben shouting the good news.
struct UpdateView: View {
    let model: UpdateModel
    private var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }

    var body: some View {
        Group {
            if case let .found(version, notes, reply) = model.phase {
                found(version: version, notes: notes, reply: reply)
            } else {
                plain
            }
        }
        .background(Theme.window)
        .foregroundStyle(Theme.textPrimary)
    }

    private func found(version: String, notes: String?, reply: @escaping (UpdateChoice) -> Void) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                VStack(spacing: 2) {
                    Text("“Hurrää, Hurrää!”").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.onAccent)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottom) { Bubble().fill(Theme.textPrimary).frame(width: 16, height: 8).offset(y: 8) }
                Text("— Lille Preben").font(.caption).foregroundStyle(Theme.textSecondary).padding(.top, 6)
                Image("LillePreben").resizable().scaledToFit().frame(width: 150)
            }
            .padding(.top, 16)
            .frame(width: 190)
            .frame(maxHeight: .infinity)
            .background(Theme.canvas.ignoresSafeArea())
            .overlay(alignment: .trailing) { Theme.line.frame(width: 1) }

            VStack(alignment: .leading, spacing: 6) {
                Text("A new version of Gallra is available!").font(.title3.bold())
                Text("Gallra \(version) is now available — you have \(current).").foregroundStyle(Theme.textSecondary)
                if let notes, !notes.isEmpty {
                    ScrollView { Text(notes).font(.callout).frame(maxWidth: .infinity, alignment: .leading) }
                        .padding(10).frame(maxHeight: 90)
                        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
                        .foregroundStyle(Theme.textSecondary).padding(.top, 4)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Spacer()
                    button("Skip This Version") { reply(.skip) }
                    button("Remind Me Later") { reply(.later) }
                    button("Install Update", primary: true) { reply(.install) }
                }
            }
            .padding(24)
        }
        .frame(width: 580, height: 300)
    }

    private var plain: some View {
        VStack(spacing: 14) {
            switch model.phase {
            case let .checking(cancel):
                ProgressView().controlSize(.small)
                Text("Checking for updates…")
                button("Cancel", action: cancel)
            case let .message(title, detail, done):
                Text(title).font(.headline)
                Text(detail).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                button("OK", primary: true, action: done)
            case let .downloading(progress, cancel):
                Text("Downloading update…")
                if let progress { ProgressView(value: progress).tint(Theme.accent) } else { ProgressView().controlSize(.small) }
                button("Cancel", action: cancel)
            case let .extracting(progress):
                Text("Preparing update…")
                ProgressView(value: progress).tint(Theme.accent)
            case let .ready(reply):
                Text("Ready to install").font(.headline)
                HStack {
                    button("Later") { reply(.later) }
                    button("Install and Relaunch", primary: true) { reply(.install) }
                }
            case .installing:
                ProgressView().controlSize(.small)
                Text("Installing update…")
            case .found:
                EmptyView()
            }
        }
        .padding(24).frame(width: 360)
    }

    private func button(_ title: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).fontWeight(primary ? .semibold : .regular).lineLimit(1).fixedSize()
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(primary ? Theme.accent : Theme.raised, in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(primary ? Theme.onAccent : Theme.textPrimary)
        }
        .buttonStyle(.plain)
    }
}

/// Little downward triangle that makes the rounded box look like a speech bubble.
private struct Bubble: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath()
        return p
    }
}
