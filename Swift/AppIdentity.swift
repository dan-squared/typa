import Foundation

enum AppIdentity {
    static let displayName = "Typa"
    static let bundleIdentifier = "app.Typa"
    static let onboardingLaunchKey = "app.typa.hasLaunchedBefore"
    static let debugResetEnvironmentKey = "TYPA_RESET_DEBUG_STATE"
    static let debugResetDefaultsKey = "app.typa.resetDebugStateOnLaunch"
    static let historyDirectoryName = "Typa-History"
    static let settingsQueueLabel = "Typa.SettingsPersistence"
}
