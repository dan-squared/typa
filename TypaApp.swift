import SwiftUI
import SwiftData

@main
struct TypaApp: App {
    enum WindowMetrics {
        static let onboardingDefaultWidth: CGFloat = 520
        static let onboardingDefaultHeight: CGFloat = 620
        static let onboardingMinimumWidth: CGFloat = 520
        static let onboardingMinimumHeight: CGFloat = 620
        static let primaryDefaultWidth: CGFloat = 860
        static let primaryDefaultHeight: CGFloat = 620
        static let primaryMinimumWidth: CGFloat = 860
        static let primaryMinimumHeight: CGFloat = 620
        static let settingsDefaultWidth: CGFloat = 760
        static let settingsDefaultHeight: CGFloat = 700
    }

    @State private var appState: AppState
    @StateObject private var updaterViewModel = UpdaterViewModel()
    private let sharedModelContainer: ModelContainer

    init() {
        // Disable macOS window restoration so the app always opens
        // to the typing practice interface regardless of which windows
        // were visible when the user last quit.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        #if os(macOS)
        NSWindow.allowsAutomaticWindowTabbing = false
        #endif

        #if DEBUG
        DevelopmentLaunchReset.performOnceBeforeBootstrap()
        #endif

        let initialAppState = AppState()
        let bootstrap = Self.makeHistoryStoreBootstrap()
        if let notice = bootstrap.notice {
            initialAppState.historyStoreNotice = notice
        }

        _appState = State(initialValue: initialAppState)
        sharedModelContainer = bootstrap.container
    }

    var body: some Scene {
        Window(AppIdentity.displayName, id: "primary") {
            AppSceneRoot(appState: appState) {
                PrimaryWindowRootView(appState: appState)
                    .withDesignSystem()
            }
            .preferredColorScheme(appState.theme.colorScheme())
            .containerBackground(.clear, for: .window)
        }
        .defaultSize(
            width: WindowMetrics.primaryDefaultWidth,
            height: WindowMetrics.primaryDefaultHeight
        )
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterViewModel.checkForUpdates()
                }
            }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandMenu("Type Test") {
                Button("New Practice") {
                    appState.shouldRestart = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Restart") {
                    appState.shouldRestart = true
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Window("Profile", id: "history") {
            AppSceneRoot(appState: appState) {
                ProfileWindowRootView(appState: appState)
                    .withDesignSystem()
            }
            .preferredColorScheme(appState.theme.colorScheme())
            .modelContainer(sharedModelContainer)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            AppSceneRoot(appState: appState) {
                SettingsView(appState: appState)
                    .withDesignSystem()
            }
            .preferredColorScheme(appState.theme.colorScheme())
            .modelContainer(sharedModelContainer)
        }
        .defaultSize(
            width: WindowMetrics.settingsDefaultWidth,
            height: WindowMetrics.settingsDefaultHeight
        )
        .restorationBehavior(.disabled)
    }
}

private extension TypaApp {
    struct HistoryStoreBootstrap {
        var container: ModelContainer
        var notice: AppInfrastructureNotice?
    }

    static func applicationSupportHistoryStoreURL() throws -> URL {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? AppIdentity.bundleIdentifier
        let directoryURL = appSupportURL.appendingPathComponent(bundleID, isDirectory: true)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("TypingHistory.store")
    }

