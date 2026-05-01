import Foundation

struct AdaptiveSessionPayload: Codable, Equatable, Sendable {
    private enum PayloadCodingKeys: String, CodingKey {
        case lesson
        case keyStats
        case transitions
        case telemetry
    }

    var lesson: AdaptiveLessonState
    var keyStats: [AdaptiveSessionKeyStat]
    var transitions: [AdaptiveSessionTransitionStat]
    var telemetry: AdaptiveSessionTelemetry?

    nonisolated static let empty = AdaptiveSessionPayload(
        lesson: .empty,
        keyStats: [],
        transitions: [],
        telemetry: nil
    )

    nonisolated init(
        lesson: AdaptiveLessonState,
        keyStats: [AdaptiveSessionKeyStat],
        transitions: [AdaptiveSessionTransitionStat],
        telemetry: AdaptiveSessionTelemetry? = nil
    ) {
        self.lesson = lesson
        self.keyStats = keyStats
        self.transitions = transitions
        self.telemetry = telemetry
    }

    nonisolated static func == (lhs: AdaptiveSessionPayload, rhs: AdaptiveSessionPayload) -> Bool {
        lhs.lesson == rhs.lesson &&
        lhs.keyStats == rhs.keyStats &&
        lhs.transitions == rhs.transitions &&
        lhs.telemetry == rhs.telemetry
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: PayloadCodingKeys.self)
        lesson = try container.decode(AdaptiveLessonState.self, forKey: .lesson)
        keyStats = try container.decode([AdaptiveSessionKeyStat].self, forKey: .keyStats)
        transitions = try container.decode([AdaptiveSessionTransitionStat].self, forKey: .transitions)
        telemetry = try container.decodeIfPresent(AdaptiveSessionTelemetry.self, forKey: .telemetry)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: PayloadCodingKeys.self)
        try container.encode(lesson, forKey: .lesson)
        try container.encode(keyStats, forKey: .keyStats)
        try container.encode(transitions, forKey: .transitions)
        try container.encodeIfPresent(telemetry, forKey: .telemetry)
    }
}

struct AdaptiveSessionKeyStat: Codable, Equatable, Sendable {
    var key: String
    var hitCount: Int
    var missCount: Int
    var timeToTypeMS: Double?

    nonisolated static func == (lhs: AdaptiveSessionKeyStat, rhs: AdaptiveSessionKeyStat) -> Bool {
        lhs.key == rhs.key &&
        lhs.hitCount == rhs.hitCount &&
        lhs.missCount == rhs.missCount &&
        lhs.timeToTypeMS == rhs.timeToTypeMS
    }
}

struct AdaptiveSessionTransitionStat: Codable, Equatable, Sendable {
    var fromKey: String
    var toKey: String
    var count: Int
    var averageTimeMS: Double

    nonisolated static func == (lhs: AdaptiveSessionTransitionStat, rhs: AdaptiveSessionTransitionStat) -> Bool {
        lhs.fromKey == rhs.fromKey &&
        lhs.toKey == rhs.toKey &&
        lhs.count == rhs.count &&
        lhs.averageTimeMS == rhs.averageTimeMS
    }
}

enum AdaptiveSessionStepKind: String, Codable, Equatable, Sendable {
    case accepted
    case rejected
    case corrected
}

struct AdaptiveSessionStep: Codable, Equatable, Sendable, Identifiable {
    var id: Int
    var kind: AdaptiveSessionStepKind
    var expectedKey: String?
    var typedKey: String?
    var cursorIndex: Int
    var timestampMS: Int
    var previousExpectedKey: String?

    nonisolated static func == (lhs: AdaptiveSessionStep, rhs: AdaptiveSessionStep) -> Bool {
        lhs.id == rhs.id &&
        lhs.kind == rhs.kind &&
        lhs.expectedKey == rhs.expectedKey &&
        lhs.typedKey == rhs.typedKey &&
        lhs.cursorIndex == rhs.cursorIndex &&
        lhs.timestampMS == rhs.timestampMS &&
        lhs.previousExpectedKey == rhs.previousExpectedKey
    }
}

struct AdaptiveSessionDigraphStat: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(previousKey ?? "_")|->|\(key)" }

    var key: String
    var previousKey: String?
    var count: Int

    var pair: String {
        if let previousKey {
            return previousKey.uppercased() + key.uppercased()
        }
        return key.uppercased()
    }

    nonisolated static func == (lhs: AdaptiveSessionDigraphStat, rhs: AdaptiveSessionDigraphStat) -> Bool {
        lhs.key == rhs.key &&
        lhs.previousKey == rhs.previousKey &&
        lhs.count == rhs.count
    }
}

struct AdaptiveSessionCorrectionStat: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(previousKey ?? "_")|~>|\(key)" }

    var key: String
    var previousKey: String?
    var count: Int

    var pair: String {
        if let previousKey {
            return previousKey.uppercased() + key.uppercased()
        }
        return key.uppercased()
    }

    nonisolated static func == (lhs: AdaptiveSessionCorrectionStat, rhs: AdaptiveSessionCorrectionStat) -> Bool {
        lhs.key == rhs.key &&
        lhs.previousKey == rhs.previousKey &&
        lhs.count == rhs.count
    }
}

struct AdaptiveSessionTelemetry: Codable, Equatable, Sendable {
    var steps: [AdaptiveSessionStep]
    var missedDigraphs: [AdaptiveSessionDigraphStat]
    var correctionHotspots: [AdaptiveSessionCorrectionStat]

    nonisolated static let empty = AdaptiveSessionTelemetry(
        steps: [],
        missedDigraphs: [],
        correctionHotspots: []
    )

    nonisolated init(
        steps: [AdaptiveSessionStep],
        missedDigraphs: [AdaptiveSessionDigraphStat],
        correctionHotspots: [AdaptiveSessionCorrectionStat]
    ) {
        self.steps = steps
        self.missedDigraphs = missedDigraphs
        self.correctionHotspots = correctionHotspots
    }

    nonisolated static func == (lhs: AdaptiveSessionTelemetry, rhs: AdaptiveSessionTelemetry) -> Bool {
        lhs.steps == rhs.steps &&
        lhs.missedDigraphs == rhs.missedDigraphs &&
        lhs.correctionHotspots == rhs.correctionHotspots
    }

    nonisolated static func build(from steps: [AdaptiveSessionStep]) -> AdaptiveSessionTelemetry {
        var missedDigraphs: [String: AdaptiveSessionDigraphStat] = [:]
        var correctionHotspots: [String: AdaptiveSessionCorrectionStat] = [:]

        for step in steps {
            switch step.kind {
            case .accepted:
                continue
            case .rejected:
                guard let key = step.expectedKey, key != " " else { continue }
                let identifier = "\(step.previousExpectedKey ?? "_")|->|\(key)"
                var stat = missedDigraphs[identifier, default: AdaptiveSessionDigraphStat(key: key, previousKey: step.previousExpectedKey, count: 0)]
                stat.count += 1
                missedDigraphs[identifier] = stat
            case .corrected:
                guard let key = step.expectedKey, key != " " else { continue }
                let identifier = "\(step.previousExpectedKey ?? "_")|~>|\(key)"
                var stat = correctionHotspots[identifier, default: AdaptiveSessionCorrectionStat(key: key, previousKey: step.previousExpectedKey, count: 0)]
                stat.count += 1
                correctionHotspots[identifier] = stat
            }
        }

        return AdaptiveSessionTelemetry(
            steps: steps,
            missedDigraphs: missedDigraphs.values.sorted {
                if $0.count == $1.count {
                    return ($0.previousKey ?? "", $0.key) < ($1.previousKey ?? "", $1.key)
                }
                return $0.count > $1.count
            },
            correctionHotspots: correctionHotspots.values.sorted {
                if $0.count == $1.count {
                    return ($0.previousKey ?? "", $0.key) < ($1.previousKey ?? "", $1.key)
                }
                return $0.count > $1.count
            }
        )
    }
}

struct AdaptiveLessonState: Codable, Equatable, Sendable {
    var activeAlphabet: [String]
    var focusedKey: String?
    var forcedKeys: [String]
    var targetWPM: Double
    var source: String

    nonisolated static let empty = AdaptiveLessonState(
        activeAlphabet: [],
        focusedKey: nil,
        forcedKeys: [],
        targetWPM: AdaptiveTypingEngine.defaults.targetWPM,
        source: "random"
    )

    nonisolated static func == (lhs: AdaptiveLessonState, rhs: AdaptiveLessonState) -> Bool {
        lhs.activeAlphabet == rhs.activeAlphabet &&
        lhs.focusedKey == rhs.focusedKey &&
        lhs.forcedKeys == rhs.forcedKeys &&
        lhs.targetWPM == rhs.targetWPM &&
        lhs.source == rhs.source
    }
}

struct AdaptiveGeneratedLesson: Equatable, Sendable {
    var text: String
    var lessonState: AdaptiveLessonState
}

struct AdaptiveHistoryResult: Equatable, Sendable {
    var date: Date
    var wpm: Double
    var accuracy: Double
    var adaptivePayload: AdaptiveSessionPayload?
    var contributesToAdaptiveProfile: Bool

    nonisolated init(
        date: Date,
        wpm: Double,
        accuracy: Double,
        adaptivePayload: AdaptiveSessionPayload?,
        contributesToAdaptiveProfile: Bool
    ) {
        self.date = date
        self.wpm = wpm
        self.accuracy = accuracy
        self.adaptivePayload = adaptivePayload
        self.contributesToAdaptiveProfile = contributesToAdaptiveProfile
    }
}

struct AdaptiveKeyProfile: Identifiable, Equatable, Sendable {
    var id: String { key }

    var key: String
    var samples: Int
    var hits: Int
    var misses: Int
    var latestTimeMS: Double?
    var bestTimeMS: Double?
    var accuracy: Double
    var confidence: Double?
    var bestConfidence: Double?
    var needScore: Double
    var isIncluded: Bool
    var isFocused: Bool
    var isForced: Bool
}

struct AdaptiveForecast: Equatable, Sendable {
    var certainty: Double
    var learningRateCPMPerLesson: Double
    var remainingLessons: Int?
}

struct AdaptiveKeyboardSnapshot: Equatable, Sendable {
    var homeRowRatio: Double
    var topRowRatio: Double
    var bottomRowRatio: Double
    var sameHandRatio: Double
    var sameFingerRatio: Double
    var keyIntensity: [String: Double]
}

struct AdaptiveTransitionInsight: Identifiable, Equatable, Sendable {
    var id: String { "\(fromKey)->\(toKey)" }

    var fromKey: String
    var toKey: String
    var count: Int
    var averageTimeMS: Double
}

struct AdaptiveAnalysisSnapshot: Equatable, Sendable {
    var averageWPM: Double
    var averageAccuracy: Double
    var sessions: Int
    var bestWPM: Double
    var currentLesson: AdaptiveLessonState
    var activeAlphabetSize: Int
    var readiness: Double
    var allKeys: [AdaptiveKeyProfile]
    var weakestKeys: [AdaptiveKeyProfile]
    var strongestKeys: [AdaptiveKeyProfile]
    var keyboard: AdaptiveKeyboardSnapshot
    var forecast: AdaptiveForecast?
    var transitions: [AdaptiveTransitionInsight]

    nonisolated static let empty = AdaptiveAnalysisSnapshot(
        averageWPM: 0,
        averageAccuracy: 0,
        sessions: 0,
        bestWPM: 0,
        currentLesson: .empty,
        activeAlphabetSize: 0,
        readiness: 0,
        allKeys: [],
        weakestKeys: [],
        strongestKeys: [],
        keyboard: AdaptiveKeyboardSnapshot(
            homeRowRatio: 0,
            topRowRatio: 0,
            bottomRowRatio: 0,
            sameHandRatio: 0,
            sameFingerRatio: 0,
            keyIntensity: [:]
        ),
        forecast: nil,
        transitions: []
    )
}

