import SwiftUI
import SwiftData

@Observable class AppState {
    private static let errorModeMigrationKey = "didMigrateErrorModeDefaultToOff"
    private static let caretColorMigrationKey = "didMigrateCaretColorDefaultToV2"
    @ObservationIgnored private let settingsPersistence: SettingsPersistence
    @ObservationIgnored private var pendingSettingsSaveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingTrainingRuntimeTask: Task<Void, Never>?
    @ObservationIgnored private var pendingHistoryLoadTask: Task<Void, Never>?
    @ObservationIgnored private var pendingHistoryLoadToken: UUID?
    @ObservationIgnored private var cachedTrainingHistory: [HistoryTransferSession] = []
    @ObservationIgnored private var trainingProgressStore = AdaptiveProgressStore()
    @ObservationIgnored private var lastTrainingHistoryInput: [HistoryTransferDeduplicationKey] = []
    @ObservationIgnored private var lastTrainingRuntimeConfiguration: TrainingRuntimeConfiguration?
    @ObservationIgnored private var hasPrimedTrainingRuntime = false
    @ObservationIgnored private var autoRaisedTargetGoalEventIDs: Set<String> = []
    var shouldRestart = false
    var isShowingResults = false
    var isTypingActive = false
    var practiceChangeTick = 0
    var isFocusMode = false
    var profileWindowOpenIntent = false
    var trainingRuntime = AdaptiveTrainingRuntimeSnapshot.empty
    var profileSnapshot = AdaptiveTrainingProfileSnapshot.empty
    var liveTrainingEvents: [TrainingProfileEvent] = []
    var trainingHistoryLoadState: TrainingHistoryLoadState = .idle
    var historyStoreNotice: AppInfrastructureNotice?
    var settingsLoadNotice: AppInfrastructureNotice?
    var settingsSaveFailureNotice: AppInfrastructureNotice?
    var resourceLoadNotice: AppInfrastructureNotice?
    
    var settings: AppSettings {
        didSet {
            scheduleSettingsSave()
            guard settings != oldValue,
                  shouldRefreshTrainingRuntime(from: oldValue, to: settings) else { return }
            refreshTrainingRuntimeFromCache()
        }
    }
    
    init() {
        let settingsPersistence = SettingsPersistence()
        let loadResult = settingsPersistence.load(defaults: .default)
        self.settingsPersistence = settingsPersistence
        self.settings = Self.normalizedSettings(loadResult.settings)
        self.settingsLoadNotice = loadResult.notice

        migrateLegacyErrorModeIfNeeded()
        migrateLegacyCaretDefaultsIfNeeded()

        WordCorpusCatalog.shared.prime()
        self.resourceLoadNotice = WordCorpusCatalog.shared.infrastructureNotice
    }
    
    func saveSettings() {
        persistSettingsImmediately()
    }

    func saveAndApplySettings() {
        saveSettings()
        shouldRestart = true
        practiceChangeTick += 1
    }

    func applySettings(_ newSettings: AppSettings) {
        let normalized = Self.normalizedSettings(newSettings)
        guard settings != normalized else { return }
        settings = normalized
        shouldRestart = true
        practiceChangeTick += 1
    }

    func syncTrainingHistory(from results: [TypingResult]) {
        syncTrainingHistory(from: results.map(HistoryTransferSession.init(result:)))
    }

    func syncTrainingHistory(from history: [HistoryTransferSession]) {
        let sortedHistory = history.sorted { $0.date < $1.date }
        let inputKey = sortedHistory.map(\.deduplicationKey)
        cachedTrainingHistory = sortedHistory
        refreshTrainingRuntime(using: sortedHistory, inputKey: inputKey)
    }

    func loadTrainingHistoryIfNeeded(from modelContainer: ModelContainer) {
        guard !hasPrimedTrainingRuntime,
              pendingHistoryLoadTask == nil else { return }
        reloadTrainingHistory(from: modelContainer)
    }

