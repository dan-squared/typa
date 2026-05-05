import SwiftUI
import SwiftData
import Combine
import Charts
#if os(macOS)
import AppKit
import AVFoundation
import UniformTypeIdentifiers
#endif

struct TypingView: View {
    @Bindable var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.ds) private var ds

    @FocusState private var isInputFocused: Bool

    @State private var activeSessionContext: TypingSessionContext?
    @State private var userInput = ""
    @State private var pendingAdaptiveDraft: NormalizedTypingResultDraft?
    @State private var finishedAdaptivePayload: AdaptiveSessionPayload?
    @State private var testFinished = false
    @State private var testStartedAt: Date?
    @State private var testFinishedAt: Date?
    @State private var sessionRecorder = AdaptiveSessionRecorder()
    @State private var restartSequence = 0
    @State private var lessonGenerationTask: Task<Void, Never>?
    @State private var isGeneratingLesson = false

    @State private var errorShake: CGFloat = 0
    #if os(macOS)
    @State private var soundURLCache: [String: URL] = [:]
    #endif
    @State private var isPointerInsideWindow = true
    @State private var liveNow = Date()
    @State private var typingContentVisible = true
    @State private var smoothViewportOffsetY: CGFloat = 0
    @State private var performanceState = TypingSessionPerformanceState()
    @State private var hoveredSecond: Int?
    @State private var hoveredChartLocation: CGPoint?
    @State private var sessionStatusMessage: String?
    @State private var isResultSettingsHovered = false
    @State private var isResultRestartHovered = false
    @State private var isResultNextHovered = false
    @State private var customWordSequenceIndex = 0
    // Entrance stagger states
    @State private var textVisible = false
    @State private var caretVisible = false
    @State private var statsVisible = false
    @State private var isPersistingResult = false
    @State private var activeNativeAlert: TypingNativeAlert?
    @State private var pendingNativeAlerts: [TypingNativeAlert] = []
    @State private var presentedLiveEventIDs: Set<String> = []
    @State private var nativeAlertVisibility = false
    @State private var entranceAnimationTask: Task<Void, Never>?
    @State private var errorResetTask: Task<Void, Never>?
    #if os(macOS)
    @State private var cachedLayoutSnapshot = TypingLayoutSnapshot.zero
    @State private var cachedLayoutKey: TypingLayoutCacheKey?
    @State private var cachedLayoutRenderedInput = ""
    @State private var cachedLayoutTextCharacters: [Character] = []
    @State private var soundPool = SoundEffectPool()
    #endif

    let inputKeys: CharacterSet = .whitespaces.union(.punctuationCharacters).union(.alphanumerics)

    private enum KeySoundRole {
        case standard
        case space
        case backspace
        case enter
    }

    private enum ToastTone {
        case success
        case warning
        case error
    }

    private struct TypingNativeAlert: Identifiable, Equatable {
        enum Source: Equatable {
            case sessionStatus
            case liveEvent(String)
        }

        var id: String
        var title: String
        var message: String
        var source: Source
        var eventKind: TrainingProfileEventKind?

        init(message: String) {
            self.id = "status|\(message)"
            self.title = "Session Status"
            self.message = message
            self.source = .sessionStatus
            self.eventKind = nil
        }

        init(event: TrainingProfileEvent) {
            self.id = "event|\(event.id)"
            self.title = event.title
            self.message = event.detail
            self.source = .liveEvent(event.id)
            self.eventKind = event.kind
        }
    }

    private var textToType: String {
        activeSessionContext?.textToType ?? ""
    }

    private var activeLesson: AdaptiveGeneratedLesson {
        activeSessionContext?.lesson ?? AdaptiveGeneratedLesson(text: "", lessonState: .empty)
    }

    private var sessionSettings: AppSettings {
        activeSessionContext?.settings ?? appState.settings
    }

    private var adaptiveHistoryTimeline: AdaptiveHistoryTimeline {
        AdaptiveHistoryTimeline(
            storedSessions: appState.trainingRuntime.sessions,
            pendingSession: pendingAdaptiveDraft?.trainingProfileSession
        )
    }

    private var adaptiveHistorySnapshots: [AdaptiveHistoryResult] {
        adaptiveHistoryTimeline.snapshots
    }

    private func accuracy() -> Int {
        performanceState.accuracy(inputCount: userInput.count)
    }

    private func grossWPM() -> Int {
        let duration: TimeInterval
        if let startedAt = testStartedAt {
            duration = (testFinishedAt ?? liveNow).timeIntervalSince(startedAt)
        } else {
            return 0
        }
        guard duration > 0 else { return 0 }

        return performanceState.grossWPM(inputCount: userInput.count, duration: duration)
    }

    private func netWPM() -> Int {
        let duration: TimeInterval
        if let startedAt = testStartedAt {
            duration = (testFinishedAt ?? liveNow).timeIntervalSince(startedAt)
        } else {
            return 0
        }
        guard duration > 0 else { return 0 }

        return performanceState.netWPM(duration: duration)
    }

    private var timeSeconds: Int {
        guard let started = testStartedAt else { return 0 }
        return Int((testFinishedAt ?? liveNow).timeIntervalSince(started))
    }

    private var usesTimeCap: Bool {
        guard sessionSettings.isTestMode else { return false }
        return sessionSettings.testLengthMode == .time || sessionSettings.useTimeCap
    }

    private var remainingTimeSeconds: Int {
        guard usesTimeCap else { return timeSeconds }
        guard let started = testStartedAt else { return sessionSettings.timeLimit }
        let elapsed = Int((testFinishedAt ?? liveNow).timeIntervalSince(started))
        return max(0, sessionSettings.timeLimit - elapsed)
    }

    private var dockTimeSeconds: Int {
        usesTimeCap ? remainingTimeSeconds : timeSeconds
    }

    private var countdownProgress: Double? {
        guard usesTimeCap else { return nil }
        let totalDuration = max(1, sessionSettings.timeLimit)
        let elapsed = totalDuration - remainingTimeSeconds
        return min(1, max(0, Double(elapsed) / Double(totalDuration)))
    }

    private var countdownValueColor: Color {
        guard let countdownProgress else { return .primary }
        switch countdownProgress {
        case 0.6666...:
            return ds.error
        case 0.3333...:
            return ds.accent
        default:
            return .primary
        }
    }

    private var incorrectCount: Int {
        performanceState.incorrectCharsCount
    }

    private var totalErrorCount: Int {
        performanceState.totalErrorCount
    }

    private var correctWordsCount: Int {
        performanceState.correctWordsCountSnapshot
    }

    private var finishedLessonFeedback: AdaptiveLastLessonFeedback? {
        finishedAdaptivePayload.map(AdaptiveLastLessonFeedback.make(from:))
    }

    private var consistencyRate: Int {
        performanceState.consistencyRate
    }

    private var resultTelemetryPayload: AdaptiveSessionPayload? {
        finishedAdaptivePayload
    }

    private var resultTelemetryFocusKey: String? {
        resultTelemetryPayload?.lesson.focusedKey
            ?? finishedLessonFeedback?.focusedKey
            ?? resultTelemetryPayload?.lesson.activeAlphabet.first
    }

    private var resultTelemetryKeyStats: [AdaptiveSessionKeyStat] {
        resultTelemetryPayload?.keyStats.sorted { $0.key < $1.key } ?? []
    }

    private var resultTelemetryActiveKeys: [String] {
        let lessonSymbols = Set(
            activeLesson.text.compactMap { character -> String? in
                let normalized = AdaptiveTypingEngine.normalizedSymbol(for: character)
                return normalized == " " ? nil : normalized
            }
        )
        let ordered = sessionSettings.keyboardLayout.rows.flatMap { $0 }
        let filtered = ordered.filter { lessonSymbols.contains($0) }
        if !filtered.isEmpty {
            let remaining = lessonSymbols.subtracting(filtered)
            return filtered + remaining.sorted()
        }
        return Array(lessonSymbols).sorted()
    }

    private var resultTelemetryCurrentStat: AdaptiveSessionKeyStat? {
        guard let resultTelemetryFocusKey else { return nil }
        return resultTelemetryKeyStats.first(where: { $0.key == resultTelemetryFocusKey })
    }

    private var resultSummaryCurrentSessionKey: HistoryTransferDeduplicationKey? {
        if let pendingAdaptiveDraft {
            return pendingAdaptiveDraft.deduplicationKey
        }

        guard sessionSettings.isLearningMode,
              let finishDate = testFinishedAt,
              let startedAt = testStartedAt,
              let adaptivePayloadJSON = finishedAdaptivePayload.flatMap(AdaptiveTypingEngine.encodedPayload) else {
            return nil
        }

        let completedSession = HistoryTransferSession(
            date: finishDate,
            mode: sessionSettings.resultModeIdentifier,
            duration: max(0, finishDate.timeIntervalSince(startedAt)),
            words: userInput.split(separator: " ").count,
            wpm: Double(netWPM()),
            accuracy: Double(accuracy()),
            rawInput: userInput,
            errors: totalErrorCount,
            adaptivePayloadJSON: adaptivePayloadJSON
        )
        return completedSession.deduplicationKey
    }

    private var resultSummaryCurrentSessionIndex: Int? {
        let sessions = adaptiveHistoryTimeline.sessions
        guard !sessions.isEmpty else { return nil }

        if let resultSummaryCurrentSessionKey,
           let matchedIndex = sessions.lastIndex(where: { $0.deduplicationKey == resultSummaryCurrentSessionKey }) {
            return matchedIndex
        }

        return nil
    }

    private var resultSummaryBaselineSession: TrainingProfileSession? {
        let sessions = adaptiveHistoryTimeline.sessions
        if let currentIndex = resultSummaryCurrentSessionIndex {
            guard currentIndex > sessions.startIndex else { return nil }
            return sessions[sessions.index(before: currentIndex)]
        }

        guard sessionSettings.isLearningMode,
              finishedAdaptivePayload != nil else {
            return nil
        }
        return sessions.last
    }

    private var currentIndex: Int {
        min(userInput.count, textToType.count)
    }

    private var showLiveDock: Bool {
        sessionSettings.showLiveStats
            && !testFinished
            && appState.isTypingActive
            && (scenePhase == .active || isPointerInsideWindow)
    }


    private var isIdle: Bool {
        userInput.isEmpty && !testFinished && testStartedAt == nil && !isGeneratingLesson
    }

    private var hasSessionInProgress: Bool {
        !userInput.isEmpty
            || testStartedAt != nil
            || performanceState.hasProgress
    }

    private var needsLiveClockUpdates: Bool {
        testStartedAt != nil && !testFinished && !isGeneratingLesson
    }

    private var allowsContinuousVisualEffects: Bool {
        scenePhase == .active && isPointerInsideWindow && !testFinished
    }

    private var usesReducedBackgroundEffects: Bool {
        isIdle || !allowsContinuousVisualEffects
    }

    private func generateTestLesson(settings: AppSettings) -> AdaptiveGeneratedLesson {
        let decoratedWords: [String]
        switch settings.testContentMode {
        case .numbers:
            decoratedWords = generateNumberFragmentWords(settings: settings)
        case .customWords:
            decoratedWords = generateCustomFragmentWords(settings: settings)
        case .commonWords, .codeWords:
            let desiredWordCount = testWordTarget(settings: settings)
            let sourceWords = testSourceWords(settings: settings)
            decoratedWords = makeDecoratedTestWords(
                from: sourceWords,
                count: desiredWordCount,
                settings: settings
            )
        }
        let activeAlphabet = activeAlphabet(from: decoratedWords)

        return AdaptiveGeneratedLesson(
            text: normalizeLongWords(in: decoratedWords.joined(separator: " ")),
            lessonState: AdaptiveLessonState(
                activeAlphabet: activeAlphabet,
                focusedKey: nil,
                forcedKeys: [],
                targetWPM: settings.adaptiveTargetWPM,
                source: "test-\(settings.testContentMode.rawValue)"
            )
        )
    }

    private func testSourceWords(settings: AppSettings) -> [String] {
        switch settings.testContentMode {
        case .commonWords:
            return appState.language.wordList()
        case .codeWords:
            return PracticeContentLibrary.codeWords
        case .numbers, .customWords:
            return PracticeContentLibrary.fallbackWords
        }
    }

    private func testWordTarget(settings: AppSettings) -> Int {
        switch settings.testLengthMode {
        case .time:
            return max(90, settings.timeLimit * 4)
        case .words:
            return max(10, settings.wordLimit)
        case .continuous:
            return max(220, settings.wordLimit * 4)
        }
    }

    private func makeTestWords(from sourceWords: [String], count: Int) -> [String] {
        let words = sourceWords.isEmpty ? PracticeContentLibrary.fallbackWords : sourceWords
        return PracticeContentLibrary.diversifiedTestWords(from: words, count: count)
    }

    static func preparedCustomSourceWords(
        rawText: String,
        settings: AppSettings,
        language: Language
    ) -> [String] {
        let sourceText = settings.customTextLowercase ? rawText.lowercased() : rawText
        let keyboardCharacters = AdaptiveTypingEngine.supportedKeyboardCharacters(for: settings.keyboardLayout)
        let learningLetters = AdaptiveTypingEngine.supportedLetters(for: language)
        let filtered = sourceText.map { character -> Character in
            if character.isWhitespace {
                return character
            }
            if settings.customTextLettersOnly {
                return learningLetters.contains(character) ? character : " "
            }
            return keyboardCharacters.contains(character) ? character : " "
        }

        return String(filtered)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func preparedCustomSourceWords(settings: AppSettings) -> [String] {
        let rawText: String
        if let selectedSnippetLibraryID = settings.selectedSnippetLibraryID,
           let selected = settings.customSnippetLibraries.first(where: { $0.id == selectedSnippetLibraryID }) {
            rawText = selected.wordsRaw
        } else {
            rawText = settings.customSnippetLibraries.first?.wordsRaw ?? ""
        }

        return Self.preparedCustomSourceWords(
            rawText: rawText,
            settings: settings,
            language: appState.language
        )
    }

    private func generateCustomFragmentWords(settings: AppSettings) -> [String] {
        let sourceWords = preparedCustomSourceWords(settings: settings)
        guard !sourceWords.isEmpty else { return ["?"] }

        let targetLength = AdaptiveTypingEngine.fragmentTextLength(for: settings)
        let repeatWords = max(1, settings.repeatWords)
        var output: [String] = []
        var outputLength = 0
        var generator = SystemRandomNumberGenerator()
        var previousWord = ""

        while outputLength < max(1, targetLength) {
            let nextWord: String
            if settings.isCustomAutoShuffleEnabled {
                nextWord = nextUniqueRandomWord(
                    from: sourceWords,
                    previousWord: previousWord,
                    generator: &generator
                ) ?? "?"
            } else {
                nextWord = sourceWords[customWordSequenceIndex % sourceWords.count]
                customWordSequenceIndex += 1
            }

            for _ in 0..<repeatWords {
                output.append(nextWord)
                outputLength += nextWord.count
                if outputLength >= max(1, targetLength) {
                    return output
                }
            }

            previousWord = nextWord
        }

        return output
    }

    private func generateNumberFragmentWords(settings: AppSettings) -> [String] {
        var generator = SystemRandomNumberGenerator()
        var words: [String] = []
        var wordsLength = 0

        while wordsLength < 50 {
            let word = generateNumberWord(settings: settings, generator: &generator)
            words.append(word)
            wordsLength += word.count
        }

        return words
    }

    private func generateNumberWord<T: RandomNumberGenerator>(
        settings: AppSettings,
        generator: inout T
    ) -> String {
        let digits = Array("0123456789").map(String.init)
        let leadingDigits = settings.numbersUseBenford
            ? [("1", 0.301), ("2", 0.176), ("3", 0.125), ("4", 0.097), ("5", 0.079), ("6", 0.067), ("7", 0.058), ("8", 0.051), ("9", 0.046)]
            : digits.dropFirst().map { ($0, 1.0) }

        let wordLength = Int.random(in: 3...6, using: &generator)
        var previousDigit = ""
        var output = ""

        for index in 0..<wordLength {
            while true {
                let digit: String
                if index == 0 {
                    digit = AdaptiveTypingEngine.weightedSample(from: leadingDigits, generator: &generator) ?? "1"
                } else {
                    digit = digits.randomElement(using: &generator) ?? "0"
                }

                if digit != previousDigit {
                    output += digit
                    previousDigit = digit
                    break
                }
            }
        }

        return output
    }

    private func nextUniqueRandomWord<T: RandomNumberGenerator>(
        from words: [String],
        previousWord: String,
        generator: inout T
    ) -> String? {
        guard !words.isEmpty else { return nil }

        for _ in 0..<3 {
            let candidate = words.randomElement(using: &generator) ?? "?"
            if candidate != previousWord {
                return candidate
            }
        }

        return words.randomElement(using: &generator)
    }

    private func makeDecoratedTestWords(
        from sourceWords: [String],
        count: Int,
        settings: AppSettings
    ) -> [String] {
        let baseWords = makeTestWords(from: sourceWords, count: count)
        var generator = SystemRandomNumberGenerator()
        return baseWords
            .map { word in
                AdaptiveTypingEngine.decorateWord(
                    word,
                    capitalsProbability: settings.capitalsProbability,
                    punctuationProbability: settings.punctuationProbability,
                    hyphenatedWord: sourceWords.randomElement(using: &generator),
                    generator: &generator
                )
            }
    }

    private func activeAlphabet(from words: [String]) -> [String] {
        var characters = Set<String>()
        characters.reserveCapacity(26)

        for word in words {
            for character in word.lowercased() where character.isLetter {
                characters.insert(String(character))
            }
        }

        return characters.sorted()
    }

    private func prepareSessionReset(clearLesson: Bool) {
        restartSequence += 1
        lessonGenerationTask?.cancel()
        entranceAnimationTask?.cancel()
        errorResetTask?.cancel()
        withAnimation(Motion.press) {
            typingContentVisible = false
        }
        withAnimation(Motion.structural) {
            testFinished = false
            testStartedAt = nil
            testFinishedAt = nil
            userInput = ""
            if clearLesson {
                activeSessionContext = nil
            }
        }
        sessionRecorder.reset()
        performanceState.reset()
        hoveredSecond = nil
        hoveredChartLocation = nil
        sessionStatusMessage = nil
        finishedAdaptivePayload = nil
        customWordSequenceIndex = 0
        smoothViewportOffsetY = 0
        errorShake = 0
        textVisible = false
        caretVisible = false
        statsVisible = false
        isGeneratingLesson = clearLesson
        #if os(macOS)
        cachedLayoutSnapshot = .zero
        cachedLayoutKey = nil
        #endif
        appState.practiceChangeTick += 1
        appState.isShowingResults = false
        appState.isTypingActive = false
    }

    private func applyLesson(_ generatedLesson: AdaptiveGeneratedLesson, for sequence: Int) {
        guard restartSequence == sequence else { return }
        lessonGenerationTask = nil
        isGeneratingLesson = false
        withAnimation(Motion.structural) {
            if let activeSessionContext {
                self.activeSessionContext = activeSessionContext.replacingLesson(generatedLesson)
            } else {
                activeSessionContext = TypingSessionContext(settings: appState.settings, lesson: generatedLesson)
            }
        }
        entranceAnimationTask?.cancel()
        // Staggered entrance: text -> caret -> stats
        entranceAnimationTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard restartSequence == sequence else { return }
                withAnimation(Motion.entrance) {
                    typingContentVisible = true
                    textVisible = true
                }
            }

            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard restartSequence == sequence else { return }
                withAnimation(Motion.entrance) {
                    caretVisible = true
                }
            }

            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard restartSequence == sequence else { return }
                withAnimation(Motion.entrance) {
                    statsVisible = true
                }
            }
        }
        appState.isTypingActive = true
        DispatchQueue.main.async {
            isInputFocused = true
        }
    }

    private func restart() {
        let frozenSettings = appState.settings
        prepareSessionReset(clearLesson: true)
        activeSessionContext = TypingSessionContext(
            settings: frozenSettings,
            lesson: AdaptiveGeneratedLesson(text: "", lessonState: .empty)
        )
        let currentRestartSequence = restartSequence

        if frozenSettings.isTestMode {
            activeSessionContext = activeSessionContext?.replacingLesson(generateTestLesson(settings: frozenSettings))
            applyLesson(activeLesson, for: currentRestartSequence)
            return
        }

        let language = appState.language
        let sharedRuntime = appState.trainingRuntime
        let adaptiveSnapshots = adaptiveHistorySnapshots
        let runtimeConfiguration = AdaptiveRuntimeConfigurationSnapshot(settings: frozenSettings, language: language)
        let canUseSharedRuntime =
            pendingAdaptiveDraft == nil &&
            sharedRuntime.configuration == runtimeConfiguration
        lessonGenerationTask = Task(priority: .userInitiated) {
            let generatedLesson = await Task.detached(priority: .userInitiated) {
                if canUseSharedRuntime {
                    return AdaptiveTypingEngine.makeLesson(
                        settings: frozenSettings,
                        language: language,
                        runtime: sharedRuntime
                    )
                }
                return AdaptiveTypingEngine.makeLesson(
                    settings: frozenSettings,
                    language: language,
                    results: adaptiveSnapshots
                )
            }.value
            guard !Task.isCancelled else { return }

            let normalizedLesson = AdaptiveGeneratedLesson(
                text: normalizeLongWords(in: generatedLesson.text),
                lessonState: generatedLesson.lessonState
            )
            await MainActor.run {
                activeSessionContext = activeSessionContext?.replacingLesson(normalizedLesson)
                applyLesson(normalizedLesson, for: currentRestartSequence)
            }
        }
    }

    private func replayCurrentSession() {
        guard !activeLesson.text.isEmpty else {
            restart()
            return
        }

        prepareSessionReset(clearLesson: false)
        let currentRestartSequence = restartSequence
        applyLesson(activeLesson, for: currentRestartSequence)
    }

    private func advanceToNextSession() {
        restart()
    }

    private func cancelCurrentSession() {
        guard !testFinished, hasSessionInProgress else { return }
        sessionStatusMessage = "Session cancelled."
        withAnimation(Motion.structural) {
            userInput = ""
            testStartedAt = nil
            testFinishedAt = nil
            testFinished = false
        }
        sessionRecorder.reset()
        performanceState.reset()
        hoveredSecond = nil
        hoveredChartLocation = nil
        smoothViewportOffsetY = 0
        errorShake = 0
        #if os(macOS)
        cachedLayoutSnapshot = .zero
        cachedLayoutKey = nil
        #endif
        appState.isShowingResults = false
        appState.isTypingActive = true
        DispatchQueue.main.async {
            isInputFocused = true
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let liveDockScale = floatingDockScale(for: geometry.size.width)
            ZStack(alignment: .bottom) {
                NoiseTextureBackground(
                    intensity: sessionSettings.noiseEnabled ? sessionSettings.noiseIntensity : 0,
                    usesReducedEffects: usesReducedBackgroundEffects
                )
                    .ignoresSafeArea()

                testView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .opacity(testFinished ? 0 : 1)
                    .allowsHitTesting(!testFinished && !isGeneratingLesson)
                    .onTapGesture {
                        guard !isGeneratingLesson else { return }
                        isInputFocused = true
                        appState.isTypingActive = true
                    }
                    .onHover { hovering in
                        isPointerInsideWindow = hovering
                    }
                    .opacity(typingContentVisible ? 1 : 0)
                    .offset(y: typingContentVisible ? 0 : 10)

                if showLiveDock {
                    FloatingStatsBadge(
                        wpm: netWPM(),
                        accuracy: accuracy(),
                        chars: userInput.count,
                        timeSeconds: dockTimeSeconds,
                        timeValueColor: countdownValueColor,
                        cascadeTick: appState.practiceChangeTick,
                        scale: liveDockScale
                    )
                    .frame(
                        width: FloatingStatsBadge.baseWidth * liveDockScale,
                        height: FloatingStatsBadge.baseHeight * liveDockScale,
                        alignment: .top
                    )
                    .padding(.bottom, max(Spacing.md, geometry.size.height * 0.022))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .opacity(statsVisible ? 1 : 0)
                }

                if testFinished {
                    resultsDashboard(in: geometry.size)
                        .padding(.bottom, Spacing.md)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .zIndex(10)
                }

                if let activeNativeAlert {
                    subtleSessionToast(
                        activeNativeAlert,
                        availableWidth: geometry.size.width
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, Spacing.md)
                    .padding(.trailing, Spacing.md)
                    .opacity(nativeAlertVisibility ? 1 : 0)
                    .offset(y: nativeAlertVisibility ? 0 : -10)
                    .allowsHitTesting(true)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
                }
            }
        }
        .animation(Motion.structural, value: showLiveDock)
        .onChange(of: isIdle, initial: true) { _, idle in
            withAnimation(Motion.structural) {
                appState.isFocusMode = !idle && !testFinished
            }
        }
        .onChange(of: testFinished) { _, finished in
            if finished {
                withAnimation(Motion.structural) {
                    appState.isFocusMode = false
                }
            }
        }
        .onChange(of: appState.shouldRestart, initial: false) { _, shouldRestart in
            if shouldRestart {
                restart()
                appState.shouldRestart = false
            }
        }
        .onChange(of: appState.trainingRuntime.sessions.map(\.deduplicationKey), initial: false) { _, sessionKeys in
            guard let pendingAdaptiveDraft else { return }
            let pendingKey = pendingAdaptiveDraft.deduplicationKey
            if sessionKeys.contains(pendingKey) {
                self.pendingAdaptiveDraft = nil
            }
        }
        .onChange(of: sessionStatusMessage, initial: false) { _, message in
            enqueueSessionStatusAlertIfNeeded(message)
        }
        .onChange(of: appState.liveTrainingEvents) { _, events in
            enqueueLiveEventAlerts(events)
        }
        .onChange(of: isInputFocused, initial: true) { _, focused in
            appState.isTypingActive = focused && !testFinished && !isGeneratingLesson
        }
        .onChange(of: testFinished, initial: true) { _, finished in
            appState.isShowingResults = finished
            appState.isTypingActive = !finished && isInputFocused && !isGeneratingLesson
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active, !testFinished, !isGeneratingLesson {
                DispatchQueue.main.async {
                    isInputFocused = true
                }
            }
            appState.isTypingActive = (phase == .active) && isInputFocused && !testFinished && !isGeneratingLesson
        }
        .onChange(of: activeNativeAlert?.id, initial: false) { _, newID in
            guard newID != nil else {
                nativeAlertVisibility = false
                return
            }
            withAnimation(Motion.structural) {
                nativeAlertVisibility = true
            }
        }
        .task(id: activeNativeAlert?.id) {
            guard let alert = activeNativeAlert else { return }
            try? await Task.sleep(nanoseconds: alertDisplayDuration(for: alert))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                dismissNativeAlert(alert)
            }
        }
        .task(id: needsLiveClockUpdates) {
            guard needsLiveClockUpdates else { return }

            while !Task.isCancelled {
                let now = Date()
                await MainActor.run {
                    guard needsLiveClockUpdates else { return }
                    liveNow = now
                    recordMetricPointIfNeeded()
                    finishTestIfNeeded(at: now)
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard !testFinished, !isGeneratingLesson else { return }
            guard let window = notification.object as? NSWindow else { return }
            guard window.isKeyWindow else { return }
            DispatchQueue.main.async {
                isInputFocused = true
                appState.isTypingActive = true
            }
        }
        #endif
        .focusable(!testFinished)
        .focused($isInputFocused)
        .focusEffectDisabled()
        .onKeyPress(KeyEquivalent("\u{7F}"), phases: .down.union(.repeat)) { _ in
            guard !testFinished, !isGeneratingLesson, !isPersistingResult, !userInput.isEmpty else { return .ignored }
            let previousInput = userInput
            userInput.removeLast()
            recordCorrectionSteps(from: previousInput, to: userInput, at: Date())
            sessionRecorder.truncate(to: userInput.count)
            processInput(from: previousInput, to: userInput)
            playKeySound(for: .backspace)
            return .handled
        }
        .onKeyPress(.return, phases: .down.union(.repeat)) { _ in
            guard !testFinished, !isGeneratingLesson, !isPersistingResult else { return .ignored }
            playKeySound(for: .enter)
            return .handled
        }
        .onKeyPress(.escape, phases: .down) { _ in
            guard !testFinished, !isGeneratingLesson, !isPersistingResult, hasSessionInProgress else { return .ignored }
            cancelCurrentSession()
            return .handled
        }
        .onKeyPress(characters: inputKeys, phases: .down.union(.repeat)) { keyPress in
            guard !testFinished, !isGeneratingLesson, !isPersistingResult else { return .ignored }
            guard userInput.count < textToType.count else { return .handled }

            let modifiers = keyPress.modifiers
            if modifiers.contains(.control) && keyPress.characters == "w" {
                deleteLastTypedWord()
                return .handled
            }
            guard allowsTypingModifiers(modifiers) else { return .ignored }

            guard let typedCharacter = keyPress.characters.first else { return .ignored }
            let newChar = String(typedCharacter)
            let expectedCharacter = characterAt(offset: userInput.count, in: textToType)

            if !shouldAcceptTypedCharacter(typedCharacter) {
                registerStrictReject(for: expectedCharacter, at: Date())
                playErrorFeedback()
                return .handled
            }

            let previousInput = userInput
            let keyPressDate = Date()
            if let expectedCharacter {
                sessionRecorder.recordAccepted(
                    expected: expectedCharacter,
                    typed: typedCharacter,
                    at: keyPressDate,
                    cursorIndex: userInput.count
                )
            }
            userInput += newChar
            processInput(from: previousInput, to: userInput)
            if sessionSettings.errorMode == .letter,
               let expectedCharacter,
               !charactersMatchForTyping(typedCharacter, expectedCharacter) {
                playErrorFeedback()
            }
            playKeySound(for: typedCharacter == " " ? .space : .standard)
            return .handled
        }
        .onKeyPress(phases: .up) { press in
            guard sessionSettings.keySoundPack == .alpaca else { return .ignored }
            
            let role: KeySoundRole
            if press.key == .return { role = .enter }
            else if press.key == .delete || press.key == .deleteForward || press.key == .init("\u{7F}") { role = .backspace }
            else if press.characters == " " { role = .space }
            else { role = .standard }
            
            playReleaseKeySound(for: role)
            return .handled
        }
    }

    private func floatingDockScale(for windowWidth: CGFloat) -> CGFloat {
        let additionalScale = max(0, (windowWidth - 860) / 4200)
        return min(1.1, 1 + additionalScale)
    }

    private func deleteLastTypedWord() {
        let previousInput = userInput
        let trimmed = userInput.trimmingCharacters(in: .whitespaces)
        if let lastSpace = trimmed.lastIndex(of: " ") {
            userInput = String(trimmed[...lastSpace])
        } else {
            userInput = ""
        }
        recordCorrectionSteps(from: previousInput, to: userInput, at: Date())
        sessionRecorder.truncate(to: userInput.count)
        processInput(from: previousInput, to: userInput)
        playKeySound(for: .backspace)
    }

    private func processInput(from previousInput: String, to input: String) {
        updateTypingMetrics(from: previousInput, to: input)
        performanceState.noteTotalErrors(totalErrorCount, atSecond: currentElapsedSecond())

        if input.isEmpty {
            testStartedAt = nil
        } else if testStartedAt == nil {
            testStartedAt = Date()
        }

        if currentIndex == textToType.count {
            if shouldAppendContinuationText {
                appendContinuationText()
                return
            }
            finishTest(at: Date())
            return
        }

        if sessionSettings.quickEnd && input.count >= textToType.count {
            finishTest(at: Date())
            return
        }

        finishTestIfNeeded(at: Date())
    }

    private func finishTestIfNeeded(at now: Date) {
        guard usesTimeCap, testStartedAt != nil, !testFinished, !isPersistingResult else { return }
        guard remainingTimeSeconds <= 0 else { return }
        finishTest(at: now)
    }

    private func finishTest(at finishDate: Date) {
        guard !testFinished, !isPersistingResult else { return }
        testFinishedAt = finishDate
        recordMetricPointIfNeeded()
        performanceState.correctWordsCountSnapshot = countCorrectWords(in: userInput)
        let achievedAccuracy = accuracy()

        if sessionSettings.minAccuracy > 0,
           Double(achievedAccuracy) < sessionSettings.minAccuracy {
            sessionStatusMessage = "Accuracy below \(Int(sessionSettings.minAccuracy.rounded()))%. Session not saved."
            playErrorFeedback()
            if sessionSettings.autoRestart {
                appState.shouldRestart = true
            } else {
                withAnimation(.spring) {
                    testFinished = true
                }
            }
            return
        }

        let duration = (testFinishedAt ?? finishDate).timeIntervalSince(testStartedAt ?? finishDate)
        let adaptivePayload: AdaptiveSessionPayload?
        if sessionSettings.isLearningMode {
            let payload = sessionRecorder.makePayload(lesson: activeLesson.lessonState)
            finishedAdaptivePayload = payload
            adaptivePayload = payload
        } else {
            finishedAdaptivePayload = nil
            adaptivePayload = nil
        }

        let draftResult: NormalizedTypingResultDraft
        switch TypingResultRecovery.validatedLocalDraft(
            date: finishDate,
            mode: sessionSettings.resultModeIdentifier,
            duration: duration,
            words: userInput.split(separator: " ").count,
            wpm: Double(netWPM()),
            accuracy: Double(achievedAccuracy),
            rawInput: userInput,
            errors: totalErrorCount,
            adaptivePayload: adaptivePayload
        ) {
        case .success(let draft):
            draftResult = draft
        case .failure(let reason):
            sessionStatusMessage = reason.message
            if sessionSettings.autoRestart {
                appState.shouldRestart = true
            } else {
                withAnimation(Motion.structural) {
                    testFinished = true
                }
            }
            return
        }

        let contributesToAdaptiveProfile = draftResult.modeDescriptor.contributesToAdaptiveProfile
        let autoRestart = sessionSettings.autoRestart
        let modelContainer = modelContext.container
        isPersistingResult = true
        pendingAdaptiveDraft = contributesToAdaptiveProfile ? draftResult : nil
        sessionStatusMessage = "Saving session…"
        if !autoRestart {
            withAnimation(Motion.structural) {
                testFinished = true
            }
        }

        Task {
            let historyStore = HistoryStoreActor(modelContainer: modelContainer)
            do {
                let savedSession = try await historyStore.saveDraft(draftResult)
                await MainActor.run {
                    appState.appendTrainingHistorySession(savedSession)
                    pendingAdaptiveDraft = nil
                    sessionStatusMessage = nil
                    isPersistingResult = false
                    if autoRestart {
                        appState.shouldRestart = true
                    }
                }
            } catch {
                await MainActor.run {
                    pendingAdaptiveDraft = nil
                    sessionStatusMessage = "Could not save session locally."
                    isPersistingResult = false
                    withAnimation(Motion.structural) {
                        testFinished = true
                    }
                }
            }
        }
    }

    var testView: some View {
        GeometryReader { geometry in
            let contentWidth = min(980, max(540, geometry.size.width * 0.72))
            let layoutSnapshot = displayedLayoutSnapshot(for: contentWidth)
            let caretOffsetY = layoutSnapshot.caretOrigin.y - smoothViewportOffsetY + caretVisualOffsetY
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack(alignment: .topLeading) {
                    TypingLayoutRenderer(snapshot: layoutSnapshot)
                        .frame(width: contentWidth, height: layoutSnapshot.fullTextHeight, alignment: .topLeading)
                        .offset(x: layoutSnapshot.contentOffsetX)
                        .offset(y: -smoothViewportOffsetY)
                        .allowsHitTesting(false)
                        .animation(Motion.viewportScroll, value: smoothViewportOffsetY)
                        .opacity(textVisible ? 1 : 0)
                        .offset(y: textVisible ? 0 : 6)

                    if !testFinished {
                        LiquidCaret(
                            style: sessionSettings.caretStyle,
                            color: sessionSettings.caretDisplayColor,
                            fontSize: sessionSettings.fontSize,
                            isBlinking: sessionSettings.blinkRate > 0 && !isIdle,
                            isIdle: isIdle,
                            allowsContinuousAnimation: allowsContinuousVisualEffects
                        )
                        .offset(
                            x: layoutSnapshot.contentOffsetX + layoutSnapshot.caretOrigin.x + caretVisualOffsetX,
                            y: caretOffsetY
                        )
                        .animation(
                            sessionSettings.smoothCaret
                                ? Motion.caret
                                : nil,
                            value: CGPoint(
                                x: layoutSnapshot.caretOrigin.x,
                                y: caretOffsetY
                            )
                        )
                        .opacity(caretVisible ? 1 : 0)
                    }

                    // Idle prompt
                    if isGeneratingLesson {
                        ProgressView("Preparing lesson")
                            .progressViewStyle(.circular)
                            .font(Typo.caption)
                            .tint(ds.accent)
                            .frame(width: contentWidth, alignment: .center)
                            .offset(y: layoutSnapshot.viewportHeight + Spacing.md)
                            .transition(.opacity)
                    } else if isIdle && caretVisible {
                        Text("type to begin")
                            .font(Typo.caption)
                            .foregroundStyle(ds.tertiaryText)
                            .frame(width: contentWidth, alignment: .center)
                            .offset(y: layoutSnapshot.viewportHeight + Spacing.md)
                            .transition(.opacity)
                    }
                }
                .frame(height: layoutSnapshot.viewportHeight, alignment: .top)
                .clipped()
                .frame(width: contentWidth, alignment: .center)
                .padding(.horizontal, Spacing.lg)
                .offset(x: errorShake)
                .blur(radius: testFinished ? 4 : 0)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(Spacing.xxl + Spacing.sm)
            .onChange(of: layoutSnapshot.viewportOffsetY, initial: true) { _, newValue in
                withAnimation(Motion.viewportScroll) {
                    smoothViewportOffsetY = newValue
                }
            }
            .task(id: typingLayoutRefreshID(for: contentWidth)) {
                refreshTypingLayoutIfNeeded(for: contentWidth)
            }
        }
        .onAppear {
            restart()
            isInputFocused = true
        }
        .onDisappear {
            lessonGenerationTask?.cancel()
            entranceAnimationTask?.cancel()
            errorResetTask?.cancel()
        }
    }

    private func enqueueSessionStatusAlertIfNeeded(_ message: String?) {
        guard let message,
              !message.isEmpty,
              !isPersistingResult,
              message != "Saving session…" else {
            return
        }
        enqueueNativeAlert(TypingNativeAlert(message: message))
    }

    private func enqueueLiveEventAlerts(_ events: [TrainingProfileEvent]) {
        for event in events where presentedLiveEventIDs.insert(event.id).inserted {
            enqueueNativeAlert(TypingNativeAlert(event: event))
        }
    }

    private func enqueueNativeAlert(_ alert: TypingNativeAlert) {
        if activeNativeAlert == nil {
            activeNativeAlert = alert
            return
        }

        guard activeNativeAlert != alert,
              !pendingNativeAlerts.contains(alert) else {
            return
        }
        pendingNativeAlerts.append(alert)
    }

    private func dismissNativeAlert(_ alert: TypingNativeAlert) {
        withAnimation(Motion.press) {
            nativeAlertVisibility = false
        }

        switch alert.source {
        case .sessionStatus:
            if sessionStatusMessage == alert.message {
                sessionStatusMessage = nil
            }
        case .liveEvent(let eventID):
            if let event = appState.liveTrainingEvents.first(where: { $0.id == eventID }) {
                appState.dismissLiveTrainingEvent(event)
            }
        }

        activeNativeAlert = nil
        presentNextNativeAlertIfNeeded()
    }

    private func presentNextNativeAlertIfNeeded() {
        guard activeNativeAlert == nil, !pendingNativeAlerts.isEmpty else { return }
        activeNativeAlert = pendingNativeAlerts.removeFirst()
    }

    private func alertDisplayDuration(for alert: TypingNativeAlert) -> UInt64 {
        switch alert.source {
        case .sessionStatus:
            return 2_000_000_000
        case .liveEvent:
            return 3_000_000_000
        }
    }

    @ViewBuilder
    private func subtleSessionToast(_ alert: TypingNativeAlert, availableWidth: CGFloat) -> some View {
        let tone = toastTone(for: alert)
        let targetWidth = min(300, max(216, availableWidth - 32))

        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(alert.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(ds.primaryText)
                    .lineLimit(1)

                Text(alert.message)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ds.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: toastSymbol(for: alert))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(toastTint(for: tone))
                .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: targetWidth, alignment: .leading)
        .background(SubtleMessageBackground(cornerRadius: CornerRadius.large))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.07), radius: 14, y: 8)
        .onTapGesture {
            dismissNativeAlert(alert)
        }
    }

    private func toastTint(for tone: ToastTone) -> Color {
        switch tone {
        case .success:
            return ds.success
        case .warning:
            return Color(red: 0.96, green: 0.80, blue: 0.28)
        case .error:
            return ds.error
        }
    }

    private func toastTone(for alert: TypingNativeAlert) -> ToastTone {
        switch alert.eventKind {
        case .dailyGoal:
            return .success
        case .newBestSpeed:
            return .success
        case .unlockedKey:
            return .warning
        case .streak:
            return .success
        case nil:
            let normalizedMessage = alert.message.lowercased()
            if normalizedMessage.contains("could not")
                || normalizedMessage.contains("failed")
                || normalizedMessage.contains("not saved")
                || normalizedMessage.contains("error") {
                return .error
            }

            if normalizedMessage.contains("cancelled")
                || normalizedMessage.contains("canceled")
                || normalizedMessage.contains("reset") {
                return .warning
            }

            return .success
        }
    }

    private func toastSymbol(for alert: TypingNativeAlert) -> String {
        switch alert.eventKind {
        case .dailyGoal:
            return "checkmark.circle.fill"
        case .newBestSpeed:
            return "arrow.up.right.circle.fill"
        case .unlockedKey:
            return "keyboard.badge.ellipsis"
        case .streak:
            return "flame.fill"
        case nil:
            switch toastTone(for: alert) {
            case .success:
                return "checkmark.circle.fill"
            case .warning:
                return "exclamationmark.triangle.fill"
            case .error:
                return "xmark.octagon.fill"
            }
        }
    }

    private var typedTextColor: Color {
        ds.primaryText
    }

    private var untypedTextColor: Color {
        let normalizedOpacity = min(max(sessionSettings.upcomingTextOpacity, 0.58), 0.9)
        let grayBase = colorScheme == .dark
            ? Color.white
            : Color.black
        let grayOpacity = colorScheme == .dark
            ? (0.34 + (normalizedOpacity * 0.32))
            : (0.30 + (normalizedOpacity * 0.28))
        return grayBase.opacity(grayOpacity)
    }

    #if os(macOS)
    private var typedTextNSColor: NSColor {
        colorScheme == .dark
            ? NSColor(white: 0.97, alpha: 1)
            : NSColor(white: 0.10, alpha: 1)
    }

    private var untypedTextNSColor: NSColor {
        colorScheme == .dark
            ? NSColor(white: 0.72, alpha: 1)
            : NSColor(white: 0.28, alpha: 1)
    }
    #endif

    private func displayedLayoutSnapshot(for width: CGFloat) -> TypingLayoutSnapshot {
        #if os(macOS)
        cachedLayoutSnapshot
        #else
        typingSnapshot(in: width)
        #endif
    }

    private var typingTextCharacters: [Character] {
        #if os(macOS)
        return cachedLayoutTextCharacters.isEmpty ? Array(textToType) : cachedLayoutTextCharacters
        #else
        return Array(textToType)
        #endif
    }

    #if os(macOS)
    private func resetCachedTypingLayout() {
        cachedLayoutSnapshot = .zero
        cachedLayoutKey = nil
        cachedLayoutRenderedInput = ""
        cachedLayoutTextCharacters = []
    }
    #endif

    private func characterAt(offset: Int, in string: String) -> Character? {
        guard offset >= 0, offset < string.count else { return nil }
        let index = string.index(string.startIndex, offsetBy: offset)
        return string[index]
    }

    private func playErrorFeedback() {
        guard sessionSettings.errorSound else { return }

        errorResetTask?.cancel()
        withAnimation(.spring(response: 0.15, dampingFraction: 0.25).repeatCount(2, autoreverses: true)) {
            errorShake = 2.5
        }
        errorResetTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                errorShake = 0
            }
        }

        playBundledSound(candidates: ["Error Sound 2"])
    }

    private func registerStrictReject(for expectedCharacter: Character?, at date: Date) {
        performanceState.noteStrictReject(atSecond: currentElapsedSecond())
        if let expectedCharacter {
            sessionRecorder.recordRejected(expected: expectedCharacter, at: date, cursorIndex: userInput.count)
        }
    }

    private func recordCorrectionSteps(from previousInput: String, to newInput: String, at date: Date) {
        let targetCharacters = typingTextCharacters
        guard previousInput.count > newInput.count, !targetCharacters.isEmpty else { return }

        let startOffset = min(previousInput.count, targetCharacters.count) - 1
        let endOffset = min(newInput.count, targetCharacters.count - 1)
        guard startOffset >= endOffset else { return }

        for offset in stride(from: startOffset, through: endOffset, by: -1) {
            let expectedCharacter = targetCharacters[offset]
            let previousExpected = offset > 0 ? targetCharacters[offset - 1] : nil
            sessionRecorder.recordCorrection(
                expected: expectedCharacter,
                previousExpected: previousExpected,
                at: date,
                cursorIndex: offset
            )
        }
    }

    private func playKeySound(for role: KeySoundRole = .standard) {
        guard sessionSettings.keySoundPack != .off else { return }

        switch sessionSettings.keySoundPack {
        case .off:
            return
        case .alpaca:
            switch role {
            case .standard:
                playBundledSound(candidates: [
                    "alpaca/press_key1",
                    "alpaca/press_key2",
                    "alpaca/press_key3",
                    "alpaca/press_key4",
                    "alpaca/press_key5"
                ])
            case .space:
                playBundledSound(candidates: ["alpaca/press_space"])
            case .backspace:
                playBundledSound(candidates: ["alpaca/press_back"])
            case .enter:
                playBundledSound(candidates: ["alpaca/press_enter"])
            }
        case .akira:
            switch role {
            case .standard, .backspace:
                playBundledSound(candidates: [
                    "Apex Pro TKL V2 Akira/akira_key1",
                    "Apex Pro TKL V2 Akira/akira_key3",
                    "Apex Pro TKL V2 Akira/akira_key4"
                ])
            case .space:
                playBundledSound(candidates: ["Apex Pro TKL V2 Akira/akira_space"])
            case .enter:
                playBundledSound(candidates: ["Apex Pro TKL V2 Akira/akira_enter"])
            }
        }
    }

    private func playReleaseKeySound(for role: KeySoundRole) {
        guard sessionSettings.keySoundPack == .alpaca else { return }
        
        switch role {
        case .standard:
            playBundledSound(candidates: ["alpaca/release_key"])
        case .space:
            playBundledSound(candidates: ["alpaca/release_space"])
        case .backspace:
            playBundledSound(candidates: ["alpaca/release_back"])
        case .enter:
            playBundledSound(candidates: ["alpaca/release_enter"])
        }
    }

    private func playBundledSound(candidates: [String]) {
        #if os(macOS)
        let volume = Float(sessionSettings.soundVolume)
        for name in candidates {
            if let soundURL = resolvedSoundURL(named: name) {
                soundPool.play(url: soundURL, name: name, volume: volume)
                return
            }
        }
        #endif
    }

    private func resolvedSoundURL(named name: String) -> URL? {
        #if os(macOS)
        if let cached = soundURLCache[name], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        #endif

        let resourceName = (name as NSString).lastPathComponent
        let resourceDirectory = (name as NSString).deletingLastPathComponent
        let subdirectory = resourceDirectory.isEmpty ? nil : resourceDirectory
        let bundles = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        let supportedExtensions = ["wav", "mp3", "ogg"]
        for bundle in bundles {
            for fileExtension in supportedExtensions {
                if let bundled = bundle.url(forResource: resourceName, withExtension: fileExtension, subdirectory: subdirectory) {
                    #if os(macOS)
                    soundURLCache[name] = bundled
                    #endif
                    return bundled
                }
                if let bundled = bundle.url(forResource: resourceName, withExtension: fileExtension) {
                    #if os(macOS)
                    soundURLCache[name] = bundled
                    #endif
                    return bundled
                }
            }
        }

        for fileExtension in supportedExtensions {
            if let bundledPath = Bundle.main.path(forResource: resourceName, ofType: fileExtension, inDirectory: subdirectory) {
                let bundled = URL(fileURLWithPath: bundledPath)
                #if os(macOS)
                soundURLCache[name] = bundled
                #endif
                return bundled
            }
            if let bundledPath = Bundle.main.path(forResource: resourceName, ofType: fileExtension) {
                let bundled = URL(fileURLWithPath: bundledPath)
                #if os(macOS)
                soundURLCache[name] = bundled
                #endif
                return bundled
            }
        }

        return nil
    }

    private func updateTypingMetrics(from previousInput: String, to newInput: String) {
        if newInput.hasPrefix(previousInput) {
            applyAppendedMetrics(from: previousInput, to: newInput)
            return
        }

        if previousInput.hasPrefix(newInput) {
            removeMetrics(from: previousInput, downTo: newInput)
            return
        }

        recalculateTypingMetrics(for: newInput)
    }

    private func applyAppendedMetrics(from previousInput: String, to newInput: String) {
        let inputCharacters = Array(newInput)
        let targetCharacters = typingTextCharacters
        let upperBound = min(inputCharacters.count, targetCharacters.count)
        guard previousInput.count < upperBound else { return }

        for offset in previousInput.count..<upperBound {
            let typedCharacter = inputCharacters[offset]
            let expectedCharacter = targetCharacters[offset]
            if charactersMatchForTyping(typedCharacter, expectedCharacter) {
                performanceState.correctCharsCount += 1
            } else {
                performanceState.incorrectCharsCount += 1
            }
        }
    }

    private func removeMetrics(from previousInput: String, downTo newInput: String) {
        let previousCharacters = Array(previousInput)
        let targetCharacters = typingTextCharacters
        let startOffset = min(previousCharacters.count, targetCharacters.count) - 1
        let endOffset = min(newInput.count, targetCharacters.count - 1)
        guard startOffset >= endOffset else { return }

        for offset in stride(from: startOffset, through: endOffset, by: -1) {
            let typedCharacter = previousCharacters[offset]
            let expectedCharacter = targetCharacters[offset]
            if charactersMatchForTyping(typedCharacter, expectedCharacter) {
                performanceState.correctCharsCount = max(0, performanceState.correctCharsCount - 1)
            } else {
                performanceState.incorrectCharsCount = max(0, performanceState.incorrectCharsCount - 1)
            }
        }
    }

    private func recalculateTypingMetrics(for input: String) {
        var correct = 0
        var incorrect = 0
        let targetCharacters = typingTextCharacters
        let inputCharacters = Array(input)

        for (expectedCharacter, typedCharacter) in zip(targetCharacters, inputCharacters) {
            if charactersMatchForTyping(typedCharacter, expectedCharacter) {
                correct += 1
            } else {
                incorrect += 1
            }
        }

        performanceState.correctCharsCount = correct
        performanceState.incorrectCharsCount = incorrect
    }

    private func countCorrectWords(in input: String) -> Int {
        var correctCount = 0
        var targetIndex = textToType.startIndex
        var inputIndex = input.startIndex

        while targetIndex < textToType.endIndex, inputIndex <= input.endIndex {
            let targetWordEnd = textToType[targetIndex...].firstIndex(of: " ") ?? textToType.endIndex
            let inputWordEnd = inputIndex < input.endIndex
                ? (input[inputIndex...].firstIndex(of: " ") ?? input.endIndex)
                : input.endIndex

            let expectedWord = String(textToType[targetIndex..<targetWordEnd])
            let typedWord = String(input[inputIndex..<inputWordEnd])

            if wordsMatchForTyping(typedWord, expectedWord: expectedWord) {
                correctCount += 1
            }

            guard targetWordEnd < textToType.endIndex, inputWordEnd < input.endIndex else {
                break
            }

            targetIndex = textToType.index(after: targetWordEnd)
            inputIndex = input.index(after: inputWordEnd)
        }

        return correctCount
    }

    private func wordsMatchForTyping(_ typedWord: String, expectedWord: String) -> Bool {
        guard typedWord.count == expectedWord.count else { return false }

        for (typedCharacter, expectedCharacter) in zip(typedWord, expectedWord) {
            if !charactersMatchForTyping(typedCharacter, expectedCharacter) {
                return false
            }
        }

        return true
    }

    private func typingSnapshot(in width: CGFloat) -> TypingLayoutSnapshot {
        #if os(macOS)
        let key = typingLayoutCacheKey(for: width)
        return buildTypingLayoutSnapshot(for: key, width: width)
        #else
        return .zero
        #endif
    }

    private func typingLayoutRefreshID(for width: CGFloat) -> TypingLayoutRefreshID {
        TypingLayoutRefreshID(
            width: Int(width.rounded()),
            textToType: textToType,
            userInput: userInput,
            settings: sessionSettings,
            testFinished: testFinished
        )
    }

    private func refreshTypingLayoutIfNeeded(for width: CGFloat) {
        #if os(macOS)
        guard !textToType.isEmpty else {
            resetCachedTypingLayout()
            return
        }

        let key = typingLayoutCacheKey(for: width)
        if cachedLayoutKey == key,
           let textStorage = cachedLayoutSnapshot.textStorage,
           let layoutManager = cachedLayoutSnapshot.layoutManager,
           let textContainer = cachedLayoutSnapshot.textContainer {
            let (nsFont, paragraph) = makeTypingLayoutConfiguration()
            cachedLayoutSnapshot = updateTypingLayoutSnapshot(
                textStorage: textStorage,
                layoutManager: layoutManager,
                textContainer: textContainer,
                nsFont: nsFont,
                paragraph: paragraph,
                forceFullRefresh: false
            )
            return
        }

        cachedLayoutSnapshot = buildTypingLayoutSnapshot(for: key, width: width)
        cachedLayoutKey = key
        #endif
    }

    #if os(macOS)
    private func typingLayoutCacheKey(for width: CGFloat) -> TypingLayoutCacheKey {
        TypingLayoutCacheKey(
            width: Int(width.rounded()),
            textToType: textToType,
            fontSize: sessionSettings.fontSize,
            lineHeight: sessionSettings.lineHeight,
            letterSpacing: sessionSettings.letterSpacing,
            caretStyle: sessionSettings.caretStyle,
            themeRaw: sessionSettings.themeRaw,
            colorScheme: colorScheme,
            upcomingTextOpacity: sessionSettings.upcomingTextOpacity,
            smoothCaret: sessionSettings.smoothCaret,
            caretColorRed: sessionSettings.caretColorRed,
            caretColorGreen: sessionSettings.caretColorGreen,
            caretColorBlue: sessionSettings.caretColorBlue
        )
    }

    private func makeTypingLayoutConfiguration() -> (NSFont, NSMutableParagraphStyle) {
        let nsFont = NSFont.monospacedSystemFont(ofSize: sessionSettings.fontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = sessionSettings.lineHeight * 10
        paragraph.alignment = .center
        return (nsFont, paragraph)
    }

    private func buildTypingLayoutSnapshot(for key: TypingLayoutCacheKey, width: CGFloat) -> TypingLayoutSnapshot {
        let (nsFont, paragraph) = makeTypingLayoutConfiguration()
        cachedLayoutTextCharacters = Array(key.textToType)
        cachedLayoutRenderedInput = ""

        let textStorage = NSTextStorage(string: key.textToType)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        textContainer.lineBreakMode = .byWordWrapping

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let snapshot = updateTypingLayoutSnapshot(
            textStorage: textStorage,
            layoutManager: layoutManager,
            textContainer: textContainer,
            nsFont: nsFont,
            paragraph: paragraph,
            forceFullRefresh: true
        )
        cachedLayoutKey = key
        return snapshot
    }

    private func updateTypingLayoutSnapshot(
        textStorage: NSTextStorage,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        nsFont: NSFont,
        paragraph: NSMutableParagraphStyle,
        forceFullRefresh: Bool
    ) -> TypingLayoutSnapshot {
        refreshDisplayAttributedString(
            in: textStorage,
            using: nsFont,
            paragraph: paragraph,
            forceFullRefresh: forceFullRefresh
        )
        layoutManager.ensureLayout(for: textContainer)

        let boundedIndex = min(currentIndex, textToType.count)
        let stringIndex = textToType.index(textToType.startIndex, offsetBy: boundedIndex)
        let nsString = textToType as NSString
        let characterIndex = stringIndex.utf16Offset(in: textToType)

        guard layoutManager.numberOfGlyphs > 0 else { return .zero }

        var lineFragmentRects: [CGRect] = []
        var glyphIndex = 0
        while glyphIndex < layoutManager.numberOfGlyphs {
            var lineRange = NSRange()
            let lineFragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineRange,
                withoutAdditionalLayout: true
            )
            lineFragmentRects.append(lineFragmentRect)
            glyphIndex = NSMaxRange(lineRange)
            if lineRange.length == 0 {
                break
            }
        }

        let measuredLineHeight = lineFragmentRects.prefix(3).map(\.height).max()
            ?? max(1, nsFont.ascender - nsFont.descender + paragraph.lineSpacing)
        let bottomPadding = max(4, paragraph.lineSpacing * 0.35)
        let fullTextHeight = max(
            measuredLineHeight * 3 + bottomPadding,
            layoutManager.usedRect(for: textContainer).height + bottomPadding
        )
        let contentOffsetX: CGFloat = 0

        let caretOrigin: CGPoint
        if boundedIndex == 0 {
            let firstGlyphRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: 0, length: 1),
                in: textContainer
            )
            let firstLineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: nil)
            caretOrigin = CGPoint(
                x: firstGlyphRect.isEmpty ? firstLineRect.minX : firstGlyphRect.minX,
                y: firstLineRect.minY
            )
        } else if characterIndex >= nsString.length {
            let extraLineRect = layoutManager.extraLineFragmentUsedRect
            if !extraLineRect.isEmpty {
                caretOrigin = CGPoint(x: extraLineRect.minX, y: extraLineRect.minY)
            } else {
                let lastGlyphIndex = layoutManager.numberOfGlyphs - 1
                var lineRange = NSRange()
                let lineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: lastGlyphIndex, effectiveRange: &lineRange)
                let lineFragmentRect = layoutManager.lineFragmentRect(
                    forGlyphAt: lastGlyphIndex,
                    effectiveRange: nil,
                    withoutAdditionalLayout: true
                )
                let glyphRect = layoutManager.boundingRect(
                    forGlyphRange: NSRange(location: lastGlyphIndex, length: 1),
                    in: textContainer
                )
                let glyphMaxX = glyphRect.isEmpty ? lineRect.maxX : glyphRect.maxX
                var insertionX = glyphMaxX
                var insertionY = lineRect.minY
                if insertionX >= lineFragmentRect.maxX - 0.5 {
                    insertionX = lineFragmentRect.minX
                    insertionY += lineRect.height
                }
                caretOrigin = CGPoint(x: insertionX, y: insertionY)
            }
        } else {
            let nextGlyphIndex = min(
                layoutManager.glyphIndexForCharacter(at: characterIndex),
                layoutManager.numberOfGlyphs - 1
            )
            let nextLineRect = layoutManager.lineFragmentUsedRect(forGlyphAt: nextGlyphIndex, effectiveRange: nil)
            let nextLineFragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: nextGlyphIndex,
                effectiveRange: nil,
                withoutAdditionalLayout: true
            )
            let nextGlyphLocation = layoutManager.location(forGlyphAt: nextGlyphIndex)
            caretOrigin = CGPoint(
                x: nextLineFragmentRect.minX + nextGlyphLocation.x,
                y: nextLineRect.minY
            )
        }

        let currentLineIndex = lineFragmentRects.lastIndex(where: {
            caretOrigin.y >= $0.minY && caretOrigin.y < $0.maxY
        }) ?? max(0, lineFragmentRects.count - 1)
        let startLine = lineFragmentRects.count <= 3
            ? 0
            : min(max(currentLineIndex - 1, 0), max(0, lineFragmentRects.count - 3))
        let viewportOffsetY = lineFragmentRects.indices.contains(startLine) ? lineFragmentRects[startLine].minY : 0

        return TypingLayoutSnapshot(
            textStorage: textStorage,
            layoutManager: layoutManager,
            textContainer: textContainer,
            caretOrigin: caretOrigin,
            contentOffsetX: contentOffsetX,
            viewportOffsetY: viewportOffsetY,
            viewportHeight: measuredLineHeight * 3,
            fullTextHeight: fullTextHeight
        )
    }
    #endif

    #if os(macOS)
    private func refreshDisplayAttributedString(
        in textStorage: NSTextStorage,
        using nsFont: NSFont,
        paragraph: NSMutableParagraphStyle,
        forceFullRefresh: Bool
    ) {
        let fullTextCharacters = cachedLayoutTextCharacters.isEmpty
            ? Array(textToType)
            : cachedLayoutTextCharacters
        guard !fullTextCharacters.isEmpty else {
            textStorage.setAttributedString(NSAttributedString(string: ""))
            cachedLayoutRenderedInput = userInput
            return
        }

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: nsFont,
            .kern: sessionSettings.letterSpacing,
            .paragraphStyle: paragraph,
            .foregroundColor: untypedTextNSColor
        ]
        let previousInputCharacters = Array(cachedLayoutRenderedInput)
        let currentInputCharacters = Array(userInput)
        let shouldRebuildStorage =
            forceFullRefresh ||
            textStorage.string != textToType ||
            textStorage.length != fullTextCharacters.count

        if shouldRebuildStorage {
            textStorage.setAttributedString(
                NSAttributedString(string: textToType, attributes: baseAttributes)
            )
        }

        let fullTextCount = fullTextCharacters.count
        let previousCaretIndex = min(previousInputCharacters.count, fullTextCount)
        let currentCaretIndex = min(currentInputCharacters.count, fullTextCount)
        let dirtyContentStart = shouldRebuildStorage ? 0 : sharedCharacterPrefixLength(previousInputCharacters, currentInputCharacters)
        let dirtyContentEnd = shouldRebuildStorage
            ? fullTextCount
            : max(previousInputCharacters.count, currentInputCharacters.count)
        let dirtyCaretStart = min(previousCaretIndex, currentCaretIndex)
        let dirtyCaretEnd = max(previousCaretIndex, currentCaretIndex) + 1
        let dirtyStart = min(dirtyContentStart, dirtyCaretStart)
        let dirtyEnd = min(fullTextCount, max(dirtyContentEnd, dirtyCaretEnd))

        guard dirtyStart < dirtyEnd else {
            cachedLayoutRenderedInput = userInput
            return
        }

        textStorage.beginEditing()
        for offset in dirtyStart..<dirtyEnd {
            var attributes = baseAttributes
            let character = fullTextCharacters[offset]
            if offset < currentInputCharacters.count {
                let userCharacter = currentInputCharacters[offset]
                if charactersMatchForTyping(userCharacter, character) {
                    attributes[.foregroundColor] = typedTextNSColor
                } else {
                    attributes[.foregroundColor] = NSColor.systemRed
                    if character == " " {
                        attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                        attributes[.underlineColor] = NSColor.systemRed.withAlphaComponent(0.95)
                    }
                }
            } else {
                attributes[.foregroundColor] = untypedTextNSColor
            }

            textStorage.setAttributes(attributes, range: NSRange(location: offset, length: 1))
        }
        textStorage.endEditing()

        cachedLayoutRenderedInput = userInput
    }

    private func sharedCharacterPrefixLength(_ lhs: [Character], _ rhs: [Character]) -> Int {
        let count = min(lhs.count, rhs.count)
        guard count > 0 else { return 0 }

        var matched = 0
        while matched < count, lhs[matched] == rhs[matched] {
            matched += 1
        }
        return matched
    }
    #endif

    private var caretVisualOffsetX: CGFloat {
        switch sessionSettings.caretStyle {
        case .bar: return -1.2
        case .block: return 1
        case .underline: return 1
        }
    }

    private var caretVisualOffsetY: CGFloat {
        let adaptiveNudge = max(1.4, sessionSettings.fontSize * 0.11)
        switch sessionSettings.caretStyle {
        case .underline:
            return adaptiveNudge * 3.0
        case .bar, .block:
            return adaptiveNudge * 1.38
        }
    }

    private func currentElapsedSecond() -> Int? {
        guard let started = testStartedAt else { return nil }
        return max(0, Int((testFinishedAt ?? liveNow).timeIntervalSince(started)))
    }

    private func recordMetricPointIfNeeded() {
        guard let second = currentElapsedSecond(), second > 0 else { return }
        let point = SessionMetricPoint(
            second: second,
            wpm: Double(netWPM()),
            accuracy: Double(accuracy()),
            errorCount: performanceState.errorCountsBySecond[second, default: 0],
            correctCharsSnapshot: performanceState.correctCharsCount,
            attemptedCharsSnapshot: userInput.count + performanceState.strictRejectCount
        )
        performanceState.recordMetricPoint(point)
    }

    private func resultsDashboard(in size: CGSize) -> some View {
        let horizontalPadding = max(Spacing.sm, min(Spacing.xl + Spacing.xs, size.width * 0.035))
        let contentWidth = max(240, size.width - (horizontalPadding * 2))
        let contentHeight = max(220, size.height - Spacing.xl)

        let baseWidth: CGFloat = 190 + 538 + 154 + (Spacing.sm * 2)
        let panelHeight: CGFloat = 334
        let telemetryHeight: CGFloat = resultTelemetryPayload == nil ? 0 : 86
        let baseHeight: CGFloat = panelHeight + (resultTelemetryPayload == nil ? 0 : (Spacing.md + telemetryHeight)) + Spacing.md + 56

        let scale = min(1, contentWidth / baseWidth, contentHeight / baseHeight)
        let scaledWidth = baseWidth * scale
        let scaledHeight = baseHeight * scale

        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: Spacing.md) {
                resultCardGrid(for: panelHeight)
                if resultTelemetryPayload != nil {
                    resultTelemetryStrip
                        .frame(height: telemetryHeight)
                }
                resultActionButtons
            }
            .frame(width: baseWidth, height: baseHeight, alignment: .top)
            .scaleEffect(scale, anchor: .top)
            .frame(width: scaledWidth, height: scaledHeight, alignment: .top)
            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func resultCardGrid(for panelHeight: CGFloat) -> some View {
        let stackSpacing: CGFloat = Spacing.md
        let primaryCardWidth: CGFloat = 190
        let graphCardWidth: CGFloat = 538
        let sideStackWidth: CGFloat = 154
        let sideCardCount = finishedLessonFeedback == nil ? 2 : 3
        let miniCardHeight = (panelHeight - (stackSpacing * CGFloat(sideCardCount - 1))) / CGFloat(sideCardCount)

        return HStack(alignment: .top, spacing: Spacing.sm) {
            resultPrimaryStatsCard
                .frame(width: primaryCardWidth, height: panelHeight)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

            resultGraphCard
                .frame(width: graphCardWidth, height: panelHeight)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

            VStack(alignment: .leading, spacing: stackSpacing) {
                resultMiniMetric(title: "CONSISTENCY", value: "\(consistencyRate)%", countUp: consistencyRate)
                    .frame(width: sideStackWidth, height: miniCardHeight, alignment: .topLeading)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                if let finishedLessonFeedback {
                    resultLessonInsightCard(feedback: finishedLessonFeedback)
                        .frame(width: sideStackWidth, height: miniCardHeight, alignment: .topLeading)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                resultMiniMetric(title: "TIME", value: "\(timeSeconds)s")
                    .frame(width: sideStackWidth, height: miniCardHeight, alignment: .topLeading)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            .frame(width: sideStackWidth, height: panelHeight, alignment: .topLeading)
        }
    }

    private var resultActionButtons: some View {
        HStack(spacing: Spacing.md) {
            Button {
                openSettings()
            } label: {
                ResultIconButtonLabel(systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isResultSettingsHovered = hovering
            }
            .background {
                if isResultSettingsHovered {
                    DSResultHoverBackground()
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
            .scaleEffect(isResultSettingsHovered ? 1.04 : 1)
            .animation(Motion.hover, value: isResultSettingsHovered)
            .help("Open Settings")

            Button {
                replayCurrentSession()
            } label: {
                ResultIconButtonLabel(systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isResultRestartHovered = hovering
            }
            .background {
                if isResultRestartHovered {
                    DSResultHoverBackground()
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
            .scaleEffect(isResultRestartHovered ? 1.04 : 1)
            .animation(Motion.hover, value: isResultRestartHovered)
            .help("Restart Current Session")

            Button {
                advanceToNextSession()
            } label: {
                ResultIconButtonLabel(systemImage: "chevron.right")
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isResultNextHovered = hovering
            }
            .background {
                if isResultNextHovered {
                    DSResultHoverBackground()
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
            .scaleEffect(isResultNextHovered ? 1.04 : 1)
            .animation(Motion.hover, value: isResultNextHovered)
            .help(sessionSettings.isLearningMode ? "Next Lesson" : "Next Test")
            .keyboardShortcut(.tab, modifiers: [])
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var resultGraphCard: some View {
        let chartPoints = rollingSessionChartPoints(from: performanceState.metricPoints)
        let maxObservedWPM = chartPoints.map(\.wpm).max() ?? 0
        let chartMaxY = max(100, ceil(max(maxObservedWPM, 100) / 10) * 10)
        let maxSecond = max(1, chartPoints.map(\.second).max() ?? 1)
        let accuracyAxisValues = accuracyAxisMarks(for: chartMaxY)

        return VStack(alignment: .leading, spacing: Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("PER-SECOND PERFORMANCE")
                        .font(Typo.label)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: Spacing.sm) {
                        legendDot(ds.accent, "WPM")
                        legendDot(ds.success, "Accuracy")
                        legendDot(ds.error, "Errors")
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("PER-SECOND PERFORMANCE")
                        .font(Typo.label)
                        .foregroundStyle(.secondary)
                    HStack(spacing: Spacing.sm) {
                        legendDot(ds.accent, "WPM")
                        legendDot(ds.success, "Accuracy")
                        legendDot(ds.error, "Errors")
                    }
                }
            }

            ZStack(alignment: .topTrailing) {
                Chart {
                    ForEach(chartPoints) { point in
                        AreaMark(
                            x: .value("Second", point.second),
                            y: .value("WPM Fill", point.wpm)
                        )
                        .interpolationMethod(.linear)
                        .foregroundStyle(ds.accent.opacity(0.14))

                        LineMark(
                            x: .value("Second", point.second),
                            y: .value("WPM", point.wpm)
                        )
                        .foregroundStyle(ds.accent)
                        .interpolationMethod(.linear)
                        .lineStyle(.init(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                        LineMark(
                            x: .value("Second", point.second),
                            y: .value("Accuracy", scaledAccuracy(point.accuracy, domainMax: chartMaxY))
                        )
                        .foregroundStyle(ds.success)
                        .interpolationMethod(.monotone)
                        .lineStyle(.init(lineWidth: 2.4, lineCap: .round, lineJoin: .round, dash: [6, 4]))
                    }

                    ForEach(chartPoints.filter { $0.second.isMultiple(of: 5) || $0.id == chartPoints.last?.id }) { point in
                        PointMark(
                            x: .value("Accuracy Second", point.second),
                            y: .value("Accuracy Dot", scaledAccuracy(point.accuracy, domainMax: chartMaxY))
                        )
                        .foregroundStyle(ds.success)
                        .symbolSize(28)
                    }

                    ForEach(performanceState.errorCountsBySecond.keys.sorted(), id: \.self) { second in
                        PointMark(
                            x: .value("Error Second", second),
                            y: .value("Error Dot", chartMaxY * 0.06)
                        )
                        .foregroundStyle(ds.error)
                        .symbolSize(18)
                    }
                }
                .chartXScale(domain: 0...Double(maxSecond + 1))
                .chartYScale(domain: 0...chartMaxY)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 5))
                    AxisMarks(position: .trailing, values: accuracyAxisValues) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                            .foregroundStyle(.clear)
                        AxisTick()
                            .foregroundStyle(ds.borderSubtle)
                        AxisValueLabel {
                            if let scaled = value.as(Double.self) {
                                Text("\(Int(((scaled / chartMaxY) * 100).rounded()))")
                                    .font(Typo.tooltip)
                                    .foregroundStyle(ds.tertiaryText)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 6))
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    let x: CGFloat
                                    if #available(macOS 14.0, *) {
                                        if let plotFrame = proxy.plotFrame {
                                            x = location.x - geo[plotFrame].origin.x
                                        } else {
                                            x = location.x
                                        }
                                    } else {
                                        let plotFrame = geo[proxy.plotAreaFrame]
                                        x = location.x - plotFrame.origin.x
                                    }
                                    if let second: Int = proxy.value(atX: x),
                                       chartPoints.contains(where: { $0.second == second }) {
                                        hoveredSecond = second
                                        hoveredChartLocation = location
                                    }
                                case .ended:
                                    hoveredSecond = nil
                                    hoveredChartLocation = nil
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                GeometryReader { overlayGeo in
                    if let hoveredSecond,
                       let point = chartPoints.first(where: { $0.second == hoveredSecond }),
                       let hoveredChartLocation {
                        HStack(spacing: Spacing.sm) {
                            Text("t=\(point.second)s")
                            Text("wpm \(Int(point.wpm))")
                            Text("acc \(Int(point.accuracy))%")
                            if point.errorCount > 0 { Text("err \(point.errorCount)") }
                        }
                        .font(Typo.tooltip)
                        .monospacedDigit()
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.sm / 2)
                        .background(ds.tooltipFill, in: RoundedRectangle(cornerRadius: CornerRadius.small))
                        .position(
                            x: clamped(hoveredChartLocation.x + 85, min: 90, max: overlayGeo.size.width - 90),
                            y: clamped(hoveredChartLocation.y - 18, min: 22, max: overlayGeo.size.height - 22)
                        )
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .padding(Spacing.lg)
        .background(DSCardBackground())
    }

    private func resultMetric(
        title: String,
        value: String,
        font: Font = Typo.displayMedium,
        countUp: Int? = nil,
        detail: String? = nil,
        detailColor: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxxs) {
            Text(title)
                .font(Typo.label)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let countUp {
                    AnimatedNumber(countUp, font: font)
                } else {
                    Text(value)
                        .font(font)
                        .monospacedDigit()
                }

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(Typo.caption)
                        .foregroundStyle(detailColor ?? ds.secondaryText)
                        .monospacedDigit()
                        .baselineOffset(8)
                }
            }
        }
    }

    private var resultPrimaryStatsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            resultMetric(
                title: "NET WPM",
                value: "\(netWPM())",
                font: Typo.displayLarge,
                countUp: netWPM(),
                detail: resultTelemetrySpeedDelta,
                detailColor: resultTelemetrySpeedDeltaColor
            )
            Text("Raw \(grossWPM()) WPM")
                .font(Typo.label)
                .foregroundStyle(.secondary)
            resultMetric(
                title: "ACCURACY",
                value: "\(accuracy())%",
                countUp: accuracy(),
                detail: resultTelemetryAccuracyDelta,
                detailColor: resultTelemetryAccuracyDeltaColor
            )
            Spacer(minLength: 0)
            resultMetric(title: "INCORRECT", value: "\(totalErrorCount)", font: Typo.displaySmall)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Spacing.md + Spacing.xxxs)
        .background(DSCardBackground())
    }

    private func resultMiniMetric(title: String, value: String, countUp: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm / 2) {
            Text(title)
                .font(Typo.label)
                .foregroundStyle(.secondary)
            if let countUp {
                AnimatedNumber(countUp, font: Typo.displaySmall)
            } else {
                Text(value)
                    .font(Typo.displaySmall)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Spacing.md)
        .background(DSCardBackground())
    }

    private var resultTelemetryStrip: some View {
        let currentKey = resultTelemetryFocusKey
        let currentStat = resultTelemetryCurrentStat

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.lg) {
                resultTelemetryLabel("Lesson set:")

                if resultTelemetryActiveKeys.isEmpty {
                    Text("No active alphabet was recorded for this session.")
                        .font(Typo.caption)
                        .foregroundStyle(ds.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(resultTelemetryActiveKeys, id: \.self) { key in
                                resultTelemetryKeyChip(
                                    key: key,
                                    isActive: true,
                                    isCurrent: currentKey == key
                                )
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: Spacing.lg) {
                resultTelemetryLabel("Current key:")

                if let currentKey {
                    HStack(alignment: .center, spacing: Spacing.md) {
                        resultTelemetryKeyChip(key: currentKey, isActive: true, isCurrent: true)

                        if let currentStat {
                            Text("Last speed: \(speedString(from: speedWPM(from: currentStat)))")
                                .font(Typo.caption)
                                .foregroundStyle(ds.primaryText)
                                .monospacedDigit()

                            Text("Top speed: \(speedString(from: bestObservedSpeedWPM(for: currentKey)))")
                                .font(Typo.caption)
                                .foregroundStyle(ds.primaryText)
                                .monospacedDigit()

                            Text("Accuracy: \(keyAccuracyString(for: currentStat))")
                                .font(Typo.caption)
                                .foregroundStyle(ds.secondaryText)
                                .monospacedDigit()
                        }

                        if let feedback = finishedLessonFeedback {
                            Text("Learning rate: \(lessonLearningRateString(feedback: feedback))")
                                .font(Typo.caption)
                                .foregroundStyle(ds.secondaryText)
                                .monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No focused key was recorded for this session.")
                        .font(Typo.caption)
                        .foregroundStyle(ds.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSCardBackground())
    }

    private func resultLessonInsightCard(feedback: AdaptiveLastLessonFeedback) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LESSON SIGNAL")
                .font(Typo.label)
                .foregroundStyle(.secondary)

            if let focus = feedback.focusedKey {
                Text("Focus \(focus.uppercased())")
                    .font(Typo.body)
                    .monospacedDigit()
            } else {
                Text("\(feedback.activeAlphabetSize) active keys")
                    .font(Typo.body)
                    .monospacedDigit()
            }

            if let digraph = feedback.topMissedDigraphs.first {
                Text("Miss \(digraph.pair) ×\(digraph.count)")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if let miss = feedback.topMisses.first {
                Text("Misses \(miss.key.uppercased()) ×\(miss.missCount)")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else if let correction = feedback.correctionHotspots.first {
                Text("Fix \(correction.pair) ×\(correction.count)")
                .font(Typo.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            } else if let transition = feedback.topTransitions.first {
                Text("Slow \(transition.fromKey.uppercased())\(transition.toKey.uppercased())")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("Clean run")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
            }

            if let correction = feedback.correctionHotspots.first {
                Text("Fix \(correction.pair) ×\(correction.count)")
                    .font(Typo.caption)
                    .foregroundStyle(ds.tertiaryText)
                    .monospacedDigit()
            } else if feedback.stepCount > 0 {
                Text("\(feedback.stepCount) steps tracked")
                    .font(Typo.caption)
                    .foregroundStyle(ds.tertiaryText)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Spacing.md)
        .background(DSCardBackground())
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: Spacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(Typo.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func resultTelemetryLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(ds.primaryText)
            .frame(width: 94, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func resultTelemetryKeyChip(key: String, isActive: Bool, isCurrent: Bool) -> some View {
        let fill = isCurrent
            ? ds.success.opacity(0.58)
            : (isActive ? ds.success.opacity(0.42) : ds.surfaceElevated)

        return Text(key.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(isActive || isCurrent ? ds.primaryText : ds.secondaryText)
            .monospaced()
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous)
                    .stroke(isCurrent ? ds.border : ds.borderSubtle, lineWidth: isCurrent ? 1.2 : 0.8)
            )
    }

    private func speedWPM(from stat: AdaptiveSessionKeyStat) -> Double? {
        guard let time = stat.timeToTypeMS, time.isFinite, time > 0 else { return nil }
        return 60_000 / (time * 5)
    }

    private func bestObservedSpeedWPM(for key: String) -> Double? {
        resultTelemetryPayload?.keyStats
            .filter { $0.key == key }
            .compactMap(speedWPM(from:))
            .max()
    }

    private func speedString(from speed: Double?) -> String {
        guard let speed, speed.isFinite else { return "—" }
        return String(format: "%.1fwpm", speed)
    }

    private func scaledAccuracy(_ accuracy: Double, domainMax: Double) -> Double {
        guard domainMax > 0 else { return 0 }
        return (max(0, min(100, accuracy)) / 100) * domainMax
    }

    private func accuracyAxisMarks(for domainMax: Double) -> [Double] {
        [0, 25, 50, 75, 100].map { (Double($0) / 100) * domainMax }
    }

    private func rollingSessionChartPoints(from points: [SessionMetricPoint], window: Int = 5) -> [SessionChartPoint] {
        guard !points.isEmpty else { return [] }

        return points.indices.map { index in
            let lowerBound = max(0, index - window)
            let current = points[index]
            let baseline = points[lowerBound]
            let elapsedSeconds = max(1, current.second - baseline.second)
            let correctDelta = max(0, current.correctCharsSnapshot - baseline.correctCharsSnapshot)
            let attemptDelta = max(0, current.attemptedCharsSnapshot - baseline.attemptedCharsSnapshot)
            let rollingWPM = (Double(correctDelta) / 5.5) / Double(elapsedSeconds) * 60
            let rollingAccuracy = attemptDelta > 0
                ? (Double(correctDelta) / Double(attemptDelta)) * 100
                : current.accuracy

            return SessionChartPoint(
                second: current.second,
                wpm: rollingWPM,
                accuracy: rollingAccuracy,
                errorCount: current.errorCount
            )
        }
    }

    private func resultSummaryDeltaString(
        current: Double?,
        baseline: Double?,
        suffix: String,
        decimalPlaces: Int = 0
    ) -> String? {
        guard let current, current.isFinite else { return nil }
        guard let baseline, baseline.isFinite else { return nil }
        let delta = current - baseline
        let roundingThreshold = pow(10.0, -Double(decimalPlaces)) / 2.0
        guard abs(delta) >= roundingThreshold else { return nil }
        return String(format: "%+.\(decimalPlaces)f%@", delta, suffix)
    }

    private func resultSummaryDeltaColor(current: Double?, baseline: Double?) -> Color {
        guard let current, current.isFinite else { return ds.secondaryText }
        guard let baseline, baseline.isFinite else { return ds.secondaryText }
        let delta = current - baseline
        guard abs(delta) >= 0.5 else { return ds.secondaryText }
        return delta > 0 ? ds.success : ds.error
    }

    private var resultTelemetrySpeedDelta: String? {
        resultSummaryDeltaString(
            current: Double(netWPM()),
            baseline: resultSummaryBaselineSession?.wpm,
            suffix: "wpm"
        )
    }

    private var resultTelemetrySpeedDeltaColor: Color {
        resultSummaryDeltaColor(
            current: Double(netWPM()),
            baseline: resultSummaryBaselineSession?.wpm
        )
    }

    private var resultTelemetryAccuracyDelta: String? {
        resultSummaryDeltaString(
            current: Double(accuracy()),
            baseline: resultSummaryBaselineSession?.accuracy,
            suffix: "%"
        )
    }

    private var resultTelemetryAccuracyDeltaColor: Color {
        resultSummaryDeltaColor(
            current: Double(accuracy()),
            baseline: resultSummaryBaselineSession?.accuracy
        )
    }

    private func keyAccuracyString(for stat: AdaptiveSessionKeyStat) -> String {
        let attempts = stat.hitCount + stat.missCount
        guard attempts > 0 else { return "—" }
        let accuracy = Double(stat.hitCount) / Double(attempts)
        return String(format: "%.0f%%", accuracy * 100)
    }

    private func lessonLearningRateString(feedback: AdaptiveLastLessonFeedback) -> String {
        if let transition = feedback.topTransitions.first {
            return "\(Int(transition.averageTimeMS.rounded()))ms"
        }
        if let miss = feedback.topMisses.first {
            return "miss \(miss.key.uppercased()) ×\(miss.missCount)"
        }
        return "Uncertain"
    }

    private func clamped(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private var shouldAppendContinuationText: Bool {
        guard sessionSettings.isTestMode else { return false }
        switch sessionSettings.testLengthMode {
        case .time, .continuous:
            return true
        case .words:
            return false
        }
    }

    private func appendContinuationText() {
        let sourceWords = testSourceWords(settings: sessionSettings)
        let nextCount: Int
        switch sessionSettings.testLengthMode {
        case .time:
            nextCount = max(60, sessionSettings.timeLimit * 2)
        case .continuous:
            nextCount = 120
        case .words:
            nextCount = max(10, sessionSettings.wordLimit)
        }

        let nextWords: [String]
        switch sessionSettings.testContentMode {
        case .numbers:
            nextWords = generateNumberFragmentWords(settings: sessionSettings)
        case .customWords:
            nextWords = generateCustomFragmentWords(settings: sessionSettings)
        case .commonWords, .codeWords:
            nextWords = makeDecoratedTestWords(
                from: sourceWords,
                count: nextCount,
                settings: sessionSettings
            )
        }
        guard !nextWords.isEmpty else {
            finishTest(at: Date())
            return
        }

        let suffix = normalizeLongWords(in: nextWords.joined(separator: " "))
        let separator = textToType.hasSuffix(" ") ? "" : " "
        activeSessionContext = activeSessionContext?.appendingText(separator + suffix)
    }

    private func normalizeLongWords(in text: String, chunkSize: Int = 20) -> String {
        text
            .split(separator: " ")
            .flatMap { word -> [String] in
                let raw = String(word)
                guard raw.count > chunkSize else { return [raw] }
                var chunks: [String] = []
                var cursor = raw.startIndex
                while cursor < raw.endIndex {
                    let next = raw.index(cursor, offsetBy: chunkSize, limitedBy: raw.endIndex) ?? raw.endIndex
                    chunks.append(String(raw[cursor..<next]))
                    cursor = next
                }
                return chunks
            }
            .joined(separator: " ")
    }

    private func shouldAcceptTypedCharacter(_ typedCharacter: Character) -> Bool {
        let mode = sessionSettings.errorMode
        guard mode != .off else { return true }
        guard let expectedChar = characterAt(offset: userInput.count, in: textToType) else { return false }

        if mode == .letter {
            return charactersMatchForTyping(typedCharacter, expectedChar)
        }

        if mode == .word {
            if typedCharacter == " " {
                guard expectedChar == " " else { return false }
                let wordIndex = userInput.filter { $0 == " " }.count
                let expectedWords = textToType.split(separator: " ")
                let currentExpectedWord = wordIndex < expectedWords.count ? String(expectedWords[wordIndex]) : ""
                let currentTypedWord = userInput.split(separator: " ").last.map(String.init) ?? ""
                return currentTypedWord.lowercased() == currentExpectedWord.lowercased()
            }
            return expectedChar != " "
        }

        return true
    }

    private func allowsTypingModifiers(_ modifiers: EventModifiers) -> Bool {
        let allowed: EventModifiers = [.shift, .capsLock]
        return modifiers.intersection(allowed) == modifiers
    }

    private func charactersMatchForTyping(_ typed: Character, _ expected: Character) -> Bool {
        let typedString = String(typed)
        let expectedString = String(expected)
        if typedString.count == 1, expectedString.count == 1,
           typedString.rangeOfCharacter(from: .letters) != nil,
           expectedString.rangeOfCharacter(from: .letters) != nil {
            return typedString.lowercased() == expectedString.lowercased()
        }
        return typed == expected
    }
}

private struct NoiseTextureBackground: View {
    @Environment(\.ds) private var ds
    @Environment(\.colorScheme) private var colorScheme

    let intensity: Double
    let usesReducedEffects: Bool

    private var clampedIntensity: Double {
        max(0, intensity)
    }

    private var secondaryBlurRadius: CGFloat {
        usesReducedEffects ? 14 : 28
    }

    var body: some View {
        ZStack {
            FrostedWindowBackdrop()

            Rectangle()
                .fill(ds.background.opacity(colorScheme == .dark ? 0.28 : 0.16))
                .ignoresSafeArea()
                .allowsHitTesting(false)

            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.04 : 0.03),
                    Color.clear,
                    Color.black.opacity(colorScheme == .dark ? 0.10 : 0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.plusLighter)

            LinearGradient(
                colors: [
                    Color.black.opacity(colorScheme == .dark ? 0.16 : 0.08),
                    Color.black.opacity(colorScheme == .dark ? 0.08 : 0.03),
                    Color.black.opacity(colorScheme == .dark ? 0.20 : 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: secondaryBlurRadius)

            // 1. Arc-style deep vignette
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.clear,
                    Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08)
                ]),
                center: .center,
                startRadius: 200,
                endRadius: 900
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.02 : 0.015),
                            Color.black.opacity(colorScheme == .dark ? 0.05 : 0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(colorScheme == .dark ? .screen : .multiply)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if !usesReducedEffects, #available(macOS 14.0, *), clampedIntensity > 0 {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.10),
                                Color.black.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .colorEffect(ShaderLibrary.filmGrain())
                    .blendMode(.softLight)
                    .opacity(ds.noiseOverlayOpacity * clampedIntensity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct ResultIconButtonLabel: View {
    @Environment(\.ds) private var ds

    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(ds.secondaryText)
            .frame(width: 34, height: 34)
        .minHitArea(44)
    }
}

private struct DSResultHoverBackground: View {
    @Environment(\.ds) private var ds

    var body: some View {
        RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
            .fill(.ultraThinMaterial.opacity(0.85))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                    .stroke(ds.border, lineWidth: 1)
            )
            .shadow(color: ds.shadowColor.opacity(0.18), radius: 8, y: 3)
    }
}

#if os(macOS)
private struct FrostedWindowBackdrop: NSViewRepresentable {
    @Environment(\.ds) private var ds

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? .windowBackground : ds.windowMaterial
        view.state = .active
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? .windowBackground : ds.windowMaterial
        view.state = .active
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        DispatchQueue.main.async {
            if let window = view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = true
                window.contentView?.wantsLayer = true
                window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
                if let contentSuperview = window.contentView?.superview {
                    contentSuperview.wantsLayer = true
                    contentSuperview.layer?.backgroundColor = NSColor.clear.cgColor
                }
            }
        }
    }
}
#else
private struct FrostedWindowBackdrop: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
    }
}
#endif

private struct SessionMetricPoint: Identifiable {
    var id: Int { second }
    let second: Int
    let wpm: Double
    let accuracy: Double
    let errorCount: Int
    let correctCharsSnapshot: Int
    let attemptedCharsSnapshot: Int
}

private struct SessionChartPoint: Identifiable {
    var id: Int { second }
    let second: Int
    let wpm: Double
    let accuracy: Double
    let errorCount: Int
}

private struct TypingSessionPerformanceState {
    var metricPoints: [SessionMetricPoint] = []
    var errorSeconds: Set<Int> = []
    var errorCountsBySecond: [Int: Int] = [:]
    var lastErrorCount = 0
    var correctCharsCount = 0
    var incorrectCharsCount = 0
    var correctWordsCountSnapshot = 0
    var strictRejectCount = 0

    var totalErrorCount: Int {
        incorrectCharsCount + strictRejectCount
    }

    var hasProgress: Bool {
        correctCharsCount > 0 || incorrectCharsCount > 0 || strictRejectCount > 0
    }

    var consistencyRate: Int {
        let speeds = metricPoints.map(\.wpm)
        guard speeds.count > 1 else { return 100 }
        let mean = speeds.reduce(0, +) / Double(speeds.count)
        guard mean > 0 else { return 0 }
        let variance = speeds.map { pow($0 - mean, 2) }.reduce(0, +) / Double(speeds.count)
        let stdDev = sqrt(variance)
        return max(0, min(100, Int((1 - (stdDev / mean)) * 100)))
    }

    mutating func reset() {
        metricPoints = []
        errorSeconds = []
        errorCountsBySecond = [:]
        lastErrorCount = 0
        correctCharsCount = 0
        incorrectCharsCount = 0
        correctWordsCountSnapshot = 0
        strictRejectCount = 0
    }

    func accuracy(inputCount: Int) -> Int {
        guard inputCount > 0 else { return 100 }
        let score = Double(correctCharsCount) / Double(inputCount)
        return Int((score * 100).rounded(.toNearestOrAwayFromZero))
    }

    func grossWPM(inputCount: Int, duration: TimeInterval) -> Int {
        guard duration > 0 else { return 0 }
        let avgEnglishWordLength = 5.5
        let rawKeystrokes = inputCount + strictRejectCount
        let wordsTyped = Double(rawKeystrokes) / avgEnglishWordLength
        return Int((wordsTyped / duration) * 60)
    }

    func netWPM(duration: TimeInterval) -> Int {
        guard duration > 0 else { return 0 }
        let avgEnglishWordLength = 5.5
        let wordsTyped = Double(correctCharsCount) / avgEnglishWordLength
        return Int((wordsTyped / duration) * 60)
    }

    mutating func noteTotalErrors(_ totalErrors: Int, atSecond second: Int?) {
        if totalErrors > lastErrorCount, let second {
            let delta = totalErrors - lastErrorCount
            errorSeconds.insert(second)
            errorCountsBySecond[second, default: 0] += delta
        }
        lastErrorCount = totalErrors
    }

    mutating func noteStrictReject(atSecond second: Int?) {
        strictRejectCount += 1
        lastErrorCount = totalErrorCount
        if let second {
            errorSeconds.insert(second)
            errorCountsBySecond[second, default: 0] += 1
        }
    }

    mutating func recordMetricPoint(_ point: SessionMetricPoint) {
        if metricPoints.last?.second == point.second {
            metricPoints[metricPoints.count - 1] = point
        } else {
            metricPoints.append(point)
        }
    }
}

private struct TypingSessionContext: Equatable {
    let id: UUID
    let createdAt: Date
    let settings: AppSettings
    let lesson: AdaptiveGeneratedLesson

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        settings: AppSettings,
        lesson: AdaptiveGeneratedLesson
    ) {
        self.id = id
        self.createdAt = createdAt
        self.settings = settings
        self.lesson = lesson
    }

    var textToType: String {
        lesson.text
    }

    func replacingLesson(_ lesson: AdaptiveGeneratedLesson) -> TypingSessionContext {
        TypingSessionContext(
            id: id,
            createdAt: createdAt,
            settings: settings,
            lesson: lesson
        )
    }

    func appendingText(_ suffix: String) -> TypingSessionContext {
        replacingLesson(
            AdaptiveGeneratedLesson(
                text: lesson.text + suffix,
                lessonState: lesson.lessonState
            )
        )
    }
}

private struct AdaptiveHistoryTimeline {
    var storedSessions: [TrainingProfileSession]
    var pendingSession: TrainingProfileSession?

    var sessions: [TrainingProfileSession] {
        let relevant = storedSessions.filter(\.contributesToAdaptiveProfile)
        guard let pendingSession else {
            return relevant.sorted { $0.date < $1.date }
        }

        let pendingKey = pendingSession.deduplicationKey
        if relevant.contains(where: { $0.deduplicationKey == pendingKey }) {
            return relevant.sorted { $0.date < $1.date }
        }

        return (relevant + [pendingSession]).sorted { $0.date < $1.date }
    }

    var snapshots: [AdaptiveHistoryResult] {
        sessions.map(\.adaptiveHistoryResult)
    }
}

private struct TypingLayoutRefreshID: Equatable {
    let width: Int
    let textToType: String
    let userInput: String
    let settings: AppSettings
    let testFinished: Bool
}

private struct TypingLayoutCacheKey: Equatable {
    let width: Int
    let textToType: String
    let fontSize: Double
    let lineHeight: Double
    let letterSpacing: Double
    let caretStyle: CaretStyle
    let themeRaw: String
    let colorScheme: ColorScheme
    let upcomingTextOpacity: Double
    let smoothCaret: Bool
    let caretColorRed: Double
    let caretColorGreen: Double
    let caretColorBlue: Double
}

private struct TypingLayoutSnapshot {
    #if os(macOS)
    /// Retains the text storage so the layout manager can draw glyphs.
    /// Without this, ARC deallocates the storage after typingSnapshot() returns,
    /// leaving layoutManager.textStorage nil and rendering invisible text.
    let textStorage: NSTextStorage?
    let layoutManager: NSLayoutManager?
    let textContainer: NSTextContainer?
    #endif
    let caretOrigin: CGPoint
    let contentOffsetX: CGFloat
    let viewportOffsetY: CGFloat
    let viewportHeight: CGFloat
    let fullTextHeight: CGFloat

    #if os(macOS)
    static let zero = TypingLayoutSnapshot(
        textStorage: nil,
        layoutManager: nil,
        textContainer: nil,
        caretOrigin: .zero,
        contentOffsetX: 0,
        viewportOffsetY: 0,
        viewportHeight: 1,
        fullTextHeight: 1
    )
    #else
    static let zero = TypingLayoutSnapshot(
        caretOrigin: .zero,
        contentOffsetX: 0,
        viewportOffsetY: 0,
        viewportHeight: 1,
        fullTextHeight: 1
    )
    #endif
}

#if os(macOS)
@MainActor
private final class SoundEffectPool {
    private let maxPlayersPerSound = 4
    private var playersByName: [String: [AVAudioPlayer]] = [:]

    func play(url: URL, name: String, volume: Float) {
        pruneIdlePlayers(for: name)

        if let index = playersByName[name]?.firstIndex(where: { !$0.isPlaying }) {
            let player = playersByName[name]![index]
            player.volume = volume
            player.currentTime = 0
            player.play()
            return
        }

        if let existingPlayers = playersByName[name], existingPlayers.count >= maxPlayersPerSound {
            let player = existingPlayers[0]
            player.stop()
            player.currentTime = 0
            player.volume = volume
            player.play()
            return
        }

        let fileTypeHint = UTType(filenameExtension: url.pathExtension)?.identifier
        let player: AVAudioPlayer?
        if let fileTypeHint {
            player = try? AVAudioPlayer(contentsOf: url, fileTypeHint: fileTypeHint)
        } else {
            player = try? AVAudioPlayer(contentsOf: url)
        }
        guard let player else { return }
        player.volume = volume
        player.prepareToPlay()
        player.play()
        playersByName[name, default: []].append(player)
    }

    private func pruneIdlePlayers(for name: String) {
        playersByName[name]?.removeAll(where: { !$0.isPlaying })
        if playersByName[name]?.isEmpty == true {
            playersByName[name] = nil
        }
    }
}

private struct TypingLayoutRenderer: NSViewRepresentable {
    let snapshot: TypingLayoutSnapshot

    func makeNSView(context: Context) -> TypingLayoutRenderView {
        let view = TypingLayoutRenderView()
        view.update(with: snapshot)
        return view
    }

    func updateNSView(_ nsView: TypingLayoutRenderView, context: Context) {
        nsView.update(with: snapshot)
    }
}

private final class TypingLayoutRenderView: NSView {
    private var snapshot: TypingLayoutSnapshot = .zero

    override var isFlipped: Bool {
        true
    }

    override var isOpaque: Bool {
        false
    }

    func update(with snapshot: TypingLayoutSnapshot) {
        self.snapshot = snapshot
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let layoutManager = snapshot.layoutManager else { return }

        let glyphRange = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
    }
}
#else
private struct TypingLayoutRenderer: View {
    let snapshot: TypingLayoutSnapshot

    var body: some View {
        Color.clear
    }
}
#endif

private extension Array {
    func cycled(to count: Int) -> [Element] {
        guard !isEmpty, count > 0 else { return [] }
        return (0..<count).map { self[$0 % self.count] }
    }
}