struct AdaptiveLessonGenerationContext: Equatable, Sendable {
    var keyProfiles: [AdaptiveKeyProfile]
    var lessonState: AdaptiveLessonState
    var transitionNeedByPair: [String: Double]

    nonisolated static let empty = AdaptiveLessonGenerationContext(
        keyProfiles: [],
        lessonState: .empty,
        transitionNeedByPair: [:]
    )
}

struct AdaptiveDerivedTrainingSnapshot: Equatable, Sendable {
    var analysis: AdaptiveAnalysisSnapshot
    var lessonGenerationContext: AdaptiveLessonGenerationContext
}

struct AdaptiveTypingDefaults: Sendable {
    var targetWPM: Double = 35
    var minimumAlphabetSize: Int = 6
    var recoverKeys: Bool = false
    var smoothingFactor: Double = 0.1
    var minimumWordLength: Int = 3
    var maximumWordLength: Int = 10
    var defaultLessonLength: Double = 0.0
    var defaultRepeatWords: Int = 1
}

struct AdaptiveTrainingConfiguration: Equatable, Sendable {
    var targetWPM: Double
    var minimumAlphabetSize: Int
    var alphabetExpansion: Double
    var recoverKeys: Bool
    var naturalWords: Bool
    var unlockStrategy: AdaptiveUnlockStrategy
    var keyboardLayout: KeyboardLayoutOption
    var lessonLength: Double
    var repeatWords: Int
    var capitalsProbability: Double
    var punctuationProbability: Double
    var smoothingFactor: Double
    var minimumWordLength: Int
    var maximumWordLength: Int

    nonisolated init(settings: AppSettings) {
        let defaults = AdaptiveTypingEngine.defaults
        self.targetWPM = settings.adaptiveTargetWPM
        self.minimumAlphabetSize = defaults.minimumAlphabetSize
        self.alphabetExpansion = settings.adaptiveAlphabetScale
        self.recoverKeys = settings.adaptiveRecoverKeys
        self.naturalWords = settings.adaptiveNaturalWords
        self.unlockStrategy = settings.adaptiveUnlockStrategy
        self.keyboardLayout = settings.keyboardLayout
        self.lessonLength = settings.lessonLength
        self.repeatWords = settings.repeatWords
        self.capitalsProbability = settings.capitalsProbability
        self.punctuationProbability = settings.punctuationProbability
        self.smoothingFactor = defaults.smoothingFactor
        self.minimumWordLength = defaults.minimumWordLength
        self.maximumWordLength = defaults.maximumWordLength
    }
}

struct AdaptiveSessionRecorder: Sendable {
    private struct AcceptedEvent: Sendable {
        var expected: String
        var typed: String
        var timestamp: Date
        var cursorIndex: Int
    }

    private struct RejectedEvent: Sendable {
        var expected: String
        var timestamp: Date
        var cursorIndex: Int
    }

    private var acceptedEvents: [AcceptedEvent] = []
    private var rejectedEvents: [RejectedEvent] = []
    private var sessionOrigin: Date?
    private var stepEvents: [AdaptiveSessionStep] = []

    mutating func reset() {
        acceptedEvents.removeAll(keepingCapacity: true)
        rejectedEvents.removeAll(keepingCapacity: true)
        stepEvents.removeAll(keepingCapacity: true)
        sessionOrigin = nil
    }

    mutating func recordAccepted(expected: Character, typed: Character, at date: Date, cursorIndex: Int? = nil) {
        guard let expectedSymbol = AdaptiveTypingEngine.normalizedSymbol(for: expected) else { return }
        let typedSymbol = AdaptiveTypingEngine.normalizedSymbol(for: typed) ?? String(typed)
        let resolvedCursorIndex = max(0, cursorIndex ?? acceptedEvents.count)
        let previousExpected = previousExpectedKey(before: resolvedCursorIndex)
        acceptedEvents.append(
            AcceptedEvent(
                expected: expectedSymbol,
                typed: typedSymbol,
                timestamp: date,
                cursorIndex: resolvedCursorIndex
            )
        )
        recordStep(
            kind: .accepted,
            expectedKey: expectedSymbol,
            typedKey: typedSymbol,
            cursorIndex: resolvedCursorIndex,
            previousExpectedKey: previousExpected,
            at: date
        )
    }

    mutating func recordRejected(expected: Character, at date: Date, cursorIndex: Int? = nil) {
        guard let expectedSymbol = AdaptiveTypingEngine.normalizedSymbol(for: expected) else { return }
        let resolvedCursorIndex = max(0, cursorIndex ?? acceptedEvents.count)
        let previousExpected = previousExpectedKey(before: resolvedCursorIndex)
        rejectedEvents.append(
            RejectedEvent(
                expected: expectedSymbol,
                timestamp: date,
                cursorIndex: resolvedCursorIndex
            )
        )
        recordStep(
            kind: .rejected,
            expectedKey: expectedSymbol,
            typedKey: nil,
            cursorIndex: resolvedCursorIndex,
            previousExpectedKey: previousExpected,
            at: date
        )
    }

    mutating func recordCorrection(
        expected: Character,
        previousExpected: Character?,
        at date: Date,
        cursorIndex: Int
    ) {
        guard let expectedSymbol = AdaptiveTypingEngine.normalizedSymbol(for: expected) else { return }
        let previousExpectedSymbol = previousExpected.flatMap { AdaptiveTypingEngine.normalizedSymbol(for: $0) }
        recordStep(
            kind: .corrected,
            expectedKey: expectedSymbol,
            typedKey: nil,
            cursorIndex: max(0, cursorIndex),
            previousExpectedKey: previousExpectedSymbol,
            at: date
        )
    }

    mutating func truncate(to cursorIndex: Int) {
        guard cursorIndex >= 0 else {
            reset()
            return
        }
        acceptedEvents.removeAll { $0.cursorIndex >= cursorIndex }
        rejectedEvents.removeAll { $0.cursorIndex >= cursorIndex }
        stepEvents.removeAll { $0.cursorIndex >= cursorIndex }
    }

    func makePayload(lesson: AdaptiveLessonState) -> AdaptiveSessionPayload {
        struct MutableKeyStat {
            var hitCount = 0
            var missCount = 0
            var sampleCount = 0
            var totalTimeMS = 0.0
        }

        struct MutableTransitionStat {
            var count = 0
            var totalTimeMS = 0.0
        }

        var keyStats: [String: MutableKeyStat] = [:]
        var transitions: [String: MutableTransitionStat] = [:]

        var previousAccepted: AcceptedEvent?
        var previousTransitionKey: String?

        for event in acceptedEvents {
            if event.expected != " " {
                var keyStat = keyStats[event.expected, default: MutableKeyStat()]
                if event.expected == event.typed {
                    keyStat.hitCount += 1
                } else {
                    keyStat.missCount += 1
                }

                if let previousAccepted {
                    let intervalMS = event.timestamp.timeIntervalSince(previousAccepted.timestamp) * 1000
                    if intervalMS.isFinite, intervalMS > 0 {
                        keyStat.sampleCount += 1
                        keyStat.totalTimeMS += intervalMS

                        if let previousTransitionKey,
                           previousTransitionKey != " " {
                            let transitionID = "\(previousTransitionKey)→\(event.expected)"
                            var transition = transitions[transitionID, default: MutableTransitionStat()]
                            transition.count += 1
                            transition.totalTimeMS += intervalMS
                            transitions[transitionID] = transition
                        }
                    }
                }

                keyStats[event.expected] = keyStat
            }
            previousAccepted = event
            previousTransitionKey = event.expected
        }

        for event in rejectedEvents {
            guard event.expected != " " else { continue }
            var keyStat = keyStats[event.expected, default: MutableKeyStat()]
            keyStat.missCount += 1
            keyStats[event.expected] = keyStat
        }

        let encodedKeyStats = keyStats
            .map { key, stat in
                AdaptiveSessionKeyStat(
                    key: key,
                    hitCount: stat.hitCount,
                    missCount: stat.missCount,
                    timeToTypeMS: stat.sampleCount > 0 ? (stat.totalTimeMS / Double(stat.sampleCount)) : nil
                )
            }
            .sorted { $0.key < $1.key }

        let encodedTransitions = transitions
            .compactMap { transitionID, stat -> AdaptiveSessionTransitionStat? in
                guard stat.count > 0 else { return nil }
                let pair = transitionID.split(separator: "→", maxSplits: 1, omittingEmptySubsequences: false)
                guard pair.count == 2 else { return nil }
                let fromKey = String(pair[0])
                let toKey = String(pair[1])
                return AdaptiveSessionTransitionStat(
                    fromKey: fromKey,
                    toKey: toKey,
                    count: stat.count,
                    averageTimeMS: stat.totalTimeMS / Double(stat.count)
                )
            }
            .sorted {
                if $0.count == $1.count {
                    return ($0.fromKey, $0.toKey) < ($1.fromKey, $1.toKey)
                }
                return $0.count > $1.count
            }

        let telemetry = stepEvents.isEmpty
            ? nil
            : AdaptiveSessionTelemetry.build(from: stepEvents)

        return AdaptiveSessionPayload(
            lesson: lesson,
            keyStats: encodedKeyStats,
            transitions: encodedTransitions,
            telemetry: telemetry
        )
    }

    private func previousExpectedKey(before cursorIndex: Int) -> String? {
        acceptedEvents
            .filter { $0.cursorIndex < cursorIndex && $0.expected != " " }
            .last?
            .expected
    }

    private mutating func recordStep(
        kind: AdaptiveSessionStepKind,
        expectedKey: String?,
        typedKey: String?,
        cursorIndex: Int,
        previousExpectedKey: String?,
        at date: Date
    ) {
        let origin = sessionOrigin ?? date
        if sessionOrigin == nil {
            sessionOrigin = origin
        }
        let timestampMS = max(0, Int((date.timeIntervalSince(origin) * 1000).rounded()))
        stepEvents.append(
            AdaptiveSessionStep(
                id: stepEvents.count,
                kind: kind,
                expectedKey: expectedKey,
                typedKey: typedKey,
                cursorIndex: cursorIndex,
                timestampMS: timestampMS,
                previousExpectedKey: previousExpectedKey
            )
        )
    }
}

private final class AdaptiveCorpusStore: @unchecked Sendable {
    nonisolated private static let maxCachedCorpora = 2
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var cache: [String: AdaptiveCorpus] = [:]
    nonisolated(unsafe) private var cacheOrder: [String] = []

    nonisolated func corpus(for language: Language) -> AdaptiveCorpus {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[language.rawValue] {
            touch(language.rawValue)
            return cached
        }

        let built = AdaptiveCorpus(
            words: language.wordList(),
            phoneticModelResourceName: language.phoneticModelResourceName
        )
        cache[language.rawValue] = built
        touch(language.rawValue)
        while cacheOrder.count > Self.maxCachedCorpora {
            let evictedKey = cacheOrder.removeFirst()
            cache.removeValue(forKey: evictedKey)
        }
        return built
    }

    nonisolated private func touch(_ key: String) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }
}

enum AdaptiveTypingEngine {
    nonisolated static let defaults = AdaptiveTypingDefaults()

