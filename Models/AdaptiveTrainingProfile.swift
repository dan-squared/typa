import Foundation

struct TrainingProfileSession: Equatable, Sendable, Identifiable {
    let deduplicationKey: HistoryTransferDeduplicationKey
    let date: Date
    let mode: String
    let modeDescriptor: TypingResultModeDescriptor
    let duration: TimeInterval
    let words: Int
    let wpm: Double
    let accuracy: Double
    let errors: Int
    let rawInput: String
    let adaptivePayload: AdaptiveSessionPayload?

    nonisolated var id: String {
        deduplicationKey.stableID
    }

    nonisolated init(
        deduplicationKey: HistoryTransferDeduplicationKey? = nil,
        date: Date,
        mode: String,
        modeDescriptor: TypingResultModeDescriptor,
        duration: TimeInterval,
        words: Int,
        wpm: Double,
        accuracy: Double,
        errors: Int,
        rawInput: String,
        adaptivePayload: AdaptiveSessionPayload?
    ) {
        self.date = date
        self.mode = mode
        self.modeDescriptor = modeDescriptor
        self.duration = duration
        self.words = words
        self.wpm = wpm
        self.accuracy = accuracy
        self.errors = errors
        self.rawInput = rawInput
        self.adaptivePayload = adaptivePayload
        self.deduplicationKey = deduplicationKey ?? HistoryTransferSession(
            date: date,
            mode: mode,
            duration: duration,
            words: words,
            wpm: wpm,
            accuracy: accuracy,
            rawInput: rawInput,
            errors: errors,
            adaptivePayloadJSON: adaptivePayload.flatMap(AdaptiveTypingEngine.encodedPayload)
        ).deduplicationKey
    }

    nonisolated var contributesToAdaptiveProfile: Bool {
        modeDescriptor.contributesToAdaptiveProfile && adaptivePayload != nil
    }

    nonisolated var adaptiveHistoryResult: AdaptiveHistoryResult {
        AdaptiveHistoryResult(
            date: date,
            wpm: wpm,
            accuracy: accuracy,
            adaptivePayload: adaptivePayload,
            contributesToAdaptiveProfile: contributesToAdaptiveProfile
        )
    }

    nonisolated var historyTransferSession: HistoryTransferSession {
        HistoryTransferSession(
            date: date,
            mode: mode,
            duration: duration,
            words: words,
            wpm: wpm,
            accuracy: accuracy,
            rawInput: rawInput,
            errors: errors,
            adaptivePayloadJSON: adaptivePayload.flatMap(AdaptiveTypingEngine.encodedPayload)
        )
    }
}

struct TrainingGoalSnapshot: Equatable, Sendable {
    var targetMinutes: Int
    var completedMinutes: Int
    var progress: Double
    var isComplete: Bool
}

enum TrainingProfileEventKind: String, Equatable, Sendable {
    case unlockedKey
    case newBestSpeed
    case dailyGoal
    case streak
}

struct TrainingProfileEvent: Identifiable, Equatable, Sendable {
    var id: String { "\(kind.rawValue)|\(date.timeIntervalSinceReferenceDate)|\(title)" }

    var date: Date
    var kind: TrainingProfileEventKind
    var title: String
    var detail: String
}

struct AdaptiveTransitionDetail: Identifiable, Equatable, Sendable {
    var id: String { pair }

    var pair: String
    var count: Int
    var averageTimeMS: Double
}

struct AdaptiveKeyDetail: Identifiable, Equatable, Sendable {
    var id: String { key }

    var key: String
    var stateLabel: String
    var confidence: Double?
    var bestConfidence: Double?
    var accuracy: Double
    var latestTimeMS: Double?
    var bestTimeMS: Double?
    var hits: Int
    var misses: Int
    var sampleCount: Int
    var needScore: Double
    var incomingTransitions: [AdaptiveTransitionDetail]
    var outgoingTransitions: [AdaptiveTransitionDetail]
}

struct AdaptiveLastLessonFeedback: Equatable, Sendable {
    var focusedKey: String?
    var activeAlphabetSize: Int
    var totalHits: Int
    var totalMisses: Int
    var stepCount: Int
    var topMisses: [AdaptiveSessionKeyStat]
    var topTransitions: [AdaptiveSessionTransitionStat]
    var topMissedDigraphs: [AdaptiveSessionDigraphStat]
    var correctionHotspots: [AdaptiveSessionCorrectionStat]

