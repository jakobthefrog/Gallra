import SwiftUI
import Sparkle

/// Wraps Sparkle's standard updater: checks for new versions in the background and on demand.
@MainActor
final class Updater {
    private let controller = SPUStandardUpdaterController(startingUpdater: true,
                                                          updaterDelegate: nil, userDriverDelegate: nil)

    func checkForUpdates() { controller.checkForUpdates(nil) }
}