    nonisolated fileprivate static let punctuatorWeights: [(String, Double)] = [
        (",", 9.0),
        (".", 8.0),
        ("!", 2.0),
        ("?", 2.0),
        (";", 1.0),
        (":", 1.0),
        ("'", 1.0),
        ("\"", 1.0),
        ("-", 1.0)
    ]
    nonisolated private static let corpusStore = AdaptiveCorpusStore()

    nonisolated static func makeLesson(
        settings: AppSettings,
        language: Language,
        results: [AdaptiveHistoryResult]
    ) -> AdaptiveGeneratedLesson {
        let lessonContext = makeDerivedSnapshot(
            results: results,
            language: language,
            settings: settings
        ).lessonGenerationContext
        return makeLesson(
            settings: settings,
            language: language,
            lessonContext: lessonContext
        )
    }

    nonisolated static func makeLesson(
        settings: AppSettings,
        language: Language,
        runtime: AdaptiveTrainingRuntimeSnapshot
    ) -> AdaptiveGeneratedLesson {
        guard !runtime.lessonGenerationContext.lessonState.activeAlphabet.isEmpty else {
            return makeLesson(
                settings: settings,
                language: language,
                results: runtime.adaptiveHistoryResults
            )
        }

        return makeLesson(
            settings: settings,
            language: language,
            lessonContext: runtime.lessonGenerationContext
        )
    }

    nonisolated static func makeAnalysisSnapshot(
        results: [AdaptiveHistoryResult],
        language: Language,
        settings: AppSettings
    ) -> AdaptiveAnalysisSnapshot {
        makeDerivedSnapshot(
            results: results,
            language: language,
            settings: settings
        ).analysis
    }

    nonisolated static func makeDerivedSnapshot(
        results: [AdaptiveHistoryResult],
        language: Language,
        settings: AppSettings
    ) -> AdaptiveDerivedTrainingSnapshot {
        let configuration = AdaptiveTrainingConfiguration(settings: settings)
        let corpus = corpus(for: language)
        let adaptiveResults = results.filter(\.contributesToAdaptiveProfile)
        let profile = buildLessonProfile(results: adaptiveResults, corpus: corpus, configuration: configuration)
        let averageWPM = metricAverage(adaptiveResults.map(\.wpm))
        let averageAccuracy = metricAverage(adaptiveResults.map(\.accuracy))
        let bestWPM = adaptiveResults.map(\.wpm).max() ?? 0
        let weakestKeys = profile.keyProfiles
            .filter { $0.isIncluded || $0.samples > 0 || $0.misses > 0 }
            .sorted {
                if abs($0.needScore - $1.needScore) < 0.0001 {
                    return $0.key < $1.key
                }
                return $0.needScore > $1.needScore
            }
            .prefix(8)
        let strongestKeys = profile.keyProfiles
            .filter { $0.samples > 0 }
            .sorted {
                let left = $0.bestConfidence ?? 0
                let right = $1.bestConfidence ?? 0
                if abs(left - right) < 0.0001 {
                    return $0.key < $1.key
                }
                return left > right
            }
            .prefix(6)

        return AdaptiveDerivedTrainingSnapshot(
            analysis: AdaptiveAnalysisSnapshot(
                averageWPM: averageWPM,
                averageAccuracy: averageAccuracy,
                sessions: adaptiveResults.count,
                bestWPM: bestWPM,
                currentLesson: profile.lessonState,
                activeAlphabetSize: profile.lessonState.activeAlphabet.count,
                readiness: profile.readiness,
                allKeys: profile.keyProfiles,
                weakestKeys: Array(weakestKeys),
                strongestKeys: Array(strongestKeys),
                keyboard: profile.keyboard,
                forecast: profile.forecast,
                transitions: Array(profile.transitions.prefix(8))
            ),
            lessonGenerationContext: AdaptiveLessonGenerationContext(
                keyProfiles: profile.keyProfiles,
                lessonState: profile.lessonState,
                transitionNeedByPair: profile.transitionNeedByPair
            )
        )
    }

    nonisolated static func makeProgressOverview(
        results: [AdaptiveHistoryResult],
        language: Language,
        settings: AppSettings
    ) -> AdaptiveProgressOverviewSnapshot {
        let adaptiveResults = chronologicallySortedIfNeeded(results.filter(\.contributesToAdaptiveProfile))
        guard !adaptiveResults.isEmpty else { return .empty }

        let configuration = AdaptiveTrainingConfiguration(settings: settings)
        let keyboardLayout = AdaptiveKeyboardLayout.layout(for: configuration.keyboardLayout)
        let orderedLetters = corpus(for: language).orderedLetters(
            using: configuration.unlockStrategy,
            keyboardLayout: keyboardLayout
        )
        let aggregate = AdaptiveAggregate(
            orderedLetters: orderedLetters,
            targetWPM: configuration.targetWPM,
            smoothingFactor: configuration.smoothingFactor
        )

        let visibleResults = Array(adaptiveResults.suffix(18))
        let hiddenPrefixCount = max(0, adaptiveResults.count - visibleResults.count)
        var profiles = aggregate.emptyProfiles()

        for result in adaptiveResults.prefix(hiddenPrefixCount) {
            aggregate.consume(result: result, into: &profiles)
        }

        var columns: [AdaptiveProgressOverviewColumn] = []
        var samplesByKey = Dictionary(uniqueKeysWithValues: orderedLetters.map { (String($0), [AdaptiveProgressOverviewSample]()) })

        for (index, result) in visibleResults.enumerated() {
            aggregate.consume(result: result, into: &profiles)

            let lesson = result.adaptivePayload?.lesson ?? .empty
            let activeKeys = Set(lesson.activeAlphabet)
            columns.append(
                AdaptiveProgressOverviewColumn(
                    id: index,
                    date: result.date,
                    focusedKey: lesson.focusedKey,
                    activeAlphabetSize: lesson.activeAlphabet.count
                )
            )

            for character in orderedLetters {
                let key = String(character)
                let profile = profiles[key] ?? AdaptiveMutableKeyProfile(key: key)
                samplesByKey[key, default: []].append(
                    AdaptiveProgressOverviewSample(
                        sessionIndex: index,
                        key: key,
                        confidence: profile.confidence(targetWPM: configuration.targetWPM),
                        bestConfidence: profile.bestConfidence(targetWPM: configuration.targetWPM),
                        isActive: activeKeys.contains(key),
                        isFocused: lesson.focusedKey == key
                    )
                )
            }
        }

        let rows = orderedLetters.map { character in
            let key = String(character)
            return AdaptiveProgressOverviewRow(
                key: key,
                samples: samplesByKey[key, default: []]
            )
        }

        return AdaptiveProgressOverviewSnapshot(
            columns: columns,
            rows: rows
        )
    }

    nonisolated private static func makeLesson(
        settings: AppSettings,
        language: Language,
        lessonContext: AdaptiveLessonGenerationContext
    ) -> AdaptiveGeneratedLesson {
        let configuration = AdaptiveTrainingConfiguration(settings: settings)
        let corpus = corpus(for: language)
        let desiredTextLength = fragmentTextLength(for: settings)

        var generator = SystemRandomNumberGenerator()
        let lessonWords = generateWords(
            textLength: desiredTextLength,
            corpus: corpus,
            profile: lessonContext,
            configuration: configuration,
            generator: &generator
        )

        return AdaptiveGeneratedLesson(
            text: lessonWords.joined(separator: " "),
            lessonState: lessonContext.lessonState
        )
    }

    nonisolated static func encodedPayload(_ payload: AdaptiveSessionPayload) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated static func decodedPayload(from json: String?) -> AdaptiveSessionPayload? {
        let decoder = JSONDecoder()
        guard let json,
              let data = json.data(using: .utf8),
              let payload = try? decoder.decode(AdaptiveSessionPayload.self, from: data) else {
            return nil
        }
        return payload
    }

    nonisolated static func normalizedSymbol(for character: Character) -> String? {
        if character == " " {
            return " "
        }

        let value = String(character).lowercased()
        guard value.count == 1 else { return nil }
        return value
    }

    nonisolated static func fragmentTextLength(for settings: AppSettings) -> Int {
        let configuration = AdaptiveTrainingConfiguration(settings: settings)
        return 100 + Int(round(configuration.lessonLength * 100))
    }