    nonisolated static func make(from payload: AdaptiveSessionPayload) -> AdaptiveLastLessonFeedback {
        let sortedMisses = payload.keyStats
            .sorted {
                if $0.missCount == $1.missCount {
                    return $0.key < $1.key
                }
                return $0.missCount > $1.missCount
            }
            .filter { $0.missCount > 0 }

        let sortedTransitions = payload.transitions
            .sorted {
                if $0.averageTimeMS == $1.averageTimeMS {
                    return ($0.fromKey, $0.toKey) < ($1.fromKey, $1.toKey)
                }
                return $0.averageTimeMS > $1.averageTimeMS
            }

        return AdaptiveLastLessonFeedback(
            focusedKey: payload.lesson.focusedKey,
            activeAlphabetSize: payload.lesson.activeAlphabet.count,
            totalHits: payload.keyStats.reduce(0) { $0 + $1.hitCount },
            totalMisses: payload.keyStats.reduce(0) { $0 + $1.missCount },
            stepCount: payload.telemetry?.steps.count ?? 0,
            topMisses: Array(sortedMisses.prefix(3)),
            topTransitions: Array(sortedTransitions.prefix(3)),
            topMissedDigraphs: Array((payload.telemetry?.missedDigraphs ?? []).prefix(3)),
            correctionHotspots: Array((payload.telemetry?.correctionHotspots ?? []).prefix(3))
        )
    }
}

struct AdaptiveProgressOverviewColumn: Identifiable, Equatable, Sendable {
    var id: Int
    var date: Date
    var focusedKey: String?
    var activeAlphabetSize: Int
}

struct AdaptiveProgressOverviewSample: Identifiable, Equatable, Sendable {
    var id: String { "\(sessionIndex)|\(key)" }

    var sessionIndex: Int
    var key: String
    var confidence: Double?
    var bestConfidence: Double?
    var isActive: Bool
    var isFocused: Bool
}

struct AdaptiveProgressOverviewRow: Identifiable, Equatable, Sendable {
    var id: String { key }

    var key: String
    var samples: [AdaptiveProgressOverviewSample]
}

struct AdaptiveProgressOverviewSnapshot: Equatable, Sendable {
    var columns: [AdaptiveProgressOverviewColumn]
    var rows: [AdaptiveProgressOverviewRow]

    nonisolated static let empty = AdaptiveProgressOverviewSnapshot(
        columns: [],
        rows: []
    )
}

struct AdaptiveTrainingProfileSnapshot: Equatable, Sendable {
    var analysis: AdaptiveAnalysisSnapshot
    var sessions: [TrainingProfileSession]
    var keyDetails: [AdaptiveKeyDetail]
    var progressOverview: AdaptiveProgressOverviewSnapshot
    var recentEvents: [TrainingProfileEvent]
    var streakDays: Int
    var dailyGoal: TrainingGoalSnapshot
    var lastLessonFeedback: AdaptiveLastLessonFeedback?

    static let empty = AdaptiveTrainingProfileSnapshot(
        analysis: .empty,
        sessions: [],
        keyDetails: [],
        progressOverview: .empty,
        recentEvents: [],
        streakDays: 0,
        dailyGoal: TrainingGoalSnapshot(targetMinutes: AppSettings.default.dailyGoalMinutes, completedMinutes: 0, progress: 0, isComplete: false),
        lastLessonFeedback: nil
    )

    func detail(for key: String?) -> AdaptiveKeyDetail? {
        guard let key else { return nil }
        return keyDetails.first(where: { $0.key == key })
    }

    var suggestedFocusKey: String? {
        analysis.currentLesson.focusedKey
            ?? analysis.weakestKeys.first?.key
            ?? keyDetails.first(where: { $0.sampleCount > 0 || $0.misses > 0 })?.key
            ?? analysis.allKeys.first?.key
    }
}

struct AdaptiveTrainingRuntimeSnapshot: Equatable, Sendable {
    var configuration: AdaptiveRuntimeConfigurationSnapshot
    var sessions: [TrainingProfileSession]
    var adaptiveHistoryResults: [AdaptiveHistoryResult]
    var analysis: AdaptiveAnalysisSnapshot
    var lessonGenerationContext: AdaptiveLessonGenerationContext
    var recentEvents: [TrainingProfileEvent]
    var allEvents: [TrainingProfileEvent]
    var streakDays: Int
    var dailyGoal: TrainingGoalSnapshot
    var lastLessonFeedback: AdaptiveLastLessonFeedback?

    static let empty = AdaptiveTrainingRuntimeSnapshot(
        configuration: .default,
        sessions: [],
        adaptiveHistoryResults: [],
        analysis: .empty,
        lessonGenerationContext: .empty,
        recentEvents: [],
        allEvents: [],
        streakDays: 0,
        dailyGoal: TrainingGoalSnapshot(
            targetMinutes: AppSettings.default.dailyGoalMinutes,
            completedMinutes: 0,
            progress: 0,
            isComplete: false
        ),
        lastLessonFeedback: nil
    )
}

struct AdaptiveRuntimeConfigurationSnapshot: Equatable, Sendable {
    var language: Language
    var dailyGoalMinutes: Int
    var adaptiveTargetWPM: Double
    var adaptiveAlphabetScale: Double
    var adaptiveRecoverKeys: Bool
    var adaptiveUnlockStrategy: AdaptiveUnlockStrategy
    var keyboardLayoutFamily: KeyboardLayoutFamily

