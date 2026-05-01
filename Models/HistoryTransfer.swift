import Foundation

struct HistoryTransferDeduplicationKey: Hashable, Sendable {
    var timestampMS: Int64
    var mode: String
    var durationMS: Int
    var words: Int
    var wpmHundredths: Int
    var accuracyHundredths: Int
    var rawInput: String
    var errors: Int
    var adaptivePayloadJSON: String?
}

extension HistoryTransferDeduplicationKey {
    nonisolated var stableID: String {
        [
            String(timestampMS),
            mode,
            String(durationMS),
            String(words),
            String(wpmHundredths),
            String(accuracyHundredths),
            rawInput,
            String(errors),
            adaptivePayloadJSON ?? ""
        ].joined(separator: "|")
    }
}

struct HistoryTransferPackage: Codable, Sendable {
    var formatVersion: Int = 2
    var exportedAt: Date
    var sessions: [HistoryTransferSession]
}

struct HistoryTransferSession: Codable, Equatable, Sendable {
    var date: Date
    var mode: String
    var duration: TimeInterval
    var words: Int
    var wpm: Double
    var accuracy: Double
    var rawInput: String
    var errors: Int
    var adaptivePayloadJSON: String?

    nonisolated init(
        date: Date,
        mode: String,
        duration: TimeInterval,
        words: Int,
        wpm: Double,
        accuracy: Double,
        rawInput: String,
        errors: Int,
        adaptivePayloadJSON: String? = nil
    ) {
        self.date = date
        self.mode = mode
        self.duration = duration
        self.words = words
        self.wpm = wpm
        self.accuracy = accuracy
        self.rawInput = rawInput
        self.errors = errors
        self.adaptivePayloadJSON = adaptivePayloadJSON
    }

    nonisolated static func == (lhs: HistoryTransferSession, rhs: HistoryTransferSession) -> Bool {
        lhs.date == rhs.date &&
        lhs.mode == rhs.mode &&
        lhs.duration == rhs.duration &&
        lhs.words == rhs.words &&
        lhs.wpm == rhs.wpm &&
        lhs.accuracy == rhs.accuracy &&
        lhs.rawInput == rhs.rawInput &&
        lhs.errors == rhs.errors &&
        lhs.adaptivePayloadJSON == rhs.adaptivePayloadJSON
    }
}

extension HistoryTransferSession {
    nonisolated var deduplicationKey: HistoryTransferDeduplicationKey {
        HistoryTransferDeduplicationKey(
            timestampMS: Int64((date.timeIntervalSince1970 * 1_000).rounded()),
            mode: mode,
            durationMS: Int((duration * 1_000).rounded()),
            words: words,
            wpmHundredths: Int((wpm * 100).rounded()),
            accuracyHundredths: Int((accuracy * 100).rounded()),
            rawInput: rawInput,
            errors: errors,
            adaptivePayloadJSON: adaptivePayloadJSON
        )
    }

    nonisolated init(result: TypingResult) {
        self.init(
            date: result.date,
            mode: result.mode,
            duration: result.duration,
            words: result.words,
            wpm: result.wpm,
            accuracy: result.accuracy,
            rawInput: result.rawInput,
            errors: result.errors,
            adaptivePayloadJSON: result.adaptivePayloadJSON
        )
    }
}

extension TypingResult {
    var deduplicationKey: HistoryTransferDeduplicationKey {
        HistoryTransferSession(result: self).deduplicationKey
    }
}