    nonisolated private static func metricAverage(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    nonisolated private static func corpus(for language: Language) -> AdaptiveCorpus {
        corpusStore.corpus(for: language)
    }

    nonisolated static func supportedLetters(for language: Language) -> Set<Character> {
        Set(corpus(for: language).frequencyOrderedLetters)
    }

    nonisolated static func supportedKeyboardCharacters(for option: KeyboardLayoutOption) -> Set<Character> {
        AdaptiveKeyboardLayout.layout(for: option).supportedCharacters
    }

    nonisolated private static func buildLessonProfile(
        results: [AdaptiveHistoryResult],
        corpus: AdaptiveCorpus,
        configuration: AdaptiveTrainingConfiguration
    ) -> AdaptiveProfile {
        let keyboardLayout = AdaptiveKeyboardLayout.layout(for: configuration.keyboardLayout)
        let orderedLetters = corpus.orderedLetters(
            using: configuration.unlockStrategy,
            keyboardLayout: keyboardLayout
        )
        let aggregate = AdaptiveAggregate(
            orderedLetters: orderedLetters,
            targetWPM: configuration.targetWPM,
            smoothingFactor: configuration.smoothingFactor
        )
        let aggregated = aggregate.consume(results: results)
        let lessonSelection = selectLessonKeys(
            orderedLetters: orderedLetters,
            aggregated: aggregated,
            configuration: configuration
        )
        let keyProfiles = buildKeyProfiles(
            orderedLetters: orderedLetters,
            aggregated: aggregated,
            selection: lessonSelection,
            configuration: configuration
        )
        let activeAlphabet = keyProfiles
            .filter(\.isIncluded)
            .map(\.key)
        let readiness = averageReadiness(for: keyProfiles)
        let keyboard = keyboardLayout.snapshot(for: keyProfiles, results: results)
        let forecastResult = forecast(
            for: lessonSelection.forecastCandidates,
            targetWPM: configuration.targetWPM
        )
        let transitions = aggregateTransitions(results: results)
        let transitionNeedByPair = transitionNeedScores(
            transitions: transitions,
            activeAlphabet: Set(activeAlphabet),
            targetTimeMS: AdaptiveAggregate.targetTimeMS(targetWPM: configuration.targetWPM)
        )

        return AdaptiveProfile(
            keyProfiles: keyProfiles,
            readiness: readiness,
            keyboard: keyboard,
            forecast: forecastResult,
            transitions: transitions,
            transitionNeedByPair: transitionNeedByPair,
            lessonState: AdaptiveLessonState(
                activeAlphabet: activeAlphabet,
                focusedKey: lessonSelection.focusedKey,
                forcedKeys: keyProfiles.filter(\.isForced).map(\.key),
                targetWPM: configuration.targetWPM,
                source: lessonSelection.includedSet.isEmpty ? "random" : "adaptive"
            )
        )
    }

    nonisolated private static func selectLessonKeys(
        orderedLetters: [Character],
        aggregated: [String: AdaptiveMutableKeyProfile],
        configuration: AdaptiveTrainingConfiguration
    ) -> AdaptiveLessonSelection {
        let minSize = min(configuration.minimumAlphabetSize, max(1, orderedLetters.count))
        let maxSize = min(
            orderedLetters.count,
            minSize + Int(round(Double(max(0, orderedLetters.count - minSize)) * configuration.alphabetExpansion))
        )

        var states: [String: AdaptiveInclusionState] = [:]
        var included: [AdaptiveMutableKeyProfile] = []

        for symbol in orderedLetters.map(String.init) {
            var profile = aggregated[symbol] ?? AdaptiveMutableKeyProfile(key: symbol)
            let bestConfidence = profile.bestConfidence(targetWPM: configuration.targetWPM)

            if included.count < minSize {
                profile.state = .included
                included.append(profile)
                states[symbol] = .included
                continue
            }

            if included.count < maxSize {
                profile.state = .forced
                included.append(profile)
                states[symbol] = .forced
                continue
            }

            if (bestConfidence ?? 0) >= 1 {
                profile.state = .included
                included.append(profile)
                states[symbol] = .included
                continue
            }

            let unlockAllowed: Bool
            if configuration.recoverKeys {
                unlockAllowed = included.allSatisfy { ($0.confidence(targetWPM: configuration.targetWPM) ?? 0) >= 1 }
            } else {
                unlockAllowed = included.allSatisfy { ($0.bestConfidence(targetWPM: configuration.targetWPM) ?? 0) >= 1 }
            }

            if unlockAllowed {
                profile.state = .included
                included.append(profile)
                states[symbol] = .included
                continue
            }

            states[symbol] = .excluded
        }

        let inclusionOrder = Dictionary(uniqueKeysWithValues: included.enumerated().map { ($0.element.key, $0.offset) })

        let focusCandidates = included
            .filter { inclusionConfidence(for: $0, configuration: configuration) < 1 }
            .sorted {
                let lhs = inclusionConfidence(for: $0, configuration: configuration)
                let rhs = inclusionConfidence(for: $1, configuration: configuration)
                if abs(lhs - rhs) < 0.0001 {
                    let leftOrder = inclusionOrder[$0.key] ?? Int.max
                    let rightOrder = inclusionOrder[$1.key] ?? Int.max
                    if leftOrder == rightOrder {
                        return $0.key < $1.key
                    }
                    return leftOrder < rightOrder
                }
                return lhs < rhs
            }
        let forecastCandidates = focusCandidates.isEmpty ? included : Array(focusCandidates.prefix(4))

        return AdaptiveLessonSelection(
            states: states,
            focusedKey: focusCandidates.first?.key,
            forecastCandidates: forecastCandidates,
            includedSet: Set(included.map(\.key))
        )
    }

    nonisolated private static func buildKeyProfiles(
        orderedLetters: [Character],
        aggregated: [String: AdaptiveMutableKeyProfile],
        selection: AdaptiveLessonSelection,
        configuration: AdaptiveTrainingConfiguration
    ) -> [AdaptiveKeyProfile] {
        orderedLetters.map { character -> AdaptiveKeyProfile in
            let key = String(character)
            let mutable = aggregated[key] ?? AdaptiveMutableKeyProfile(key: key)
            let state = selection.states[key] ?? .excluded
            let confidence = mutable.confidence(targetWPM: configuration.targetWPM)
            let bestConfidence = mutable.bestConfidence(targetWPM: configuration.targetWPM)
            let samples = mutable.samples.count
            let totalAttempts = mutable.hits + mutable.misses
            let accuracy = totalAttempts > 0 ? Double(mutable.hits) / Double(totalAttempts) : 0
            let speedNeed = max(0, 1 - (confidence ?? 0))
            let accuracyNeed = samples == 0 && mutable.misses == 0
                ? 0.35
                : max(0, 0.98 - accuracy) / 0.98
            let noveltyNeed = samples == 0 ? 0.55 : (samples < 3 ? 0.18 : 0)
            let needScore = min(
                1.8,
                speedNeed * 0.72 + accuracyNeed * 0.28 + noveltyNeed + (key == selection.focusedKey ? 0.12 : 0)
            )

            return AdaptiveKeyProfile(
                key: key,
                samples: samples,
                hits: mutable.hits,
                misses: mutable.misses,
                latestTimeMS: mutable.latestTimeMS,
                bestTimeMS: mutable.bestTimeMS,
                accuracy: accuracy,
                confidence: confidence,
                bestConfidence: bestConfidence,
                needScore: needScore,
                isIncluded: state != .excluded,
                isFocused: key == selection.focusedKey,
                isForced: state == .forced
            )
        }
    }

    nonisolated private static func averageReadiness(for keyProfiles: [AdaptiveKeyProfile]) -> Double {
        let readinessComponents = keyProfiles
            .filter(\.isIncluded)
            .map { profile in
                min(1, max(0, profile.confidence ?? 0))
            }
        return readinessComponents.isEmpty
            ? 0
            : min(1, readinessComponents.reduce(0, +) / Double(readinessComponents.count))
    }

    nonisolated private static func inclusionConfidence(
        for profile: AdaptiveMutableKeyProfile,
        configuration: AdaptiveTrainingConfiguration
    ) -> Double {
        if configuration.recoverKeys {
            return profile.confidence(targetWPM: configuration.targetWPM) ?? 0
        }
        return profile.bestConfidence(targetWPM: configuration.targetWPM) ?? 0
    }

    nonisolated private static func forecast(
        for profiles: [AdaptiveMutableKeyProfile],
        targetWPM: Double
    ) -> AdaptiveForecast? {
        let projections = profiles.compactMap { profile -> AdaptiveKeyForecast? in
            forecastProjection(
                for: profile.samples,
                targetWPM: targetWPM
            )
        }
        guard !projections.isEmpty else { return nil }

        let certainty = projections.map(\.certainty).reduce(0, +) / Double(projections.count)
        guard certainty >= 0.35 else { return nil }

        let learningRate = projections.map(\.learningRateCPMPerLesson).reduce(0, +) / Double(projections.count)
        let remainingCandidates = projections.compactMap(\.remainingLessons)
        let remainingLessons: Int?
        if remainingCandidates.isEmpty {
            remainingLessons = projections.allSatisfy { $0.remainingLessons == 0 } ? 0 : nil
        } else {
            remainingLessons = remainingCandidates.max()
        }

        return AdaptiveForecast(
            certainty: certainty,
            learningRateCPMPerLesson: learningRate,
            remainingLessons: remainingLessons
        )
    }

    nonisolated private static func forecastProjection(
        for samples: [AdaptiveLessonSample],
        targetWPM: Double
    ) -> AdaptiveKeyForecast? {
        let recent = recentLearningSamples(from: samples)
        guard recent.count >= 5 else { return nil }

        let targetCPM = targetWPM * 5
        let xs = recent.enumerated().map { Double($0.offset + 1) }
        let ys = recent.map { 60_000 / $0.filteredTimeMS }
        let degree = polynomialDegree(for: xs.count)
        guard let model = polynomialRegression(xs: xs, ys: ys, degree: degree) else { return nil }

        let certainty = coefficientOfDetermination(xs: xs, ys: ys, model: model)
        guard certainty.isFinite, certainty >= 0.5 else { return nil }

        let lastIndex = Double(recent.count)
        let lastPrediction = model.evaluate(lastIndex)
        let learningRate = model.derivative(at: lastIndex)
        let remainingLessons: Int?
        if lastPrediction >= targetCPM {
            remainingLessons = 0
        } else {
            remainingLessons = (1...50).first { lessonOffset in
                model.evaluate(lastIndex + Double(lessonOffset)) >= targetCPM
            }
        }

        return AdaptiveKeyForecast(
            certainty: certainty,
            learningRateCPMPerLesson: learningRate,
            remainingLessons: remainingLessons
        )
    }

    nonisolated private static func recentLearningSamples(from samples: [AdaptiveLessonSample]) -> [AdaptiveLessonSample] {
        let sorted = samples.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return [] }

        let recent = Array(sorted.suffix(30))
        guard recent.count >= 5 else { return recent }

        for index in stride(from: recent.count - 1, to: 0, by: -1) {
            let previous = recent[index - 1]
            let current = recent[index]
            if current.date.timeIntervalSince(previous.date) > 60 * 60 {
                return Array(recent.suffix(from: index))
            }
            if current.filteredTimeMS > previous.filteredTimeMS,
               recent.count - index + 1 >= 5 {
                return Array(recent.suffix(from: index))
            }
        }

        return Array(recent)
    }