    nonisolated static let `default` = AdaptiveRuntimeConfigurationSnapshot(
        settings: .default,
        language: .english
    )

    nonisolated init(settings: AppSettings, language: Language) {
        self.language = language
        self.dailyGoalMinutes = settings.dailyGoalMinutes
        self.adaptiveTargetWPM = settings.adaptiveTargetWPM
        self.adaptiveAlphabetScale = settings.adaptiveAlphabetScale
        self.adaptiveRecoverKeys = settings.adaptiveRecoverKeys
        self.adaptiveUnlockStrategy = settings.adaptiveUnlockStrategy
        self.keyboardLayoutFamily = settings.keyboardLayoutFamily
    }
}

struct NormalizedTypingResultDraft: Sendable {
    let date: Date
    let mode: String
    let modeDescriptor: TypingResultModeDescriptor
    let duration: TimeInterval
    let words: Int
    let wpm: Double
    let accuracy: Double
    let rawInput: String
    let errors: Int
    let adaptivePayload: AdaptiveSessionPayload?
    let adaptivePayloadJSON: String?

    nonisolated var trainingProfileSession: TrainingProfileSession {
        TrainingProfileSession(
            deduplicationKey: historyTransferSession.deduplicationKey,
            date: date,
            mode: mode,
            modeDescriptor: modeDescriptor,
            duration: duration,
            words: words,
            wpm: wpm,
            accuracy: accuracy,
            errors: errors,
            rawInput: rawInput,
            adaptivePayload: adaptivePayload
        )
    }

    nonisolated var historyTransferSession: HistoryTransferSession {
        HistoryTransferSession(
            date: date,
            mode: mode,
            duration: duration,
            words: words,
            wpm: wpm,
            accuracy: accuracy,
            rawInput: rawInput,
            errors: errors,
            adaptivePayloadJSON: adaptivePayloadJSON
        )
    }

    nonisolated var deduplicationKey: HistoryTransferDeduplicationKey {
        historyTransferSession.deduplicationKey
    }
}

enum TypingResultDiscardReason: String, Equatable, Hashable, Sendable, Codable {
    case missingAdaptiveTelemetry
    case sessionTooShort
    case insufficientKeyVariety
    case unrealisticSpeed
    case malformedSession

    var summaryLabel: String {
        switch self {
        case .missingAdaptiveTelemetry:
            return "missing telemetry"
        case .sessionTooShort:
            return "too short"
        case .insufficientKeyVariety:
            return "low variety"
        case .unrealisticSpeed:
            return "unrealistic speed"
        case .malformedSession:
            return "malformed"
        }
    }
}

struct TypingResultNormalizationOutcome: Sendable {
    var draft: NormalizedTypingResultDraft?
    var discardReason: TypingResultDiscardReason?
    var wasRepaired: Bool
}

struct TypingResultValidationError: Error, Equatable, Sendable, LocalizedError {
    var message: String

    var errorDescription: String? {
        message
    }
}

enum TypingResultRecovery {
    nonisolated static func normalizedSession(result: TypingResult) -> TrainingProfileSession? {
        normalizedTrainingProfileSession(HistoryTransferSession(result: result))
    }

    nonisolated static func normalizedSession(_ session: HistoryTransferSession, now: Date = .now) -> HistoryTransferSession? {
        normalizedOutcome(for: session, now: now).draft?.historyTransferSession
    }

    nonisolated static func normalizedTrainingProfileSession(
        _ session: HistoryTransferSession,
        now: Date = .now
    ) -> TrainingProfileSession? {
        normalizedOutcome(for: session, now: now).draft?.trainingProfileSession
    }

    nonisolated static func normalizedOutcome(
        for session: HistoryTransferSession,
        now: Date = .now
    ) -> TypingResultNormalizationOutcome {
        let modeDescriptor = TypingResultModeDescriptor.parse(
            mode: session.mode,
            adaptivePayloadJSON: session.adaptivePayloadJSON
        )
        guard let normalized = normalizedDraft(
            date: session.date,
            mode: session.mode,
            duration: session.duration,
            words: session.words,
            wpm: session.wpm,
            accuracy: session.accuracy,
            rawInput: session.rawInput,
            errors: session.errors,
            adaptivePayloadJSON: session.adaptivePayloadJSON,
            now: now
        ) else {
            return TypingResultNormalizationOutcome(
                draft: nil,
                discardReason: modeDescriptor.sessionMode == .learning
                    ? ((session.adaptivePayloadJSON?.isEmpty ?? true) ? .missingAdaptiveTelemetry : .malformedSession)
                    : .malformedSession,
                wasRepaired: false
            )
        }

        if normalized.modeDescriptor.sessionMode == .learning,
           let discardReason = learningValidationDiscardReason(for: normalized) {
            return TypingResultNormalizationOutcome(
                draft: nil,
                discardReason: discardReason,
                wasRepaired: false
            )
        }

        return TypingResultNormalizationOutcome(
            draft: normalized,
            discardReason: nil,
            wasRepaired: normalized.historyTransferSession != session
        )
    }