    func reloadTrainingHistory(from modelContainer: ModelContainer) {
        pendingHistoryLoadTask?.cancel()
        pendingHistoryLoadTask = nil
        let loadToken = UUID()
        pendingHistoryLoadToken = loadToken
        trainingHistoryLoadState = .loading
        pendingHistoryLoadTask = Task { [weak self, modelContainer] in
            defer {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.pendingHistoryLoadToken == loadToken else { return }
                    self.pendingHistoryLoadTask = nil
                    self.pendingHistoryLoadToken = nil
                }
            }
            let historyStore = HistoryStoreActor(modelContainer: modelContainer)
            do {
                let history = try await historyStore.fetchSessions()
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.trainingHistoryLoadState = .loaded
                    self?.syncTrainingHistory(from: history)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.trainingHistoryLoadState = .failed(
                        "Could not load saved history."
                    )
                }
            }
        }
    }

    func appendTrainingHistorySession(_ session: HistoryTransferSession) {
        var updatedHistory = cachedTrainingHistory
        updatedHistory.removeAll { $0.deduplicationKey == session.deduplicationKey }
        updatedHistory.append(session)
        syncTrainingHistory(from: updatedHistory)
    }

    func removeTrainingHistorySession(with deduplicationKey: HistoryTransferDeduplicationKey) {
        syncTrainingHistory(
            from: cachedTrainingHistory.filter { $0.deduplicationKey != deduplicationKey }
        )
    }

    func clearTrainingHistory() {
        pendingHistoryLoadTask?.cancel()
        pendingHistoryLoadTask = nil
        pendingHistoryLoadToken = nil
        trainingHistoryLoadState = .loaded
        liveTrainingEvents = []
        syncTrainingHistory(from: [HistoryTransferSession]())
        profileSnapshot = .empty
        shouldRestart = true
    }

    var trainingHistorySummary: TrainingHistorySummary {
        let sessions = trainingRuntime.sessions
        let bestWPM = Int(sessions.map(\.wpm).max() ?? 0)
        let averageAccuracy = sessions.isEmpty
            ? 0
            : Int((sessions.map(\.accuracy).reduce(0, +) / Double(sessions.count)).rounded())
        return TrainingHistorySummary(
            sessionsCount: sessions.count,
            bestWPM: bestWPM,
            averageAccuracy: averageAccuracy
        )
    }

    func dismissLiveTrainingEvent(_ event: TrainingProfileEvent) {
        liveTrainingEvents.removeAll { $0.id == event.id }
    }

    func dismissInfrastructureNotice() {
        switch infrastructureNotice?.source {
        case .history:
            historyStoreNotice = nil
            if case .failed = trainingHistoryLoadState {
                trainingHistoryLoadState = .idle
            }
        case .settings:
            settingsLoadNotice = nil
            settingsSaveFailureNotice = nil
        case .resources:
            resourceLoadNotice = nil
        case .none:
            break
        }
    }

    var infrastructureNotice: AppInfrastructureNotice? {
        if let historyStoreNotice {
            return historyStoreNotice
        }
        if case .failed(let message) = trainingHistoryLoadState {
            return AppInfrastructureNotice(
                source: .history,
                kind: .error,
                title: "History Unavailable",
                message: message
            )
        }
        return settingsSaveFailureNotice ?? settingsLoadNotice ?? resourceLoadNotice
    }
    
    // Helper properties mapping to the enums
    var theme: AppTheme {
        get {
            AppTheme(rawValue: settings.themeRaw) ?? .system
        }
        set {
            settings.themeRaw = newValue.rawValue
        }
    }
    
    var language: Language {
        get {
            Language(rawValue: settings.languageRaw) ?? .english
        }
        set {
            settings.languageRaw = newValue.rawValue
            shouldRestart = true
        }
    }

    func requestProfileWindowOpen() {
        profileWindowOpenIntent = true
    }

    func consumeProfileWindowOpenIntent() -> Bool {
        let shouldOpen = profileWindowOpenIntent
        profileWindowOpenIntent = false
        return shouldOpen
    }
}

struct TrainingHistorySummary: Equatable, Sendable {
    var sessionsCount: Int
    var bestWPM: Int
    var averageAccuracy: Int
}

enum TrainingHistoryLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

