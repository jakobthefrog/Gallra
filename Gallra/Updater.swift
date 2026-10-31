import AppKit
import SwiftUI
import Sparkle

/// Wraps Sparkle: checks for new versions in the background and on demand,
/// and shows our own update window (with Lille Preben) instead of Sparkle's standard one.
@MainActor
final class Updater {
    private let driver = UpdateWindowDriver()
    private lazy var controller = SPUUpdater(hostBundle: .main, applicationBundle: .main,
                                             userDriver: driver, delegate: nil)

    init() { try? controller.start() }

    func checkForUpdates() { controller.checkForUpdates() }
}

/// Sparkle "user driver": Sparkle does the work, this class only decides what the user sees.
@MainActor
final class UpdateWindowDriver: NSObject, SPUUserDriver, NSWindowDelegate {
    private let model = UpdateModel()
    private var window: NSWindow?

    private func show(_ phase: UpdatePhase) {
        model.phase = phase
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: UpdateView(model: model)))
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        window?.sizeToFit()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowWillClose(_ notification: Notification) { model.closed() }

    // MARK: SPUUserDriver

    func show(_ request: SPUUpdatePermissionRequest) async -> SUUpdatePermissionResponse {
        SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        model.closed = cancellation
        show(.checking(cancel: { cancellation() }))
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState) async -> SPUUserUpdateChoice {
        await withCheckedContinuation { continuation in
            var answered = false
            let answer: (SPUUserUpdateChoice) -> Void = { [weak self] choice in
                guard !answered else { return }
                answered = true
                self?.model.closed = {}
                continuation.resume(returning: choice)
            }
            model.closed = { answer(.dismiss) }
            let notes = appcastItem.itemDescription.flatMap {
                NSAttributedString(html: Data($0.utf8), documentAttributes: nil)?.string
            }
            show(.found(version: appcastItem.displayVersionString, notes: notes, reply: { choice in
                switch choice {
                case .install: answer(.install)
                case .later: answer(.dismiss)
                case .skip: answer(.skip)
                }
            }))
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        message("You're up to date!", "Gallra is the newest version.", acknowledgement)
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        message("Update error", error.localizedDescription, acknowledgement)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        total = 0; received = 0
        model.closed = cancellation
        show(.downloading(progress: nil, cancel: { cancellation() }))
    }

    private var total: UInt64 = 0
    private var received: UInt64 = 0

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { total = expectedContentLength }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        received += length
        guard total > 0, case let .downloading(_, cancel) = model.phase else { return }
        model.phase = .downloading(progress: min(1, Double(received) / Double(total)), cancel: cancel)
    }

    func showDownloadDidStartExtractingUpdate() { show(.extracting(progress: 0)) }
    func showExtractionReceivedProgress(_ progress: Double) { model.phase = .extracting(progress: progress) }

    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        await withCheckedContinuation { continuation in
            show(.ready(reply: { choice in
                continuation.resume(returning: choice == .install ? .install : .dismiss)
            }))
        }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        show(.installing)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() { window?.makeKeyAndOrderFront(nil) }

    func dismissUpdateInstallation() {
        model.closed = {}
        window?.close()
        window = nil
    }

    private func message(_ title: String, _ detail: String, _ done: @escaping () -> Void) {
        model.closed = done
        show(.message(title: title, detail: detail, done: { done() }))
    }
}

private extension NSWindow {
    func sizeToFit() { if let size = contentViewController?.view.fittingSize, size.width > 0 { setContentSize(size) } }
}