    nonisolated static func validatedLocalDraft(
        date: Date,
        mode: String,
        duration: TimeInterval,
        words: Int,
        wpm: Double,
        accuracy: Double,
        rawInput: String,
        errors: Int,
        adaptivePayload: AdaptiveSessionPayload?,
        now: Date = .now
    ) -> Result<NormalizedTypingResultDraft, TypingResultValidationError> {
        let payloadJSON = adaptivePayload.flatMap { encodePayload(normalizedPayload($0) ?? $0) }
        let outcome = normalizedOutcome(
            for: HistoryTransferSession(
                date: date,
                mode: mode,
                duration: duration,
                words: words,
                wpm: wpm,
                accuracy: accuracy,
                rawInput: rawInput,
                errors: errors,
                adaptivePayloadJSON: payloadJSON
            ),
            now: now
        )

        if let draft = outcome.draft {
            return .success(draft)
        }

        return .failure(
            TypingResultValidationError(
                message: localLearningValidationFailureMessage(for: outcome.discardReason)
            )
        )
    }

    nonisolated private static func normalizedDraft(
        date: Date,
        mode: String,
        duration: TimeInterval,
        words: Int,
        wpm: Double,
        accuracy: Double,
        rawInput: String,
        errors: Int,
        adaptivePayloadJSON: String?,
        now: Date
    ) -> NormalizedTypingResultDraft? {
        let recoveredPayload = normalizedPayload(from: adaptivePayloadJSON)
        let recoveredPayloadJSON = recoveredPayload.flatMap { payload in
            encodePayload(payload)
        }
        let descriptor = TypingResultModeDescriptor.parse(
            mode: mode,
            adaptivePayloadJSON: recoveredPayloadJSON
        )

        let normalizedMode: String
        if descriptor.sessionMode == .learning {
            normalizedMode = SessionMode.learning.rawValue
        } else {
            let length = descriptor.testLengthMode ?? .words
            let content = descriptor.testContentMode ?? .commonWords
            normalizedMode = "test:\(length.rawValue):\(content.rawValue)"
        }

        let normalizedAccuracy = min(100, max(0, accuracy.isFinite ? accuracy : 0))
        let normalizedWPM = min(320, max(0, wpm.isFinite ? wpm : 0))
        let normalizedErrors = max(0, errors)
        let normalizedRawInput = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDate = min(date, now.addingTimeInterval(86_400))

        let derivedWordsFromInput = normalizedRawInput.split(whereSeparator: \.isWhitespace).count
        let derivedWordsFromDuration = Int(((max(duration, 0) / 60.0) * max(1, normalizedWPM)).rounded())
        let normalizedWords = max(1, max(words, max(derivedWordsFromInput, derivedWordsFromDuration)))

        let normalizedDuration: TimeInterval
        if duration.isFinite, duration > 0 {
            normalizedDuration = min(duration, 7_200)
        } else if normalizedWPM > 0 {
            normalizedDuration = min(7_200, (Double(normalizedWords) / max(1, normalizedWPM)) * 60.0)
        } else {
            normalizedDuration = max(1, Double(normalizedWords) * 2.4)
        }

        if descriptor.sessionMode == .learning, recoveredPayload == nil {
            return nil
        }

        let normalizedDescriptor = TypingResultModeDescriptor.parse(
            mode: normalizedMode,
            adaptivePayloadJSON: recoveredPayloadJSON
        )

        return NormalizedTypingResultDraft(
            date: normalizedDate,
            mode: normalizedMode,
            modeDescriptor: normalizedDescriptor,
            duration: normalizedDuration,
            words: normalizedWords,
            wpm: normalizedWPM,
            accuracy: normalizedAccuracy,
            rawInput: normalizedRawInput,
            errors: normalizedErrors,
            adaptivePayload: normalizedDescriptor.sessionMode == .learning ? recoveredPayload : nil,
            adaptivePayloadJSON: normalizedDescriptor.sessionMode == .learning ? recoveredPayloadJSON : nil
        )
    }

    nonisolated private static func learningValidationDiscardReason(for draft: NormalizedTypingResultDraft) -> TypingResultDiscardReason? {
        guard let payload = draft.adaptivePayload else {
            return .missingAdaptiveTelemetry
        }

        let totalAttempts = payload.keyStats.reduce(0) { partial, stat in
            partial + stat.hitCount + stat.missCount
        }
        let uniqueKeys = Set(payload.keyStats.map(\.key)).count
        let fastestRecordedTime = payload.keyStats.compactMap(\.timeToTypeMS).min()

        if draft.duration < 12 || totalAttempts < 24 {
            return .sessionTooShort
        }

        if uniqueKeys < min(4, max(1, payload.lesson.activeAlphabet.count)) {
            return .insufficientKeyVariety
        }

        if draft.wpm > 220 || (fastestRecordedTime.map { $0 < 40 } ?? false) {
            return .unrealisticSpeed
        }

        return nil
    }