    nonisolated private static func aggregateTransitions(results: [AdaptiveHistoryResult]) -> [AdaptiveTransitionInsight] {
        struct MutableTransition {
            var count = 0
            var totalTimeMS = 0.0
        }

        var totals: [String: MutableTransition] = [:]

        for result in results {
            guard let payload = result.adaptivePayload else { continue }
            for item in payload.transitions {
                let id = "\(item.fromKey)→\(item.toKey)"
                var mutable = totals[id, default: MutableTransition()]
                mutable.count += item.count
                mutable.totalTimeMS += item.averageTimeMS * Double(item.count)
                totals[id] = mutable
            }
        }

        return totals.compactMap { id, mutable in
            guard mutable.count > 0 else { return nil }
            let parts = id.split(separator: "→", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return AdaptiveTransitionInsight(
                fromKey: String(parts[0]),
                toKey: String(parts[1]),
                count: mutable.count,
                averageTimeMS: mutable.totalTimeMS / Double(mutable.count)
            )
        }
        .sorted {
            if $0.count == $1.count {
                return ($0.fromKey, $0.toKey) < ($1.fromKey, $1.toKey)
            }
            return $0.count > $1.count
        }
    }

    nonisolated private static func transitionNeedScores(
        transitions: [AdaptiveTransitionInsight],
        activeAlphabet: Set<String>,
        targetTimeMS: Double
    ) -> [String: Double] {
        guard targetTimeMS > 0 else { return [:] }

        var scores: [String: Double] = [:]
        for transition in transitions {
            guard activeAlphabet.contains(transition.fromKey),
                  activeAlphabet.contains(transition.toKey) else {
                continue
            }

            let relativeSlowdown = max(0, (transition.averageTimeMS / targetTimeMS) - 1)
            let sampleWeight = min(1, Double(transition.count) / 6)
            let score = min(1.5, relativeSlowdown * (0.45 + (sampleWeight * 0.55)))
            guard score > 0 else { continue }

            let pair = transition.fromKey + transition.toKey
            scores[pair] = max(scores[pair] ?? 0, score)
        }
        return scores
    }

    nonisolated private static func generateWords<T: RandomNumberGenerator>(
        textLength: Int,
        corpus: AdaptiveCorpus,
        profile: AdaptiveLessonGenerationContext,
        configuration: AdaptiveTrainingConfiguration,
        generator: inout T
    ) -> [String] {
        let allowed = Set(profile.lessonState.activeAlphabet.compactMap(\.first))
        let focusKey = profile.lessonState.focusedKey?.first
        let forcedKeys = Set(profile.lessonState.forcedKeys.compactMap(\.first))
        let keyNeedByCharacter = Dictionary(
            uniqueKeysWithValues: profile.keyProfiles.compactMap { keyProfile -> (Character, Double)? in
                guard let character = keyProfile.key.first,
                      keyProfile.isIncluded || keyProfile.isForced else {
                    return nil
                }
                return (character, keyProfile.needScore)
            }
        )
        let wordPool = makeLessonWordPool(
            corpus: corpus,
            allowed: allowed,
            focused: focusKey,
            forced: forcedKeys,
            keyNeedByCharacter: keyNeedByCharacter,
            transitionNeedByPair: profile.transitionNeedByPair,
            configuration: configuration,
            generator: &generator
        )

        var words: [String] = []
        var recentBaseWords: [String] = []
        var wordsLength = 0

        while true {
            let baseWord = nextDiversifiedLessonWord(
                corpus: corpus,
                wordPool: wordPool,
                allowed: allowed,
                focused: focusKey,
                forced: forcedKeys,
                transitionNeedByPair: profile.transitionNeedByPair,
                configuration: configuration,
                recentWords: recentBaseWords,
                generator: &generator
            ) ?? fallbackLessonWord(
                allowed: allowed,
                focused: focusKey,
                forced: forcedKeys,
                configuration: configuration
            )
            let decorated = decorateWord(
                baseWord,
                capitalsProbability: configuration.capitalsProbability,
                punctuationProbability: configuration.punctuationProbability,
                hyphenatedWord: nextLessonWord(
                    corpus: corpus,
                    wordPool: wordPool,
                    allowed: allowed,
                    focused: focusKey,
                    forced: forcedKeys,
                    transitionNeedByPair: profile.transitionNeedByPair,
                    configuration: configuration,
                    previousWord: baseWord,
                    generator: &generator
                ),
                generator: &generator
            )

            for _ in 0..<max(1, configuration.repeatWords) {
                words.append(decorated)
                wordsLength += decorated.count
                if wordsLength >= max(1, textLength) {
                    return words
                }
            }

            recentBaseWords.append(baseWord)
            if recentBaseWords.count > 4 {
                recentBaseWords.removeFirst(recentBaseWords.count - 4)
            }
        }
    }

    nonisolated private static func makeLessonWordPool<T: RandomNumberGenerator>(
        corpus: AdaptiveCorpus,
        allowed: Set<Character>,
        focused: Character?,
        forced: Set<Character>,
        keyNeedByCharacter: [Character: Double],
        transitionNeedByPair: [String: Double],
        configuration: AdaptiveTrainingConfiguration,
        generator: inout T
    ) -> [AdaptiveWeightedWordCandidate] {
        var seenWords: Set<String> = []
        var words: [String] = []

        if configuration.naturalWords {
            for word in corpus.filteredWords(allowed: allowed, focused: nil).prefix(1_000) {
                guard seenWords.insert(word).inserted else { continue }
                words.append(word)
            }
        }

        let minimumCandidateCount: Int
        if configuration.naturalWords, words.count >= 6 {
            minimumCandidateCount = words.count
        } else if configuration.naturalWords, !words.isEmpty {
            minimumCandidateCount = 6
        } else {
            minimumCandidateCount = 24
        }

        while words.count < minimumCandidateCount {
            let pseudoWord = corpus.generatePseudoWord(
                allowed: allowed,
                focused: focused,
                configuration: configuration,
                generator: &generator
            )
            guard !pseudoWord.isEmpty else { break }
            guard seenWords.insert(pseudoWord).inserted else { continue }
            words.append(pseudoWord)
        }

        if words.isEmpty {
            words.append(
                fallbackLessonWord(
                    allowed: allowed,
                    focused: focused,
                    forced: forced,
                    configuration: configuration
                )
            )
        }

        return words.map { word in
            AdaptiveWeightedWordCandidate(
                word: word,
                baseWeight: lessonWordWeight(
                    word: word,
                    focused: focused,
                    forced: forced,
                    keyNeedByCharacter: keyNeedByCharacter,
                    transitionNeedByPair: transitionNeedByPair,
                    configuration: configuration
                )
            )
        }
    }

    nonisolated private static func nextDiversifiedLessonWord<T: RandomNumberGenerator>(
        corpus: AdaptiveCorpus,
        wordPool: [AdaptiveWeightedWordCandidate],
        allowed: Set<Character>,
        focused: Character?,
        forced: Set<Character>,
        transitionNeedByPair: [String: Double],
        configuration: AdaptiveTrainingConfiguration,
        recentWords: [String],
        generator: inout T
    ) -> String? {
        let recentWordSet = Set(recentWords)
        let previousWord = recentWords.last ?? ""

        for _ in 0..<3 {
            let candidate = nextLessonWord(
                corpus: corpus,
                wordPool: wordPool,
                allowed: allowed,
                focused: focused,
                forced: forced,
                transitionNeedByPair: transitionNeedByPair,
                configuration: configuration,
                previousWord: previousWord,
                generator: &generator
            ) ?? ""
            if !candidate.isEmpty, !recentWordSet.contains(candidate) {
                return candidate
            }
        }

        for _ in 0..<3 {
            let candidate = nextLessonWord(
                corpus: corpus,
                wordPool: wordPool,
                allowed: allowed,
                focused: focused,
                forced: forced,
                transitionNeedByPair: transitionNeedByPair,
                configuration: configuration,
                previousWord: previousWord,
                generator: &generator
            ) ?? ""
            if !candidate.isEmpty, candidate != previousWord {
                return candidate
            }
        }

        return nextLessonWord(
            corpus: corpus,
            wordPool: wordPool,
            allowed: allowed,
            focused: focused,
            forced: forced,
            transitionNeedByPair: transitionNeedByPair,
            configuration: configuration,
            previousWord: previousWord,
            generator: &generator
        )
    }

    nonisolated private static func nextLessonWord<T: RandomNumberGenerator>(
        corpus: AdaptiveCorpus,
        wordPool: [AdaptiveWeightedWordCandidate],
        allowed: Set<Character>,
        focused: Character?,
        forced: Set<Character>,
        transitionNeedByPair: [String: Double],
        configuration: AdaptiveTrainingConfiguration,
        previousWord: String? = nil,
        generator: inout T
    ) -> String? {
        if !wordPool.isEmpty {
            let filteredPool = wordPool.filter { candidate in
                previousWord.map { candidate.word != $0 } ?? true
            }
            let activePool = filteredPool.isEmpty ? wordPool : filteredPool
            let weightedItems = activePool.map { candidate in
                (
                    candidate.word,
                    candidate.baseWeight + crossWordTransitionWeight(
                        previousWord: previousWord,
                        candidateWord: candidate.word,
                        transitionNeedByPair: transitionNeedByPair
                    )
                )
            }
            return weightedSample(from: weightedItems, generator: &generator)
        }

        let pseudoWord = corpus.generatePseudoWord(
            allowed: allowed,
            focused: focused,
            configuration: configuration,
            generator: &generator
        )
        if !pseudoWord.isEmpty {
            return pseudoWord
        }
        return fallbackLessonWord(
            allowed: allowed,
            focused: focused,
            forced: forced,
            configuration: configuration
        )
    }

    nonisolated private static func lessonWordWeight(
        word: String,
        focused: Character?,
        forced: Set<Character>,
        keyNeedByCharacter: [Character: Double],
        transitionNeedByPair: [String: Double],
        configuration: AdaptiveTrainingConfiguration
    ) -> Double {
        let letters = Array(word.lowercased())
        guard !letters.isEmpty else { return 0.05 }

        let targetLength = Double(configuration.minimumWordLength + configuration.maximumWordLength) / 2
        let lengthFitness = max(0.55, 1 - (abs(Double(letters.count) - targetLength) * 0.12))

        let focusHits = focused.map { key in
            letters.filter { $0 == key }.count
        } ?? 0
        let forcedHits = letters.filter { forced.contains($0) }.count
        let keyNeed = letters.reduce(0.0) { partialResult, character in
            partialResult + (keyNeedByCharacter[character] ?? 0)
        }

        var transitionNeed = 0.0
        if letters.count > 1 {
            for index in 1..<letters.count {
                let pair = String(letters[index - 1]) + String(letters[index])
                transitionNeed += transitionNeedByPair[pair] ?? 0
            }
        }

        var weight = 0.45
        weight += keyNeed * 0.42
        weight += transitionNeed * 0.85
        weight += Double(forcedHits) * 0.8

        if focused != nil {
            if focusHits > 0 {
                weight += 1.75 + (Double(focusHits) * 0.55)
            } else {
                weight *= 0.28
            }
        }

        return max(0.05, weight * lengthFitness)
    }

    nonisolated private static func crossWordTransitionWeight(
        previousWord: String?,
        candidateWord: String,
        transitionNeedByPair: [String: Double]
    ) -> Double {
        guard let previousCharacter = previousWord?.lowercased().last,
              let nextCharacter = candidateWord.lowercased().first else {
            return 0
        }
        return transitionNeedByPair[String(previousCharacter) + String(nextCharacter)] ?? 0
    }

    nonisolated private static func fallbackLessonWord(
        allowed: Set<Character>,
        focused: Character?,
        forced: Set<Character>,
        configuration: AdaptiveTrainingConfiguration
    ) -> String {
        var prioritized: [Character] = []
        if let focused {
            prioritized.append(focused)
        }
        prioritized.append(contentsOf: forced.sorted())
        prioritized.append(contentsOf: allowed.sorted())

        var seen: Set<Character> = []
        let seed = prioritized.filter { seen.insert($0).inserted }
        guard let firstSeed = seed.first else { return "type" }

        let targetLength = min(
            configuration.maximumWordLength,
            max(configuration.minimumWordLength, min(seed.count + 1, configuration.maximumWordLength))
        )

        if seed.count == 1 {
            return String(repeating: String(firstSeed), count: targetLength)
        }

        var output: [Character] = []
        output.reserveCapacity(targetLength)
        while output.count < targetLength {
            for character in seed {
                guard output.count < targetLength else { break }
                if output.last == character {
                    continue
                }
                output.append(character)
            }
        }

        return String(output)
    }

    nonisolated static func decorateWord<T: RandomNumberGenerator>(
        _ word: String,
        capitalsProbability: Double,
        punctuationProbability: Double,
        hyphenatedWord: String?,
        generator: inout T
    ) -> String {
        var output = word

        if capitalsProbability > 0, capitalsProbability >= Double.random(in: 0...1, using: &generator) {
            output = capitalizedWord(output)
        }

        if punctuationProbability > 0,
           punctuationProbability >= Double.random(in: 0...1, using: &generator),
           let punctuator = weightedSample(from: punctuatorWeights, generator: &generator) {
            switch punctuator {
            case "!":
                output += "!"
            case "\"":
                output = "\"\(output)\""
            case "'":
                output = "'\(output)'"
            case ",":
                output += ","
            case "-":
                if let suffix = hyphenatedWord {
                    output += "-\(suffix)"
                } else {
                    output += "-"
                }
            case ".":
                output += "."
            case ":":
                output += ":"
            case ";":
                output += ";"
            case "?":
                output += "?"
            default:
                break
            }
        }

        return output
    }

    nonisolated private static func capitalizedWord(_ word: String) -> String {
        guard let firstCharacter = word.first else { return word }
        return String(firstCharacter).uppercased() + String(word.dropFirst())
    }

    nonisolated static func weightedSample<T: RandomNumberGenerator>(
        from items: [(String, Double)],
        generator: inout T
    ) -> String? {
        let total = items.reduce(0.0) { $0 + max(0, $1.1) }
        guard total > 0 else { return items.first?.0 }

        var threshold = Double.random(in: 0..<total, using: &generator)
        for (value, weight) in items {
            threshold -= max(0, weight)
            if threshold <= 0 {
                return value
            }
        }
        return items.last?.0
    }
}

private struct AdaptiveProfile {
    var keyProfiles: [AdaptiveKeyProfile]
    var readiness: Double
    var keyboard: AdaptiveKeyboardSnapshot
    var forecast: AdaptiveForecast?
    var transitions: [AdaptiveTransitionInsight]
    var transitionNeedByPair: [String: Double]
    var lessonState: AdaptiveLessonState
}

private struct AdaptiveLessonSelection {
    var states: [String: AdaptiveInclusionState]
    var focusedKey: String?
    var forecastCandidates: [AdaptiveMutableKeyProfile]
    var includedSet: Set<String>
}

private struct AdaptiveWeightedWordCandidate {
    var word: String
    var baseWeight: Double
}

private struct AdaptiveKeyForecast {
    var certainty: Double
    var learningRateCPMPerLesson: Double
    var remainingLessons: Int?
}

private struct AdaptivePolynomialModel {
    var coefficients: [Double]