    static func temporaryHistoryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(AppIdentity.historyDirectoryName, isDirectory: true)
            .appendingPathComponent("TypingHistory.store")
    }

    static func makeHistoryStoreBootstrap() -> HistoryStoreBootstrap {
        if let storeURL = try? applicationSupportHistoryStoreURL() {
            do {
                return HistoryStoreBootstrap(
                    container: try makePersistentHistoryContainer(storeURL: storeURL),
                    notice: nil
                )
            } catch {
                removeStoreFiles(at: storeURL)

                do {
                    return HistoryStoreBootstrap(
                        container: try makePersistentHistoryContainer(storeURL: storeURL),
                        notice: nil
                    )
                } catch {
                    return makeTemporaryOrInMemoryBootstrap(
                        notice: AppInfrastructureNotice(
                            source: .history,
                            kind: .warning,
                            title: "History Unavailable",
                            message: "Persistent history is unavailable. Falling back to temporary local storage for this launch."
                        )
                    )
                }
            }
        }

        return makeTemporaryOrInMemoryBootstrap(
            notice: AppInfrastructureNotice(
                source: .history,
                kind: .warning,
                title: "History Unavailable",
                message: "Application Support could not be prepared. Falling back to temporary local storage for this launch."
            )
        )
    }

    static func makeTemporaryOrInMemoryBootstrap(notice: AppInfrastructureNotice) -> HistoryStoreBootstrap {
        let storeURL = temporaryHistoryStoreURL()
        try? FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            return HistoryStoreBootstrap(
                container: try makePersistentHistoryContainer(storeURL: storeURL),
                notice: notice
            )
        } catch {
            removeStoreFiles(at: storeURL)

            do {
                return HistoryStoreBootstrap(
                    container: try makePersistentHistoryContainer(storeURL: storeURL),
                    notice: notice
                )
            } catch {
                do {
                    return HistoryStoreBootstrap(
                        container: try makeInMemoryHistoryContainer(),
                        notice: AppInfrastructureNotice(
                            source: .history,
                            kind: .error,
                            title: "History Unavailable",
                            message: "Persistent storage is unavailable. History will only be kept in memory for this launch."
                        )
                    )
                } catch {
                    return HistoryStoreBootstrap(
                        container: emergencyInMemoryHistoryContainer(),
                        notice: AppInfrastructureNotice(
                            source: .history,
                            kind: .error,
                            title: "Storage Unavailable",
                            message: "Local storage initialization failed repeatedly. Using an emergency in-memory store for this launch."
                        )
                    )
                }
            }
        }
    }

    static func makePersistentHistoryContainer(storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TypaSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(
            for: TypingResult.self,
            migrationPlan: TypaSchemaMigrationPlan.self,
            configurations: configuration
        )
    }

    static func makeInMemoryHistoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: TypaSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: TypingResult.self,
            migrationPlan: TypaSchemaMigrationPlan.self,
            configurations: configuration
        )
    }

    static func emergencyInMemoryHistoryContainer() -> ModelContainer {
        do {
            return try makeInMemoryHistoryContainer()
        } catch {
            fatalError("Emergency in-memory history container initialization failed: \(error.localizedDescription)")
        }
    }

    static func removeStoreFiles(at storeURL: URL) {
        let fileManager = FileManager.default
        let relatedURLs = [
            storeURL,
            storeURL.appendingPathExtension("shm"),
            storeURL.appendingPathExtension("wal")
        ]

        for url in relatedURLs where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}

#if DEBUG
private enum DevelopmentLaunchReset {
    private static var hasPerformedReset = false

    static func performOnceBeforeBootstrap() {
        guard !hasPerformedReset else { return }
        hasPerformedReset = true
        let storeURL = (try? TypaApp.applicationSupportHistoryStoreURL()) ?? TypaApp.temporaryHistoryStoreURL()
        performIfRequested(storeURL: storeURL)
    }

    static func performIfRequested(storeURL: URL) {
        guard shouldResetOnLaunch else { return }
        clearUserDefaults()
        removeStoreFiles(at: storeURL)
    }

    private static var shouldResetOnLaunch: Bool {
        if ProcessInfo.processInfo.environment[AppIdentity.debugResetEnvironmentKey] == "1" {
            return true
        }

        return UserDefaults.standard.bool(forKey: AppIdentity.debugResetDefaultsKey)
    }

    private static func clearUserDefaults() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
    }

    private static func removeStoreFiles(at storeURL: URL) {
        TypaApp.removeStoreFiles(at: storeURL)
        let fileManager = FileManager.default
        let relatedURLs = [storeURL, storeURL.appendingPathExtension("shm"), storeURL.appendingPathExtension("wal")]
        for url in relatedURLs where fileManager.fileExists(atPath: url.path) {
            assertionFailure("Failed to remove development store at \(url.path).")
        }
    }
}
#endif