    nonisolated private static func localLearningValidationFailureMessage(for reason: TypingResultDiscardReason?) -> String {
        switch reason {
        case .missingAdaptiveTelemetry:
            return "Learning session was missing adaptive telemetry and was not saved."
        case .sessionTooShort:
            return "Learning session was too short to save."
        case .insufficientKeyVariety:
            return "Learning session did not include enough key variety to save."
        case .unrealisticSpeed:
            return "Learning session speed looked unrealistic and was ignored."
        case .malformedSession, .none:
            return "Session data was malformed and was not saved."
        }
    }

    nonisolated private static func normalizedPayload(from json: String?) -> AdaptiveSessionPayload? {
        guard let json,
              let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(AdaptiveSessionPayload.self, from: data) else {
            return nil
        }
        return normalizedPayload(payload)
    }

    nonisolated static func normalizedPayload(_ payload: AdaptiveSessionPayload?) -> AdaptiveSessionPayload? {
        guard let payload else { return nil }

        let activeAlphabet = Array(
            Set(payload.lesson.activeAlphabet.compactMap { normalizedKeyToken($0) })
        ).sorted()
        let focusedKey = payload.lesson.focusedKey.flatMap { normalizedKeyToken($0) }
        let forcedKeys = Array(Set(payload.lesson.forcedKeys.compactMap { normalizedKeyToken($0) })).sorted()

        let keyStats = payload.keyStats.compactMap { stat -> AdaptiveSessionKeyStat? in
            guard let key = normalizedKeyToken(stat.key) else { return nil }
            let hitCount = max(0, stat.hitCount)
            let missCount = max(0, stat.missCount)
            let timeToTypeMS: Double?
            if let value = stat.timeToTypeMS, value.isFinite, value > 0 {
                timeToTypeMS = min(10_000, value)
            } else {
                timeToTypeMS = nil
            }
            guard hitCount > 0 || missCount > 0 || timeToTypeMS != nil else { return nil }
            return AdaptiveSessionKeyStat(
                key: key,
                hitCount: hitCount,
                missCount: missCount,
                timeToTypeMS: timeToTypeMS
            )
        }

        let transitions = payload.transitions.compactMap { transition -> AdaptiveSessionTransitionStat? in
            guard let fromKey = normalizedKeyToken(transition.fromKey),
                  let toKey = normalizedKeyToken(transition.toKey) else {
                return nil
            }
            let count = max(0, transition.count)
            guard count > 0,
                  transition.averageTimeMS.isFinite,
                  transition.averageTimeMS > 0 else {
                return nil
            }
            return AdaptiveSessionTransitionStat(
                fromKey: fromKey,
                toKey: toKey,
                count: count,
                averageTimeMS: min(10_000, transition.averageTimeMS)
            )
        }

        let normalizedSteps = payload.telemetry?.steps.enumerated().compactMap { index, step -> AdaptiveSessionStep? in
            let expectedKey = step.expectedKey.flatMap { normalizedKeyToken($0) }
            let typedKey = step.typedKey.flatMap { normalizedKeyToken($0) }
            let previousExpectedKey = step.previousExpectedKey.flatMap { normalizedKeyToken($0) }

            switch step.kind {
            case .accepted:
                guard let expectedKey else { return nil }
                return AdaptiveSessionStep(
                    id: index,
                    kind: step.kind,
                    expectedKey: expectedKey,
                    typedKey: typedKey ?? expectedKey,
                    cursorIndex: max(0, step.cursorIndex),
                    timestampMS: max(0, step.timestampMS),
                    previousExpectedKey: previousExpectedKey
                )
            case .rejected, .corrected:
                guard let expectedKey else { return nil }
                return AdaptiveSessionStep(
                    id: index,
                    kind: step.kind,
                    expectedKey: expectedKey,
                    typedKey: typedKey,
                    cursorIndex: max(0, step.cursorIndex),
                    timestampMS: max(0, step.timestampMS),
                    previousExpectedKey: previousExpectedKey
                )
            }
        } ?? []
        let normalizedTelemetry = normalizedSteps.isEmpty ? nil : AdaptiveSessionTelemetry.build(from: normalizedSteps)

        guard !activeAlphabet.isEmpty || !keyStats.isEmpty else { return nil }

        return AdaptiveSessionPayload(
            lesson: AdaptiveLessonState(
                activeAlphabet: activeAlphabet,
                focusedKey: focusedKey,
                forcedKeys: forcedKeys,
                targetWPM: min(160, max(10, payload.lesson.targetWPM.isFinite ? payload.lesson.targetWPM : AdaptiveTypingEngine.defaults.targetWPM)),
                source: payload.lesson.source.isEmpty ? "adaptive" : payload.lesson.source
            ),
            keyStats: keyStats.sorted { $0.key < $1.key },
            transitions: transitions.sorted {
                if $0.count == $1.count {
                    return ($0.fromKey, $0.toKey) < ($1.fromKey, $1.toKey)
                }
                return $0.count > $1.count
            },
            telemetry: normalizedTelemetry
        )
    }