    nonisolated func evaluate(_ x: Double) -> Double {
        var result = 0.0
        for coefficient in coefficients.reversed() {
            result = (result * x) + coefficient
        }
        return result
    }

    nonisolated func derivative(at x: Double) -> Double {
        guard coefficients.count > 1 else { return 0 }

        var derivativeCoefficients: [Double] = []
        derivativeCoefficients.reserveCapacity(coefficients.count - 1)
        for index in 1..<coefficients.count {
            derivativeCoefficients.append(coefficients[index] * Double(index))
        }
        return AdaptivePolynomialModel(coefficients: derivativeCoefficients).evaluate(x)
    }
}

nonisolated private func polynomialDegree(for sampleCount: Int) -> Int {
    if sampleCount > 20 {
        return 3
    }
    if sampleCount > 10 {
        return 2
    }
    return 1
}

nonisolated private func polynomialRegression(
    xs: [Double],
    ys: [Double],
    degree: Int
) -> AdaptivePolynomialModel? {
    guard !xs.isEmpty, xs.count == ys.count else { return nil }

    let size = degree + 1
    var matrix = Array(repeating: Array(repeating: 0.0, count: size), count: size)
    var rhs = Array(repeating: 0.0, count: size)

    for row in 0..<size {
        for column in 0..<size {
            matrix[row][column] = xs.reduce(0) { partial, x in
                partial + pow(x, Double(row + column))
            }
        }
        rhs[row] = zip(xs, ys).reduce(0) { partial, pair in
            partial + (pow(pair.0, Double(row)) * pair.1)
        }
    }

    guard let coefficients = solveLinearSystem(matrix: matrix, rhs: rhs) else { return nil }
    return AdaptivePolynomialModel(coefficients: coefficients)
}

nonisolated private func solveLinearSystem(
    matrix: [[Double]],
    rhs: [Double]
) -> [Double]? {
    let size = matrix.count
    guard size > 0,
          matrix.allSatisfy({ $0.count == size }),
          rhs.count == size else {
        return nil
    }

    var augmented = zip(matrix, rhs).map { row, value in
        row + [value]
    }

    for pivotIndex in 0..<size {
        var maxRow = pivotIndex
        var maxValue = abs(augmented[pivotIndex][pivotIndex])

        for row in (pivotIndex + 1)..<size {
            let candidate = abs(augmented[row][pivotIndex])
            if candidate > maxValue {
                maxValue = candidate
                maxRow = row
            }
        }

        guard maxValue > 1e-12 else { return nil }

        if maxRow != pivotIndex {
            augmented.swapAt(pivotIndex, maxRow)
        }

        for row in (pivotIndex + 1)..<size {
            let factor = augmented[row][pivotIndex] / augmented[pivotIndex][pivotIndex]
            guard factor.isFinite else { return nil }

            for column in pivotIndex...size {
                augmented[row][column] -= factor * augmented[pivotIndex][column]
            }
        }
    }

    var solution = Array(repeating: 0.0, count: size)
    for row in stride(from: size - 1, through: 0, by: -1) {
        var partial = augmented[row][size]
        for column in (row + 1)..<size {
            partial -= augmented[row][column] * solution[column]
        }

        let pivot = augmented[row][row]
        guard abs(pivot) > 1e-12 else { return nil }
        solution[row] = partial / pivot
    }

    return solution.allSatisfy(\.isFinite) ? solution : nil
}

nonisolated private func coefficientOfDetermination(
    xs: [Double],
    ys: [Double],
    model: AdaptivePolynomialModel
) -> Double {
    guard !xs.isEmpty, xs.count == ys.count else { return .nan }

    let meanY = ys.reduce(0, +) / Double(ys.count)
    let residual = zip(xs, ys).reduce(0.0) { partial, pair in
        partial + pow(pair.1 - model.evaluate(pair.0), 2)
    }
    let total = ys.reduce(0.0) { partial, value in
        partial + pow(value - meanY, 2)
    }
    guard total > 0 else { return .nan }
    return 1 - (residual / total)
}

private struct AdaptiveWordEntry {
    var word: String
    var letters: Set<Character>
}

private struct AdaptivePrefixEntry {
    var value: String
    var letters: Set<Character>
}

private struct AdaptivePhoneticModel {
    struct Entry {
        var symbol: String
        var frequency: Int
    }

    private struct Reader {
        let data: Data
        var offset = 0

        nonisolated mutating func readUInt8() throws -> UInt8 {
            guard offset < data.count else { throw AdaptivePhoneticModelError.truncated }
            defer { offset += 1 }
            return data[offset]
        }

        nonisolated mutating func readUInt16() throws -> UInt16 {
            guard offset + 1 < data.count else { throw AdaptivePhoneticModelError.truncated }
            let value = (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
            offset += 2
            return value
        }
    }

    private enum AdaptivePhoneticModelError: Error {
        case invalidSignature
        case invalidAlphabet
        case invalidIndex
        case invalidFrequency
        case truncated
    }

    nonisolated private static let signature: [UInt8] = [107, 101, 121, 98, 114, 46, 99, 111, 109]
    nonisolated private static let spaceSymbol = " "
    nonisolated private static let minimumPrefixLength = 3

    let order: Int
    let alphabet: [String]
    let alphabetIndexBySymbol: [String: Int]
    let frequencyByLetter: [Character: Int]
    let orderedLettersByFrequency: [Character]
    let segments: [[Entry]]
    let prefixMap: [Character: [AdaptivePrefixEntry]]

    nonisolated init(data: Data) throws {
        var reader = Reader(data: data)
        for byte in Self.signature {
            guard try reader.readUInt8() == byte else {
                throw AdaptivePhoneticModelError.invalidSignature
            }
        }

        let order = Int(try reader.readUInt8())
        let size = Int(try reader.readUInt8())
        guard order >= 2, size > 0 else {
            throw AdaptivePhoneticModelError.invalidAlphabet
        }

        var alphabet: [String] = []
        alphabet.reserveCapacity(size)
        for _ in 0..<size {
            let codePoint = Int(try reader.readUInt16())
            guard let scalar = UnicodeScalar(codePoint) else {
                throw AdaptivePhoneticModelError.invalidAlphabet
            }
            alphabet.append(String(scalar))
        }

        let segmentCount = Self.integerPower(size, exponent: order - 1)
        var segments: [[Entry]] = []
        segments.reserveCapacity(segmentCount)

        for _ in 0..<segmentCount {
            let length = Int(try reader.readUInt8())
            guard length <= size else {
                throw AdaptivePhoneticModelError.invalidIndex
            }

            var segment: [Entry] = []
            segment.reserveCapacity(length)
            for _ in 0..<length {
                let index = Int(try reader.readUInt8())
                guard index < alphabet.count else {
                    throw AdaptivePhoneticModelError.invalidIndex
                }
                let frequency = Int(try reader.readUInt8())
                guard frequency > 0 else {
                    throw AdaptivePhoneticModelError.invalidFrequency
                }
                segment.append(Entry(symbol: alphabet[index], frequency: frequency))
            }
            segments.append(segment)
        }

        let indexBySymbol = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($0.element, $0.offset) })
        var frequencyByLetter: [Character: Int] = [:]
        for segment in segments {
            for entry in segment {
                guard entry.symbol != Self.spaceSymbol, let character = entry.symbol.first else { continue }
                frequencyByLetter[character, default: 0] += entry.frequency
            }
        }

        self.order = order
        self.alphabet = alphabet
        self.alphabetIndexBySymbol = indexBySymbol
        self.frequencyByLetter = frequencyByLetter
        self.orderedLettersByFrequency = frequencyByLetter
            .sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
                }
                return $0.value > $1.value
            }
            .map(\.key)
        self.segments = segments
        self.prefixMap = Self.buildPrefixMap(order: order, alphabetIndexBySymbol: indexBySymbol, segments: segments)
    }

    nonisolated static func load(resourceName: String) -> AdaptivePhoneticModel? {
        for bundle in ResourceBundleCatalog.candidateBundles {
            guard let url = bundle.url(forResource: resourceName, withExtension: "data"),
                  let data = try? Data(contentsOf: url),
                  let model = try? AdaptivePhoneticModel(data: data) else {
                continue
            }
            return model
        }
        return nil
    }

    nonisolated func segment(for output: [String]) -> [Entry] {
        let segmentIndex = Self.segmentIndex(
            order: order,
            alphabetSize: alphabet.count,
            alphabetIndexBySymbol: alphabetIndexBySymbol,
            chain: output
        )
        guard segmentIndex >= 0, segmentIndex < segments.count else { return [] }
        return segments[segmentIndex]
    }

    nonisolated private static func buildPrefixMap(
        order: Int,
        alphabetIndexBySymbol: [String: Int],
        segments: [[Entry]]
    ) -> [Character: [AdaptivePrefixEntry]] {
        var prefixMap: [Character: [AdaptivePrefixEntry]] = [:]

        func walk(_ output: [String]) {
            let segmentIndex = segmentIndex(
                order: order,
                alphabetSize: alphabetIndexBySymbol.count,
                alphabetIndexBySymbol: alphabetIndexBySymbol,
                chain: output
            )
            guard segmentIndex >= 0, segmentIndex < segments.count else { return }

            for entry in segments[segmentIndex] where entry.symbol != spaceSymbol {
                let nextOutput = output + [entry.symbol]
                let prefix = nextOutput.joined()
                if let lastCharacter = prefix.last {
                    prefixMap[lastCharacter, default: []].append(
                        AdaptivePrefixEntry(
                            value: prefix,
                            letters: Set(prefix)
                        )
                    )
                }

                if nextOutput.count < minimumPrefixLength {
                    walk(nextOutput)
                }
            }
        }

        walk([])
        return prefixMap
    }

    nonisolated private static func segmentIndex(
        order: Int,
        alphabetSize: Int,
        alphabetIndexBySymbol: [String: Int],
        chain: [String]
    ) -> Int {
        guard order >= 2 else { return 0 }

        let neededSymbols = order - 1
        let suffix = Array(chain.suffix(neededSymbols))
        let padded = Array(repeating: spaceSymbol, count: max(0, neededSymbols - suffix.count)) + suffix

        var index = 0
        for (position, symbol) in padded.enumerated() {
            let offset = integerPower(alphabetSize, exponent: neededSymbols - position - 1)
            index += (alphabetIndexBySymbol[symbol] ?? 0) * offset
        }
        return index
    }

    nonisolated private static func integerPower(_ base: Int, exponent: Int) -> Int {
        guard exponent > 0 else { return 1 }
        return (0..<exponent).reduce(1) { partialResult, _ in
            partialResult * base
        }
    }
}

private struct AdaptiveCorpus {
    private let phoneticModel: AdaptivePhoneticModel?
    private let transitionCounts: [String: [String: Int]]
    private let wordEntries: [AdaptiveWordEntry]
    private let frequencyByLetter: [Character: Int]
    private let orderedLettersByFrequency: [Character]
    private let prefixMap: [Character: [AdaptivePrefixEntry]]