struct AppInfrastructureNotice: Identifiable, Equatable, Sendable {
    enum Source: String, Sendable {
        case history
        case settings
        case resources
    }

    enum Kind: String, Sendable {
        case warning
        case error
    }

    var id: String { source.rawValue }
    var source: Source
    var kind: Kind
    var title: String
    var message: String
}

private extension AppState {
    struct TrainingRuntimeConfiguration: Equatable, Sendable {
        var language: Language
        var dailyGoalMinutes: Int
        var adaptiveTargetWPM: Double
        var adaptiveAlphabetScale: Double
        var adaptiveRecoverKeys: Bool
        var adaptiveUnlockStrategy: AdaptiveUnlockStrategy
        var keyboardLayoutFamily: KeyboardLayoutFamily
    }

    struct TrainingRuntimeUpdate: Sendable {
        var progressStore: AdaptiveProgressStore
        var snapshot: AdaptiveTrainingRuntimeSnapshot
        var profileSnapshot: AdaptiveTrainingProfileSnapshot
    }

    enum HistorySyncMode: Sendable {
        case rebuild
        case append(startIndex: Int)
    }

    enum TrainingRuntimeRefreshMode: Sendable {
        case rebuildStore
        case appendToStore(startIndex: Int)
        case reuseStore
    }

    func refreshTrainingRuntimeFromCache() {
        guard !cachedTrainingHistory.isEmpty || hasPrimedTrainingRuntime else { return }
        refreshTrainingRuntime(
            using: cachedTrainingHistory,
            inputKey: cachedTrainingHistory.map(\.deduplicationKey)
        )
    }

    func refreshTrainingRuntime(
        using history: [HistoryTransferSession],
        inputKey: [HistoryTransferDeduplicationKey]
    ) {
        let configuration = currentTrainingRuntimeConfiguration()
        guard let refreshMode = trainingRuntimeRefreshMode(
            inputKey: inputKey,
            configuration: configuration
        ) else { return }

        let previousStore = trainingProgressStore
        let previousRuntime = trainingRuntime
        let language = self.language
        let settings = self.settings
        let historySlice: [HistoryTransferSession]
        switch refreshMode {
        case .rebuildStore, .reuseStore:
            historySlice = history
        case .appendToStore(let startIndex):
            historySlice = Array(history.dropFirst(startIndex))
        }

        pendingTrainingRuntimeTask?.cancel()
        pendingTrainingRuntimeTask = Task { [historySlice, inputKey, refreshMode, previousStore, previousRuntime, configuration, language, settings] in
            let update = await Task.detached(priority: .userInitiated) {
                let progressStore: AdaptiveProgressStore
                switch refreshMode {
                case .rebuildStore:
                    progressStore = AdaptiveTrainingRuntimeBuilder.buildProgressStore(
                        sessions: historySlice,
                        dailyGoalMinutes: settings.dailyGoalMinutes
                    )
                case .appendToStore:
                    progressStore = AdaptiveTrainingRuntimeBuilder.appending(
                        sessions: historySlice,
                        to: previousStore,
                        dailyGoalMinutes: settings.dailyGoalMinutes
                    )
                case .reuseStore:
                    progressStore = previousStore
                }

                let runtimeSnapshot = AdaptiveTrainingRuntimeBuilder.snapshot(
                    from: progressStore,
                    language: language,
                    settings: settings
                )

                return TrainingRuntimeUpdate(
                    progressStore: progressStore,
                    snapshot: runtimeSnapshot,
                    profileSnapshot: AdaptiveTrainingProfileBuilder.build(
                        runtime: runtimeSnapshot,
                        language: language,
                        settings: settings
                    )
                )
            }.value
            guard !Task.isCancelled else { return }

            let snapshot = stabilizedTrainingRuntime(update.snapshot, previous: previousRuntime)
            await MainActor.run {
                let previousEventIDs = Set(previousRuntime.allEvents.map(\.id))
                let previousSessionCount = previousRuntime.sessions.count
                let shouldEmitLiveMilestones =
                    hasPrimedTrainingRuntime &&
                    snapshot.sessions.count > previousSessionCount &&
                    abs((snapshot.sessions.last?.date ?? .distantPast).timeIntervalSinceNow) < 20

                trainingProgressStore = update.progressStore
                trainingRuntime = snapshot
                profileSnapshot = update.profileSnapshot
                lastTrainingHistoryInput = inputKey
                lastTrainingRuntimeConfiguration = configuration

                if shouldEmitLiveMilestones {
                    liveTrainingEvents = prioritizedLiveEvents(
                        from: preparedLiveEvents(
                            from: snapshot.allEvents.filter { !previousEventIDs.contains($0.id) }
                        )
                    )
                } else if !hasPrimedTrainingRuntime {
                    liveTrainingEvents = []
                }

                hasPrimedTrainingRuntime = true
            }
        }
    }