    nonisolated private static func encodePayload(_ payload: AdaptiveSessionPayload) -> String? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated private static func normalizedKeyToken(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count == 1 else { return nil }
        return trimmed
    }
}

struct AdaptiveProgressStore: Sendable {
    private(set) var sessions: [TrainingProfileSession] = []
    private(set) var adaptiveHistoryResults: [AdaptiveHistoryResult] = []
    private(set) var lastLessonFeedback: AdaptiveLastLessonFeedback?

    private var dailyGoalMinutes: Int
    private var learningDays: Set<Date> = []
    private var practiceDurationByDay: [Date: TimeInterval] = [:]
    private var unlockedKeys: Set<String> = []
    private var emittedDailyGoalDays: Set<Date> = []
    private var emittedStreaks: Set<Int> = []
    private var bestLearningWPM = 0.0
    private var events: [TrainingProfileEvent] = []

    private let calendar = Calendar.current

    nonisolated init(dailyGoalMinutes: Int = AppSettings.default.dailyGoalMinutes) {
        self.dailyGoalMinutes = dailyGoalMinutes
    }

    nonisolated mutating func append(_ session: TrainingProfileSession) {
        sessions.append(session)

        let day = calendar.startOfDay(for: session.date)
        let previousPracticeTime = practiceDurationByDay[day, default: 0]
        let updatedPracticeTime = previousPracticeTime + session.duration
        practiceDurationByDay[day] = updatedPracticeTime

        let goalSeconds = TimeInterval(dailyGoalMinutes * 60)
        if dailyGoalMinutes > 0,
           previousPracticeTime < goalSeconds,
           updatedPracticeTime >= goalSeconds,
           emittedDailyGoalDays.insert(day).inserted {
            events.append(
                TrainingProfileEvent(
                    date: session.date,
                    kind: .dailyGoal,
                    title: "Daily Goal Reached",
                    detail: "\(dailyGoalMinutes) minutes completed"
                )
            )
        }

        guard session.modeDescriptor.sessionMode == .learning else {
            return
        }

        learningDays.insert(day)

        if session.contributesToAdaptiveProfile {
            adaptiveHistoryResults.append(session.adaptiveHistoryResult)
            if let payload = session.adaptivePayload {
                lastLessonFeedback = AdaptiveLastLessonFeedback.make(from: payload)

                let forcedKeys = Set(payload.lesson.forcedKeys)
                let unlockedLessonKeys = payload.lesson.activeAlphabet.filter { !forcedKeys.contains($0) }
                if unlockedKeys.isEmpty {
                    unlockedKeys.formUnion(unlockedLessonKeys)
                } else {
                    let newKeys = unlockedLessonKeys.filter { unlockedKeys.insert($0).inserted }
                    if !newKeys.isEmpty {
                        events.append(
                            TrainingProfileEvent(
                                date: session.date,
                                kind: .unlockedKey,
                                title: newKeys.count == 1 ? "New Key Unlocked" : "New Keys Unlocked",
                                detail: newKeys.map { $0.uppercased() }.joined(separator: " ")
                            )
                        )
                    }
                }
            }

            if session.wpm > bestLearningWPM + 0.5 {
                bestLearningWPM = session.wpm
                if adaptiveHistoryResults.count >= 3 {
                    events.append(
                        TrainingProfileEvent(
                            date: session.date,
                            kind: .newBestSpeed,
                            title: "New Best Speed",
                            detail: "\(Int(bestLearningWPM.rounded())) WPM in learning mode"
                        )
                    )
                }
            }
        }

        let streak = streakDays
        if streak >= 3,
           emittedStreaks.insert(streak).inserted {
            events.append(
                TrainingProfileEvent(
                    date: session.date,
                    kind: .streak,
                    title: "Streak Active",
                    detail: "\(streak)-day learning streak"
                )
            )
        }
    }

    nonisolated var streakDays: Int {
        guard !learningDays.isEmpty else { return 0 }

        var day = calendar.startOfDay(for: .now)
        var streak = 0
        while learningDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    nonisolated var dailyGoal: TrainingGoalSnapshot {
        let today = calendar.startOfDay(for: .now)
        let completedMinutes = Int((practiceDurationByDay[today, default: 0] / 60).rounded(.down))
        let progress = dailyGoalMinutes > 0
            ? min(1, Double(practiceDurationByDay[today, default: 0]) / Double(dailyGoalMinutes * 60))
            : 0
        return TrainingGoalSnapshot(
            targetMinutes: dailyGoalMinutes,
            completedMinutes: completedMinutes,
            progress: progress,
            isComplete: dailyGoalMinutes > 0 && progress >= 1
        )
    }

    nonisolated var allEvents: [TrainingProfileEvent] {
        events
    }

    nonisolated var recentEvents: [TrainingProfileEvent] {
        Array(events.sorted(by: { $0.date > $1.date }).prefix(8))
    }
}

enum AdaptiveTrainingRuntimeBuilder {
    nonisolated static func build(
        sessions: [HistoryTransferSession],
        language: Language,
        settings: AppSettings
    ) -> AdaptiveTrainingRuntimeSnapshot {
        snapshot(
            from: buildProgressStore(sessions: sessions, dailyGoalMinutes: settings.dailyGoalMinutes),
            language: language,
            settings: settings
        )
    }