    nonisolated init(words sourceWords: [String], phoneticModelResourceName: String) {
        var letterFrequency: [Character: Int] = [:]
        var transitions: [String: [String: Int]] = [:]
        var words: [AdaptiveWordEntry] = []
        var prefixes = Set<String>()
        var prefixMap: [Character: [AdaptivePrefixEntry]] = [:]

        for sourceWord in sourceWords {
            let word = sourceWord.lowercased().filter(\.isLetter)
            guard word.count >= 3 else { continue }
            let characters = Set(word)
            words.append(
                AdaptiveWordEntry(
                    word: word,
                    letters: characters
                )
            )

            for character in word {
                letterFrequency[character, default: 0] += 1
            }

            let prefixLimit = min(3, word.count)
            if prefixLimit > 0 {
                for length in 1...prefixLimit {
                    let prefix = String(word.prefix(length))
                    if prefixes.insert(prefix).inserted, let lastCharacter = prefix.last {
                        let entry = AdaptivePrefixEntry(
                            value: prefix,
                            letters: Set(prefix)
                        )
                        prefixMap[lastCharacter, default: []].append(entry)
                    }
                }
            }

            let padded = Array(repeating: " ", count: 3) + word.map(String.init) + [" "]
            guard padded.count >= 4 else { continue }
            for index in 3..<padded.count {
                let state = padded[(index - 3)..<index].joined()
                let next = padded[index]
                transitions[state, default: [:]][next, default: 0] += 1
            }
        }

        let sortedLetters = letterFrequency
            .sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
                }
                return $0.value > $1.value
            }
            .map(\.key)

        let phoneticModel = AdaptivePhoneticModel.load(resourceName: phoneticModelResourceName)

        self.phoneticModel = phoneticModel
        self.frequencyByLetter = phoneticModel?.frequencyByLetter ?? letterFrequency
        self.orderedLettersByFrequency = phoneticModel?.orderedLettersByFrequency ?? sortedLetters
        self.transitionCounts = transitions
        self.wordEntries = words
        self.prefixMap = phoneticModel?.prefixMap ?? prefixMap
    }

    nonisolated func orderedLetters(
        using strategy: AdaptiveUnlockStrategy,
        keyboardLayout: AdaptiveKeyboardLayout
    ) -> [Character] {
        switch strategy {
        case .frequencyFirst:
            return orderedLettersByFrequency
        case .layoutAware:
            return orderedLettersByFrequency.sorted { lhs, rhs in
                let leftWeight = keyboardLayout.keyboardOrderWeight(for: String(lhs))
                let rightWeight = keyboardLayout.keyboardOrderWeight(for: String(rhs))
                if leftWeight == rightWeight {
                    let leftFrequency = frequencyByLetter[lhs, default: 0]
                    let rightFrequency = frequencyByLetter[rhs, default: 0]
                    if leftFrequency == rightFrequency {
                        return lhs < rhs
                    }
                    return leftFrequency > rightFrequency
                }
                return leftWeight < rightWeight
            }
        }
    }

    nonisolated var frequencyOrderedLetters: [Character] {
        orderedLettersByFrequency
    }

    nonisolated func filteredWords(allowed: Set<Character>, focused: Character?) -> [String] {
        wordEntries.compactMap { entry in
            guard entry.letters.isSubset(of: allowed) else { return nil }
            if let focused {
                return entry.word.contains(focused) ? entry.word : nil
            }
            return entry.word
        }
    }

    nonisolated func generatePseudoWord<T: RandomNumberGenerator>(
        allowed: Set<Character>,
        focused: Character?,
        configuration: AdaptiveTrainingConfiguration,
        generator: inout T
    ) -> String {
        let prefixes = filteredPrefixes(allowed: allowed, focused: focused)
        let minLength = configuration.minimumWordLength
        let maxLength = configuration.maximumWordLength
        var attempt = 0
        var output: [String] = []

        func retry() -> Bool {
            guard attempt < 5 else { return false }
            attempt += 1
            output.removeAll(keepingCapacity: true)
            if let prefix = prefixes.randomElement(using: &generator) {
                output.append(contentsOf: prefix.map(String.init))
            }
            return true
        }

        guard retry() else { return "" }

        while true {
            let entries = transitionEntries(for: output).compactMap { key, weight -> (String, Double)? in
                if key == " " {
                    guard output.count >= minLength else { return nil }
                    return (key, Double(weight) * pow(1.3, Double(output.count)))
                }

                guard let character = key.first, allowed.contains(character) else {
                    return nil
                }
                return (key, Double(weight))
            }

            guard let next = AdaptiveTypingEngine.weightedSample(from: entries, generator: &generator) else {
                if retry() {
                    continue
                }
                return output.joined()
            }

            if next == " " {
                return output.joined()
            }

            if output.count > maxLength {
                if retry() {
                    continue
                }
                return output.joined()
            }

            output.append(next)
        }
    }

    nonisolated private func filteredPrefixes(
        allowed: Set<Character>,
        focused: Character?
    ) -> [String] {
        guard !allowed.isEmpty else { return [] }

        if let focused {
            let matching = (prefixMap[focused] ?? []).compactMap { entry -> String? in
                guard entry.letters.isSubset(of: allowed) else { return nil }
                return entry.value
            }

            if !matching.isEmpty {
                return matching
            }

            return [String(focused)]
        }

        return []
    }

    nonisolated private func transitionEntries(for output: [String]) -> [(String, Int)] {
        if let phoneticModel {
            return phoneticModel.segment(for: output).map { ($0.symbol, $0.frequency) }
        }

        let prefix = Array(repeating: " ", count: max(0, 3 - output.count))
        let state = (prefix + Array(output.suffix(3))).joined()
        return (transitionCounts[state] ?? [:]).map { ($0.key, $0.value) }
    }
}

private struct AdaptiveLessonSample: Sendable {
    var date: Date
    var filteredTimeMS: Double
}

private enum AdaptiveInclusionState: Equatable, Sendable {
    case excluded
    case included
    case forced

    nonisolated static func == (lhs: AdaptiveInclusionState, rhs: AdaptiveInclusionState) -> Bool {
        switch (lhs, rhs) {
        case (.excluded, .excluded), (.included, .included), (.forced, .forced):
            return true
        default:
            return false
        }
    }
}

private struct AdaptiveMutableKeyProfile: Sendable {
    var key: String
    var hits = 0
    var misses = 0
    var latestTimeMS: Double?
    var bestTimeMS: Double?
    var samples: [AdaptiveLessonSample] = []
    var state: AdaptiveInclusionState = .excluded

    nonisolated mutating func append(
        timeMS: Double?,
        hits newHits: Int,
        misses newMisses: Int,
        date: Date,
        smoothingFactor: Double
    ) {
        hits += newHits
        misses += newMisses

        guard let timeMS, timeMS.isFinite, timeMS > 0 else { return }

        let filtered = latestTimeMS.map { previous in
            previous + ((timeMS - previous) * smoothingFactor)
        } ?? timeMS

        latestTimeMS = filtered
        bestTimeMS = min(bestTimeMS ?? filtered, filtered)
        samples.append(AdaptiveLessonSample(date: date, filteredTimeMS: filtered))
    }

    nonisolated func confidence(targetWPM: Double) -> Double? {
        guard let latestTimeMS else { return nil }
        return AdaptiveAggregate.targetTimeMS(targetWPM: targetWPM) / latestTimeMS
    }

    nonisolated func bestConfidence(targetWPM: Double) -> Double? {
        guard let bestTimeMS else { return nil }
        return AdaptiveAggregate.targetTimeMS(targetWPM: targetWPM) / bestTimeMS
    }
}

private struct AdaptiveAggregate {
    let orderedLetters: [Character]
    let targetWPM: Double
    let smoothingFactor: Double

    nonisolated static func targetTimeMS(targetWPM: Double) -> Double {
        60_000 / (targetWPM * 5)
    }

    nonisolated func emptyProfiles() -> [String: AdaptiveMutableKeyProfile] {
        Dictionary(uniqueKeysWithValues: orderedLetters.map {
            (String($0), AdaptiveMutableKeyProfile(key: String($0)))
        })
    }

    nonisolated func consume(result: AdaptiveHistoryResult, into map: inout [String: AdaptiveMutableKeyProfile]) {
        guard let payload = result.adaptivePayload else { return }
        for stat in payload.keyStats {
            var mutable = map[stat.key, default: AdaptiveMutableKeyProfile(key: stat.key)]
            mutable.append(
                timeMS: stat.timeToTypeMS,
                hits: stat.hitCount,
                misses: stat.missCount,
                date: result.date,
                smoothingFactor: smoothingFactor
            )
            map[stat.key] = mutable
        }
    }

    nonisolated func consume(results: [AdaptiveHistoryResult]) -> [String: AdaptiveMutableKeyProfile] {
        var map = emptyProfiles()

        for result in chronologicallySortedIfNeeded(results) {
            consume(result: result, into: &map)
        }

        return map
    }
}

nonisolated private func chronologicallySortedIfNeeded(_ results: [AdaptiveHistoryResult]) -> [AdaptiveHistoryResult] {
    guard results.count > 1 else { return results }
    for index in 1..<results.count where results[index - 1].date > results[index].date {
        return results.sorted(by: { $0.date < $1.date })
    }
    return results
}

private struct AdaptiveKeyboardKey {
    var key: String
    var row: AdaptiveKeyboardRow
    var hand: AdaptiveKeyboardHand
    var finger: AdaptiveKeyboardFinger
}

private enum AdaptiveKeyboardRow {
    case top
    case home
    case bottom
}

private enum AdaptiveKeyboardHand: Equatable {
    case left
    case right

    nonisolated static func == (lhs: AdaptiveKeyboardHand, rhs: AdaptiveKeyboardHand) -> Bool {
        switch (lhs, rhs) {
        case (.left, .left), (.right, .right):
            return true
        default:
            return false
        }
    }
}

private enum AdaptiveKeyboardFinger: Equatable {
    case pinky
    case ring
    case middle
    case leftIndex
    case rightIndex

    nonisolated static func == (lhs: AdaptiveKeyboardFinger, rhs: AdaptiveKeyboardFinger) -> Bool {
        switch (lhs, rhs) {
        case (.pinky, .pinky), (.ring, .ring), (.middle, .middle), (.leftIndex, .leftIndex), (.rightIndex, .rightIndex):
            return true
        default:
            return false
        }
    }
}

private enum AdaptivePunctuationDecoration: Sendable {
    case append(String)
    case wrap(String, String)
    case join(String)
}

private struct AdaptiveKeyboardLayout {
    nonisolated let rows: [[String]]
    private let keys: [String: AdaptiveKeyboardKey]
    private let punctuationDecorations: [AdaptivePunctuationDecoration]
    private let digits: [String]

    nonisolated init(
        rows: [[String]],
        definitions: [(AdaptiveKeyboardRow, [(String, AdaptiveKeyboardHand, AdaptiveKeyboardFinger)])],
        punctuationDecorations: [AdaptivePunctuationDecoration] = Self.defaultPunctuationDecorations,
        digits: [String] = Self.defaultDigits
    ) {
        self.rows = rows
        self.punctuationDecorations = punctuationDecorations
        self.digits = digits
        var map: [String: AdaptiveKeyboardKey] = [:]
        for (row, values) in definitions {
            for (key, hand, finger) in values {
                map[key] = AdaptiveKeyboardKey(key: key, row: row, hand: hand, finger: finger)
            }
        }
        self.keys = map
    }

