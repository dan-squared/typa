import SwiftUI
import Combine
#if canImport(Sparkle)
import Sparkle
#endif

final class UpdaterViewModel: ObservableObject {
    #if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController

    var updater: SPUUpdater {
        updaterController.updater
    }
    #endif

    init() {
        #if canImport(Sparkle)
        // Initializes Sparkle's standard updater controller when the dependency is available.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif
    }

    func checkForUpdates() {
        #if canImport(Sparkle)
        updaterController.checkForUpdates(nil)
        #endif
    }
}