    nonisolated static func build(
        sessions: [TrainingProfileSession],
        language: Language,
        settings: AppSettings
    ) -> AdaptiveTrainingRuntimeSnapshot {
        snapshot(
            from: buildProgressStore(sessions: sessions, dailyGoalMinutes: settings.dailyGoalMinutes),
            language: language,
            settings: settings
        )
    }

    nonisolated static func buildProgressStore(
        sessions: [HistoryTransferSession],
        dailyGoalMinutes: Int = AppSettings.default.dailyGoalMinutes
    ) -> AdaptiveProgressStore {
        buildProgressStore(
            sessions: sessions.compactMap { session in
                TypingResultRecovery.normalizedTrainingProfileSession(session)
            },
            dailyGoalMinutes: dailyGoalMinutes
        )
    }

    nonisolated static func buildProgressStore(
        sessions: [TrainingProfileSession],
        dailyGoalMinutes: Int = AppSettings.default.dailyGoalMinutes
    ) -> AdaptiveProgressStore {
        var progressStore = AdaptiveProgressStore(dailyGoalMinutes: dailyGoalMinutes)
        for session in sessionsOrderedByDateIfNeeded(sessions) {
            progressStore.append(session)
        }
        return progressStore
    }

    nonisolated static func appending(
        sessions: [HistoryTransferSession],
        to existing: AdaptiveProgressStore,
        dailyGoalMinutes: Int = AppSettings.default.dailyGoalMinutes
    ) -> AdaptiveProgressStore {
        var progressStore = existing
        for session in sessionsOrderedByDateIfNeeded(
            sessions.compactMap { TypingResultRecovery.normalizedTrainingProfileSession($0) }
        ) {
            progressStore.append(session)
        }
        return progressStore
    }

    nonisolated static func snapshot(
        from progressStore: AdaptiveProgressStore,
        language: Language,
        settings: AppSettings
    ) -> AdaptiveTrainingRuntimeSnapshot {
        let derived = AdaptiveTypingEngine.makeDerivedSnapshot(
            results: progressStore.adaptiveHistoryResults,
            language: language,
            settings: settings
        )
        let allEvents = AdaptiveTrainingProfileBuilder.enrichedEvents(
            from: progressStore.allEvents,
            analysis: derived.analysis,
            latestAdaptiveDate: progressStore.adaptiveHistoryResults.last?.date
        )
        return AdaptiveTrainingRuntimeSnapshot(
            configuration: AdaptiveRuntimeConfigurationSnapshot(settings: settings, language: language),
            sessions: progressStore.sessions,
            adaptiveHistoryResults: progressStore.adaptiveHistoryResults,
            analysis: derived.analysis,
            lessonGenerationContext: derived.lessonGenerationContext,
            recentEvents: AdaptiveTrainingProfileBuilder.recentEvents(from: allEvents),
            allEvents: allEvents,
            streakDays: progressStore.streakDays,
            dailyGoal: progressStore.dailyGoal,
            lastLessonFeedback: progressStore.lastLessonFeedback
        )
    }
}

enum AdaptiveTrainingProfileBuilder {
    nonisolated static func build(
        sessions: [HistoryTransferSession],
        language: Language,
        settings: AppSettings
    ) -> AdaptiveTrainingProfileSnapshot {
        build(
            runtime: AdaptiveTrainingRuntimeBuilder.build(
                sessions: sessions,
                language: language,
                settings: settings
            ),
            language: language,
            settings: settings
        )
    }

    nonisolated static func build(
        sessions: [TrainingProfileSession],
        language: Language,
        settings: AppSettings
    ) -> AdaptiveTrainingProfileSnapshot {
        build(
            runtime: AdaptiveTrainingRuntimeBuilder.build(
                sessions: sessions,
                language: language,
                settings: settings
            ),
            language: language,
            settings: settings
        )
    }