    func shouldRefreshTrainingRuntime(from oldSettings: AppSettings, to newSettings: AppSettings) -> Bool {
        trainingRuntimeConfiguration(for: oldSettings, language: Language(rawValue: oldSettings.languageRaw) ?? .english) !=
        trainingRuntimeConfiguration(for: newSettings, language: Language(rawValue: newSettings.languageRaw) ?? .english)
    }

    func currentTrainingRuntimeConfiguration() -> TrainingRuntimeConfiguration {
        trainingRuntimeConfiguration(for: settings, language: language)
    }

    func trainingRuntimeConfiguration(
        for settings: AppSettings,
        language: Language
    ) -> TrainingRuntimeConfiguration {
        TrainingRuntimeConfiguration(
            language: language,
            dailyGoalMinutes: settings.dailyGoalMinutes,
            adaptiveTargetWPM: settings.adaptiveTargetWPM,
            adaptiveAlphabetScale: settings.adaptiveAlphabetScale,
            adaptiveRecoverKeys: settings.adaptiveRecoverKeys,
            adaptiveUnlockStrategy: settings.adaptiveUnlockStrategy,
            keyboardLayoutFamily: settings.keyboardLayoutFamily
        )
    }

    func trainingRuntimeRefreshMode(
        inputKey: [HistoryTransferDeduplicationKey],
        configuration: TrainingRuntimeConfiguration
    ) -> TrainingRuntimeRefreshMode? {
        if !hasPrimedTrainingRuntime {
            return .rebuildStore
        }

        if inputKey != lastTrainingHistoryInput {
            return historySyncMode(for: inputKey).trainingRuntimeRefreshMode
        }

        if configuration != lastTrainingRuntimeConfiguration {
            return .reuseStore
        }

        return nil
    }

    func historySyncMode(for inputKey: [HistoryTransferDeduplicationKey]) -> HistorySyncMode {
        guard hasPrimedTrainingRuntime,
              inputKey.count >= lastTrainingHistoryInput.count,
              inputKey.starts(with: lastTrainingHistoryInput) else {
            return .rebuild
        }

        return .append(startIndex: lastTrainingHistoryInput.count)
    }

    func stabilizedTrainingRuntime(
        _ snapshot: AdaptiveTrainingRuntimeSnapshot,
        previous: AdaptiveTrainingRuntimeSnapshot
    ) -> AdaptiveTrainingRuntimeSnapshot {
        var stabilized = snapshot
        let previousAnalysisEvents = Dictionary(
            uniqueKeysWithValues: previous.allEvents
                .filter(isAnalysisDerivedEvent)
                .map { (analysisEventIdentity($0), $0) }
        )

        stabilized.allEvents = snapshot.allEvents.map { event in
            guard isAnalysisDerivedEvent(event),
                  let previousEvent = previousAnalysisEvents[analysisEventIdentity(event)] else {
                return event
            }
            return previousEvent
        }
        stabilized.recentEvents = AdaptiveTrainingProfileBuilder.recentEvents(from: stabilized.allEvents)
        return stabilized
    }

    func isAnalysisDerivedEvent(_ event: TrainingProfileEvent) -> Bool {
        event.kind == .unlockedKey && event.title == "Alphabet Ready"
    }