    nonisolated static func layout(for option: KeyboardLayoutOption) -> AdaptiveKeyboardLayout {
        switch option {
        case .qwerty:
            return AdaptiveKeyboardLayout(
                rows: KeyboardLayoutOption.qwerty.rows,
                definitions: [
                    (.top, commonNumberRow()),
                    (.top, [
                        ("`", .left, .pinky),
                        ("-", .right, .pinky),
                        ("=", .right, .pinky),
                        ("q", .left, .pinky),
                        ("w", .left, .ring),
                        ("e", .left, .middle),
                        ("r", .left, .leftIndex),
                        ("t", .left, .leftIndex),
                        ("y", .right, .rightIndex),
                        ("u", .right, .rightIndex),
                        ("i", .right, .middle),
                        ("o", .right, .ring),
                        ("p", .right, .pinky),
                        ("[", .right, .pinky),
                        ("]", .right, .pinky),
                        ("\\", .right, .pinky),
                    ]),
                    (.home, [
                        ("a", .left, .pinky),
                        ("s", .left, .ring),
                        ("d", .left, .middle),
                        ("f", .left, .leftIndex),
                        ("g", .left, .leftIndex),
                        ("h", .right, .rightIndex),
                        ("j", .right, .rightIndex),
                        ("k", .right, .middle),
                        ("l", .right, .ring),
                        (";", .right, .pinky),
                        ("'", .right, .pinky),
                    ]),
                    (.bottom, [
                        ("z", .left, .pinky),
                        ("x", .left, .ring),
                        ("c", .left, .middle),
                        ("v", .left, .leftIndex),
                        ("b", .left, .leftIndex),
                        ("n", .right, .rightIndex),
                        ("m", .right, .rightIndex),
                        (",", .right, .middle),
                        (".", .right, .ring),
                        ("/", .right, .pinky),
                    ]),
                ],
                punctuationDecorations: [
                    .append("!"),
                    .wrap("\"", "\""),
                    .wrap("'", "'"),
                    .append(","),
                    .join("-"),
                    .append("."),
                    .append(":"),
                    .append(";"),
                    .append("?")
                ]
            )
        case .qwertyUk:
            return AdaptiveKeyboardLayout(
                rows: KeyboardLayoutOption.qwertyUk.rows,
                definitions: [
                    (.top, commonNumberRow()),
                    (.top, [
                        ("`", .left, .pinky),
                        ("-", .right, .pinky),
                        ("=", .right, .pinky),
                        ("q", .left, .pinky),
                        ("w", .left, .ring),
                        ("e", .left, .middle),
                        ("r", .left, .leftIndex),
                        ("t", .left, .leftIndex),
                        ("y", .right, .rightIndex),
                        ("u", .right, .rightIndex),
                        ("i", .right, .middle),
                        ("o", .right, .ring),
                        ("p", .right, .pinky),
                        ("[", .right, .pinky),
                        ("]", .right, .pinky),
                    ]),
                    (.home, [
                        ("a", .left, .pinky),
                        ("s", .left, .ring),
                        ("d", .left, .middle),
                        ("f", .left, .leftIndex),
                        ("g", .left, .leftIndex),
                        ("h", .right, .rightIndex),
                        ("j", .right, .rightIndex),
                        ("k", .right, .middle),
                        ("l", .right, .ring),
                        (";", .right, .pinky),
                        ("'", .right, .pinky),
                        ("#", .right, .pinky),
                    ]),
                    (.bottom, [
                        ("\\", .left, .pinky),
                        ("z", .left, .pinky),
                        ("x", .left, .ring),
                        ("c", .left, .middle),
                        ("v", .left, .leftIndex),
                        ("b", .left, .leftIndex),
                        ("n", .right, .rightIndex),
                        ("m", .right, .rightIndex),
                        (",", .right, .middle),
                        (".", .right, .ring),
                        ("/", .right, .pinky),
                    ]),
                ],
                punctuationDecorations: [
                    .append("!"),
                    .wrap("\"", "\""),
                    .wrap("'", "'"),
                    .append("£"),
                    .append("#"),
                    .append("@"),
                    .append(","),
                    .join("-"),
                    .append("."),
                    .append(":"),
                    .append(";"),
                    .append("?")
                ]
            )
        case .colemak:
            return AdaptiveKeyboardLayout(
                rows: KeyboardLayoutOption.colemak.rows,
                definitions: [
                    (.top, commonNumberRow()),
                    (.top, [
                        ("`", .left, .pinky),
                        ("-", .right, .pinky),
                        ("=", .right, .pinky),
                        ("q", .left, .pinky),
                        ("w", .left, .ring),
                        ("f", .left, .middle),
                        ("p", .left, .leftIndex),
                        ("g", .left, .leftIndex),
                        ("j", .right, .rightIndex),
                        ("l", .right, .rightIndex),
                        ("u", .right, .middle),
                        ("y", .right, .ring),
                        (";", .right, .pinky),
                        ("[", .right, .pinky),
                        ("]", .right, .pinky),
                        ("\\", .right, .pinky),
                    ]),
                    (.home, [
                        ("a", .left, .pinky),
                        ("r", .left, .ring),
                        ("s", .left, .middle),
                        ("t", .left, .leftIndex),
                        ("d", .left, .leftIndex),
                        ("h", .right, .rightIndex),
                        ("n", .right, .rightIndex),
                        ("e", .right, .middle),
                        ("i", .right, .ring),
                        ("o", .right, .pinky),
                        ("'", .right, .pinky),
                    ]),
                    (.bottom, [
                        ("z", .left, .pinky),
                        ("x", .left, .ring),
                        ("c", .left, .middle),
                        ("v", .left, .leftIndex),
                        ("b", .left, .leftIndex),
                        ("k", .right, .rightIndex),
                        ("m", .right, .rightIndex),
                        (",", .right, .middle),
                        (".", .right, .ring),
                        ("/", .right, .pinky),
                    ]),
                ],
                punctuationDecorations: [
                    .append("!"),
                    .wrap("\"", "\""),
                    .wrap("'", "'"),
                    .append(","),
                    .join("-"),
                    .append("."),
                    .append(":"),
                    .append(";"),
                    .append("?")
                ]
            )
        case .dvorak:
            return AdaptiveKeyboardLayout(
                rows: KeyboardLayoutOption.dvorak.rows,
                definitions: [
                    (.top, commonNumberRow()),
                    (.top, [
                        ("`", .left, .pinky),
                        ("[", .right, .ring),
                        ("]", .right, .pinky),
                        ("'", .left, .pinky),
                        (",", .left, .ring),
                        (".", .left, .middle),
                        ("p", .left, .leftIndex),
                        ("y", .left, .leftIndex),
                        ("f", .right, .rightIndex),
                        ("g", .right, .rightIndex),
                        ("c", .right, .middle),
                        ("r", .right, .ring),
                        ("l", .right, .pinky),
                        ("/", .right, .pinky),
                        ("=", .right, .pinky),
                        ("\\", .right, .pinky),
                    ]),
                    (.home, [
                        ("a", .left, .pinky),
                        ("o", .left, .ring),
                        ("e", .left, .middle),
                        ("u", .left, .leftIndex),
                        ("i", .left, .leftIndex),
                        ("d", .right, .rightIndex),
                        ("h", .right, .rightIndex),
                        ("t", .right, .middle),
                        ("n", .right, .ring),
                        ("s", .right, .pinky),
                        ("-", .right, .pinky),
                    ]),
                    (.bottom, [
                        (";", .left, .pinky),
                        ("q", .left, .ring),
                        ("j", .left, .middle),
                        ("k", .left, .leftIndex),
                        ("x", .left, .leftIndex),
                        ("b", .right, .rightIndex),
                        ("m", .right, .rightIndex),
                        ("w", .right, .middle),
                        ("v", .right, .ring),
                        ("z", .right, .pinky),
                    ]),
                ],
                punctuationDecorations: [
                    .append("!"),
                    .wrap("\"", "\""),
                    .wrap("'", "'"),
                    .append(","),
                    .join("-"),
                    .append("."),
                    .append(":"),
                    .append(";"),
                    .append("?")
                ]
            )
        }
    }

    nonisolated func randomDigit<T: RandomNumberGenerator>(using generator: inout T) -> String {
        digits.randomElement(using: &generator) ?? "0"
    }

    nonisolated var supportedCharacters: Set<Character> {
        Set(
            rows
                .flatMap(\.self)
                .compactMap(\.first)
        )
    }

    nonisolated func randomPunctuationDecoration<T: RandomNumberGenerator>(
        using generator: inout T
    ) -> AdaptivePunctuationDecoration {
        punctuationDecorations.randomElement(using: &generator) ?? Self.defaultPunctuationDecorations[0]
    }

    nonisolated func snapshot(
        for keyProfiles: [AdaptiveKeyProfile],
        results: [AdaptiveHistoryResult]
    ) -> AdaptiveKeyboardSnapshot {
        let intensity = Dictionary(uniqueKeysWithValues: keyProfiles.map { profile in
            let activity = Double(profile.samples + profile.hits + profile.misses)
            let weakness = profile.needScore
            return (profile.key, activity > 0 ? min(1, (weakness * 0.7) + (activity / 120.0)) : weakness)
        })

        var homeCount = 0.0
        var topCount = 0.0
        var bottomCount = 0.0
        var totalCount = 0.0

        for profile in keyProfiles {
            guard let key = keys[profile.key] else { continue }
            let count = Double(profile.hits + profile.misses)
            totalCount += count
            switch key.row {
            case .home: homeCount += count
            case .top: topCount += count
            case .bottom: bottomCount += count
            }
        }

        var sameHandCount = 0.0
        var sameFingerCount = 0.0
        var transitionTotal = 0.0

        for result in results {
            guard let payload = result.adaptivePayload else { continue }
            for transition in payload.transitions {
                guard let from = keys[transition.fromKey],
                      let to = keys[transition.toKey] else { continue }
                let count = Double(transition.count)
                transitionTotal += count
                if from.hand == to.hand {
                    sameHandCount += count
                }
                if from.finger == to.finger {
                    sameFingerCount += count
                }
            }
        }

        return AdaptiveKeyboardSnapshot(
            homeRowRatio: totalCount > 0 ? homeCount / totalCount : 0,
            topRowRatio: totalCount > 0 ? topCount / totalCount : 0,
            bottomRowRatio: totalCount > 0 ? bottomCount / totalCount : 0,
            sameHandRatio: transitionTotal > 0 ? sameHandCount / transitionTotal : 0,
            sameFingerRatio: transitionTotal > 0 ? sameFingerCount / transitionTotal : 0,
            keyIntensity: intensity
        )
    }

    nonisolated func keyboardOrderWeight(for key: String) -> Int {
        guard let mapped = keys[key] else { return 1_000 }
        switch mapped.row {
        case .home:
            return 1
        case .top:
            return 2
        case .bottom:
            return 1_000
        }
    }

    nonisolated func unlockPriority(for key: String) -> Double {
        guard let mapped = keys[key] else { return 0 }

        let rowWeight: Double
        switch mapped.row {
        case .home:
            rowWeight = 1.0
        case .top:
            rowWeight = 0.76
        case .bottom:
            rowWeight = 0.68
        }

        let fingerWeight: Double
        switch mapped.finger {
        case .leftIndex, .rightIndex:
            fingerWeight = 1.0
        case .middle:
            fingerWeight = 0.88
        case .ring:
            fingerWeight = 0.72
        case .pinky:
            fingerWeight = 0.54
        }

        return (rowWeight * 1.2) + fingerWeight
    }

    nonisolated private static let defaultDigits = Array("0123456789").map(String.init)

    nonisolated private static let defaultPunctuationDecorations: [AdaptivePunctuationDecoration] = [
        .append("!"),
        .wrap("\"", "\""),
        .wrap("'", "'"),
        .append(","),
        .join("-"),
        .append("."),
        .append(":"),
        .append(";"),
        .append("?")
    ]

    nonisolated private static func commonNumberRow() -> [(String, AdaptiveKeyboardHand, AdaptiveKeyboardFinger)] {
        [
            ("1", .left, .pinky),
            ("2", .left, .ring),
            ("3", .left, .middle),
            ("4", .left, .leftIndex),
            ("5", .left, .leftIndex),
            ("6", .right, .rightIndex),
            ("7", .right, .rightIndex),
            ("8", .right, .middle),
            ("9", .right, .ring),
            ("0", .right, .pinky),
        ]
    }
}