    nonisolated static func build(
        runtime: AdaptiveTrainingRuntimeSnapshot,
        language: Language,
        settings: AppSettings
    ) -> AdaptiveTrainingProfileSnapshot {
        let analysis = runtime.analysis
        let progressOverview = AdaptiveTypingEngine.makeProgressOverview(
            results: runtime.adaptiveHistoryResults,
            language: language,
            settings: settings
        )
        let transitions = aggregateTransitions(in: runtime.adaptiveHistoryResults)
        let keyDetails = makeKeyDetails(from: analysis, transitions: transitions)

        return AdaptiveTrainingProfileSnapshot(
            analysis: analysis,
            sessions: runtime.sessions,
            keyDetails: keyDetails,
            progressOverview: progressOverview,
            recentEvents: runtime.recentEvents,
            streakDays: runtime.streakDays,
            dailyGoal: runtime.dailyGoal,
            lastLessonFeedback: runtime.lastLessonFeedback
        )
    }

    nonisolated private static func aggregateTransitions(in results: [AdaptiveHistoryResult]) -> [AdaptiveTransitionInsight] {
        struct MutableTransition {
            var count = 0
            var totalTimeMS = 0.0
        }

        var totals: [String: MutableTransition] = [:]
        for result in results {
            guard let payload = result.adaptivePayload else { continue }
            for item in payload.transitions {
                let id = "\(item.fromKey)→\(item.toKey)"
                var current = totals[id, default: MutableTransition()]
                current.count += item.count
                current.totalTimeMS += item.averageTimeMS * Double(item.count)
                totals[id] = current
            }
        }

        return totals.compactMap { id, item in
            guard item.count > 0 else { return nil }
            let parts = id.split(separator: "→", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return AdaptiveTransitionInsight(
                fromKey: String(parts[0]),
                toKey: String(parts[1]),
                count: item.count,
                averageTimeMS: item.totalTimeMS / Double(item.count)
            )
        }
        .sorted {
            if $0.count == $1.count {
                return ($0.fromKey, $0.toKey) < ($1.fromKey, $1.toKey)
            }
            return $0.count > $1.count
        }
    }

    nonisolated private static func makeKeyDetails(
        from analysis: AdaptiveAnalysisSnapshot,
        transitions: [AdaptiveTransitionInsight]
    ) -> [AdaptiveKeyDetail] {
        analysis.allKeys.map { key in
            let incoming = transitions
                .filter { $0.toKey == key.key }
                .prefix(3)
                .map {
                    AdaptiveTransitionDetail(
                        pair: $0.fromKey.uppercased() + $0.toKey.uppercased(),
                        count: $0.count,
                        averageTimeMS: $0.averageTimeMS
                    )
                }
            let outgoing = transitions
                .filter { $0.fromKey == key.key }
                .prefix(3)
                .map {
                    AdaptiveTransitionDetail(
                        pair: $0.fromKey.uppercased() + $0.toKey.uppercased(),
                        count: $0.count,
                        averageTimeMS: $0.averageTimeMS
                    )
                }

            let stateLabel: String
            if key.isFocused {
                stateLabel = "Focus"
            } else if key.isForced {
                stateLabel = "Forced"
            } else if key.isIncluded {
                stateLabel = "Active"
            } else if key.samples > 0 || key.misses > 0 {
                stateLabel = "Learned"
            } else {
                stateLabel = "Queued"
            }

            return AdaptiveKeyDetail(
                key: key.key,
                stateLabel: stateLabel,
                confidence: key.confidence,
                bestConfidence: key.bestConfidence,
                accuracy: key.accuracy,
                latestTimeMS: key.latestTimeMS,
                bestTimeMS: key.bestTimeMS,
                hits: key.hits,
                misses: key.misses,
                sampleCount: key.samples,
                needScore: key.needScore,
                incomingTransitions: Array(incoming),
                outgoingTransitions: Array(outgoing)
            )
        }
        .sorted {
            if abs($0.needScore - $1.needScore) < 0.0001 {
                return $0.key < $1.key
            }
            return $0.needScore > $1.needScore
        }
    }

    nonisolated static func enrichedEvents(
        from baseEvents: [TrainingProfileEvent],
        analysis: AdaptiveAnalysisSnapshot,
        latestAdaptiveDate: Date?
    ) -> [TrainingProfileEvent] {
        var events = baseEvents

        if analysis.readiness >= 0.99, let latestAdaptiveDate {
            events.append(
                TrainingProfileEvent(
                    date: latestAdaptiveDate,
                    kind: .unlockedKey,
                    title: "Alphabet Ready",
                    detail: "Current active set is at threshold"
                )
            )
        }

        return events.sorted(by: { $0.date > $1.date })
    }

    nonisolated static func recentEvents(from events: [TrainingProfileEvent]) -> [TrainingProfileEvent] {
        Array(events.sorted(by: { $0.date > $1.date }).prefix(8))
    }
}

nonisolated private func sessionsOrderedByDateIfNeeded(_ sessions: [TrainingProfileSession]) -> [TrainingProfileSession] {
    guard sessions.count > 1 else { return sessions }
    for index in 1..<sessions.count where sessions[index - 1].date > sessions[index].date {
        return sessions.sorted(by: { $0.date < $1.date })
    }
    return sessions
}