    func analysisEventIdentity(_ event: TrainingProfileEvent) -> String {
        "\(event.kind.rawValue)|\(event.title)|\(event.detail)"
    }

    func prioritizedLiveEvents(from events: [TrainingProfileEvent]) -> [TrainingProfileEvent] {
        events
            .sorted { lhs, rhs in
                let leftPriority = liveEventPriority(lhs.kind)
                let rightPriority = liveEventPriority(rhs.kind)
                if leftPriority == rightPriority {
                    return lhs.date > rhs.date
                }
                return leftPriority < rightPriority
            }
            .prefix(2)
            .map { $0 }
    }

    func preparedLiveEvents(from events: [TrainingProfileEvent]) -> [TrainingProfileEvent] {
        var prepared = events.sorted { $0.date > $1.date }

        for index in prepared.indices where prepared[index].kind == .newBestSpeed {
            let eventID = prepared[index].id
            guard autoRaisedTargetGoalEventIDs.insert(eventID).inserted else {
                continue
            }

            let achievedWPM = achievedWPM(from: prepared[index].detail)
            let currentGoal = settings.adaptiveTargetWPM
            guard achievedWPM >= currentGoal else {
                continue
            }

            let nextGoal = min(200, currentGoal + 10)
            if nextGoal > currentGoal {
                settings.adaptiveTargetWPM = nextGoal
                prepared[index].title = "WPM Goal Reached"
                prepared[index].detail = "Hit \(Int(achievedWPM.rounded())) WPM. New target: \(Int(nextGoal.rounded())) WPM. Update your goal in Settings any time."
            } else {
                prepared[index].title = "WPM Goal Reached"
                prepared[index].detail = "Hit \(Int(achievedWPM.rounded())) WPM. You are at the max target. Update your goal in Settings any time."
            }
        }

        return prepared
    }

    func achievedWPM(from eventDetail: String) -> Double {
        let digits = eventDetail.prefix { $0.isNumber }
        return Double(digits) ?? 0
    }

    func liveEventPriority(_ kind: TrainingProfileEventKind) -> Int {
        switch kind {
        case .dailyGoal:
            return 0
        case .unlockedKey:
            return 1
        case .newBestSpeed:
            return 2
        case .streak:
            return 3
        }
    }

    func scheduleSettingsSave(delayNanoseconds: UInt64 = 250_000_000) {
        let snapshot = PersistedAppSettings(settings)
        pendingSettingsSaveTask?.cancel()
        pendingSettingsSaveTask = Task { [settingsPersistence] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            do {
                try settingsPersistence.save(snapshot)
                await MainActor.run {
                    settingsSaveFailureNotice = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    settingsSaveFailureNotice = AppInfrastructureNotice(
                        source: .settings,
                        kind: .error,
                        title: "Settings Save Failed",
                        message: "The latest settings could not be written locally."
                    )
                }
            }
        }
    }

    func persistSettingsImmediately() {
        let snapshot = PersistedAppSettings(settings)
        pendingSettingsSaveTask?.cancel()
        pendingSettingsSaveTask = Task { [settingsPersistence] in
            do {
                try settingsPersistence.save(snapshot)
                await MainActor.run {
                    settingsSaveFailureNotice = nil
                }
            } catch {
                await MainActor.run {
                    settingsSaveFailureNotice = AppInfrastructureNotice(
                        source: .settings,
                        kind: .error,
                        title: "Settings Save Failed",
                        message: "The latest settings could not be written locally."
                    )
                }
            }
        }
    }

    func migrateLegacyErrorModeIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.errorModeMigrationKey) else { return }
        if settings.errorMode == .letter {
            settings.errorMode = .off
        }
        UserDefaults.standard.set(true, forKey: Self.errorModeMigrationKey)
    }

    func migrateLegacyCaretDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.caretColorMigrationKey) else { return }

        let usedLegacyBlueDefault =
            settings.caretStyle == .bar &&
            settings.caretColor == .systemBlue &&
            abs(settings.caretColorRed - 0.0) < 0.0001 &&
            abs(settings.caretColorGreen - 0.478) < 0.0001 &&
            abs(settings.caretColorBlue - 1.0) < 0.0001

        if usedLegacyBlueDefault {
            settings.caretColor = .custom
            settings.caretColorRed = 234.0 / 255.0
            settings.caretColorGreen = 51.0 / 255.0
            settings.caretColorBlue = 35.0 / 255.0
        }

        UserDefaults.standard.set(true, forKey: Self.caretColorMigrationKey)
    }

    static func normalizedSettings(_ raw: AppSettings) -> AppSettings {
        var settings = raw

        settings.timeLimit = min(600, max(15, settings.timeLimit))
        settings.wordLimit = min(400, max(10, settings.wordLimit))
        settings.dailyGoalMinutes = min(120, max(0, settings.dailyGoalMinutes))
        settings.adaptiveTargetWPM = min(200, max(15, settings.adaptiveTargetWPM))
        settings.adaptiveAlphabetScale = min(1, max(0, settings.adaptiveAlphabetScale))
        settings.lessonLength = min(1, max(0, settings.lessonLength))
        settings.repeatWords = min(10, max(1, settings.repeatWords))
        settings.capitalsProbability = min(1, max(0, settings.capitalsProbability))
        settings.punctuationProbability = min(1, max(0, settings.punctuationProbability))
        settings.fontSize = min(42, max(16, settings.fontSize))
        settings.lineHeight = min(2.5, max(1.0, settings.lineHeight))
        settings.letterSpacing = min(5, max(-2, settings.letterSpacing))
        settings.upcomingTextOpacity = min(1, max(0.35, settings.upcomingTextOpacity))
        settings.blinkRate = min(1, max(0, settings.blinkRate))
        settings.soundVolume = min(1, max(0, settings.soundVolume))
        settings.noiseIntensity = min(1.5, max(0, settings.noiseIntensity))
        settings.minAccuracy = min(100, max(0, settings.minAccuracy))

        if settings.customSnippetLibraries.isEmpty {
            settings.customSnippetLibraries = AppSettings.default.customSnippetLibraries
        }

        if let selectedID = settings.selectedSnippetLibraryID,
           settings.customSnippetLibraries.contains(where: { $0.id == selectedID }) {
            return settings
        }

        settings.selectedSnippetLibraryID = settings.customSnippetLibraries.first?.id
        return settings
    }
}

private extension AppState.HistorySyncMode {
    var trainingRuntimeRefreshMode: AppState.TrainingRuntimeRefreshMode {
        switch self {
        case .rebuild:
            return .rebuildStore
        case .append(let startIndex):
            return .appendToStore(startIndex: startIndex)
        }
    }
}

private final class SettingsPersistence {
    private let queue = DispatchQueue(label: AppIdentity.settingsQueueLabel, qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let settingsKey = "appSettings"
    private let corruptBackupKey = "appSettings.corruptBackup"

    struct LoadResult {
        var settings: AppSettings
        var notice: AppInfrastructureNotice?
    }

    func load(defaults: AppSettings) -> LoadResult {
        guard let data = UserDefaults.standard.data(forKey: settingsKey) else {
            return LoadResult(settings: defaults, notice: nil)
        }

        do {
            let decoded = try decoder.decode(PersistedAppSettings.self, from: data)
            return LoadResult(settings: decoded.appSettings, notice: nil)
        } catch {
            UserDefaults.standard.set(data, forKey: corruptBackupKey)
            UserDefaults.standard.removeObject(forKey: settingsKey)
            return LoadResult(
                settings: defaults,
                notice: AppInfrastructureNotice(
                    source: .settings,
                    kind: .warning,
                    title: "Settings Restored",
                    message: "Saved settings were corrupted. Defaults were restored and the broken payload was backed up."
                )
            )
        }
    }

    func save(_ settings: PersistedAppSettings) throws {
        try queue.sync {
            let encoded = try self.encoder.encode(settings)
            UserDefaults.standard.set(encoded, forKey: self.settingsKey)
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    case system = "System Default"
    
    var id: String { self.rawValue }
    
    func colorScheme() -> ColorScheme? {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        case .system:
            return nil
        }
    }
}