private struct PrimaryWindowRootView: View {
    @Bindable var appState: AppState
    @AppStorage(AppIdentity.onboardingLaunchKey) private var hasLaunchedBefore = false
    @State private var hasCompletedOnboardingForSession = false

    private var showsOnboarding: Bool {
        !hasLaunchedBefore && !hasCompletedOnboardingForSession
    }

    private var windowChromePhase: WindowChromePhase {
        showsOnboarding ? .immersive : .standard
    }

    private var minimumWindowSize: CGSize {
        if showsOnboarding {
            return CGSize(
                width: TypaApp.WindowMetrics.onboardingMinimumWidth,
                height: TypaApp.WindowMetrics.onboardingMinimumHeight
            )
        }

        return CGSize(
            width: TypaApp.WindowMetrics.primaryMinimumWidth,
            height: TypaApp.WindowMetrics.primaryMinimumHeight
        )
    }

    var body: some View {
        ZStack {
            ContentView(appState: appState)
                .withDesignSystem()
                .opacity(showsOnboarding ? 0 : 1)
                .allowsHitTesting(!showsOnboarding)

            if showsOnboarding {
                OnboardingIntroView(
                    onWindowReveal: {},
                    onBeginFinish: {},
                    onFinish: {
                        hasCompletedOnboardingForSession = true
                        hasLaunchedBefore = true
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: showsOnboarding)
        .frame(minWidth: minimumWindowSize.width, minHeight: minimumWindowSize.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .background(
            WindowAccessor(
                phase: windowChromePhase,
                minimumWindowSize: NSSize(
                    width: minimumWindowSize.width,
                    height: minimumWindowSize.height
                )
            )
        )
        #if os(macOS)
        .onAppear {
            // Ensure the primary (typing practice) window is always the
            // frontmost key window on launch, even if macOS restored a
            // secondary window from a previous session.
            DispatchQueue.main.async {
                if let primaryWindow = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("primary") ?? false }) {
                    primaryWindow.makeKeyAndOrderFront(nil)
                } else {
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }
                NSApp.activate(ignoringOtherApps: false)
            }
        }
        #endif
    }
}

private struct ProfileWindowRootView: View {
    @Bindable var appState: AppState
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var hasValidatedPresentation = false

    var body: some View {
        Group {
            if hasValidatedPresentation {
                AdaptiveAnalysisView(appState: appState)
            } else {
                Color.clear
            }
        }
        .onAppear {
            validatePresentation()
        }
        .task {
            // Delayed re-check: if the window was restored by macOS before
            // onAppear could dismiss it, this catches it after the window
            // system has fully settled.
            guard !hasValidatedPresentation else { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, !hasValidatedPresentation else { return }
            validatePresentation()
        }
    }

    private func validatePresentation() {
        guard !hasValidatedPresentation else { return }

        guard appState.consumeProfileWindowOpenIntent() else {
            dismissWindow(id: "history")
            return
        }

        hasValidatedPresentation = true
    }
}

private struct AppSceneRoot<Content: View>: View {
    let appState: AppState
    @Environment(\.modelContext) private var modelContext
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .overlay(alignment: .topTrailing) {
                if let notice = appState.infrastructureNotice {
                    CompactInfrastructureNotice(notice: notice) {
                        appState.dismissInfrastructureNotice()
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                }
            }
            .task {
                appState.loadTrainingHistoryIfNeeded(from: modelContext.container)
            }
    }
}

private struct CompactInfrastructureNotice: View {
    @Environment(\.ds) private var ds
    let notice: AppInfrastructureNotice
    let onDismiss: () -> Void

    private var tint: Color {
        switch notice.kind {
        case .warning:
            return ds.warning
        case .error:
            return ds.error
        }
    }

    private var symbolName: String {
        switch notice.kind {
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(ds.primaryText)
                Text(notice.message)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ds.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 300, alignment: .leading)
        .background(SubtleMessageBackground(cornerRadius: CornerRadius.large))
        .shadow(color: ds.shadowColor.opacity(0.9), radius: 14, y: 8)
        .onTapGesture {
            onDismiss()
        }
    }
}
