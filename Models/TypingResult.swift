import SwiftData
import Foundation

struct TypingResultModeDescriptor: Equatable, Sendable {
    var sessionMode: SessionMode
    var testLengthMode: TestLengthMode?
    var testContentMode: TestContentMode?
    var label: String
    var contributesToAdaptiveProfile: Bool

    nonisolated static func parse(mode: String, adaptivePayloadJSON: String?) -> TypingResultModeDescriptor {
        let hasAdaptivePayload = !(adaptivePayloadJSON?.isEmpty ?? true)

        if mode == SessionMode.learning.rawValue {
            return TypingResultModeDescriptor(
                sessionMode: .learning,
                testLengthMode: nil,
                testContentMode: nil,
                label: "Learning",
                contributesToAdaptiveProfile: hasAdaptivePayload
            )
        }

        let parts = mode.split(separator: ":").map(String.init)
        if parts.first == SessionMode.test.rawValue {
            let lengthMode = parts.count > 1 ? TestLengthMode(rawValue: parts[1]) : nil
            let contentMode = parts.count > 2 ? TestContentMode(rawValue: parts[2]) : nil
            let lengthLabel = lengthMode.map { Self.lengthLabel(for: $0) } ?? "Test"
            let contentLabel = contentMode.map { Self.contentLabel(for: $0) } ?? "Custom"
            return TypingResultModeDescriptor(
                sessionMode: .test,
                testLengthMode: lengthMode,
                testContentMode: contentMode,
                label: "Test · \(lengthLabel) · \(contentLabel)",
                contributesToAdaptiveProfile: false
            )
        }

        if let legacyMode = LegacyPracticeMode(rawValue: mode) {
            switch legacyMode {
            case .custom:
                return TypingResultModeDescriptor(
                    sessionMode: .test,
                    testLengthMode: .words,
                    testContentMode: .customWords,
                    label: "Test · Words · Custom",
                    contributesToAdaptiveProfile: false
                )
            case .quote:
                return TypingResultModeDescriptor(
                    sessionMode: .test,
                    testLengthMode: .words,
                    testContentMode: .commonWords,
                    label: "Test · Words · Common",
                    contributesToAdaptiveProfile: false
                )
            case .time:
                return TypingResultModeDescriptor(
                    sessionMode: hasAdaptivePayload ? .learning : .test,
                    testLengthMode: .time,
                    testContentMode: .commonWords,
                    label: hasAdaptivePayload ? "Learning" : "Test · Time · Common",
                    contributesToAdaptiveProfile: hasAdaptivePayload
                )
            case .words:
                return TypingResultModeDescriptor(
                    sessionMode: hasAdaptivePayload ? .learning : .test,
                    testLengthMode: .words,
                    testContentMode: .commonWords,
                    label: hasAdaptivePayload ? "Learning" : "Test · Words · Common",
                    contributesToAdaptiveProfile: hasAdaptivePayload
                )
            case .unlimited:
                return TypingResultModeDescriptor(
                    sessionMode: hasAdaptivePayload ? .learning : .test,
                    testLengthMode: .continuous,
                    testContentMode: .commonWords,
                    label: hasAdaptivePayload ? "Learning" : "Test · Continuous · Common",
                    contributesToAdaptiveProfile: hasAdaptivePayload
                )
            }
        }

        return TypingResultModeDescriptor(
            sessionMode: hasAdaptivePayload ? .learning : .test,
            testLengthMode: nil,
            testContentMode: nil,
            label: hasAdaptivePayload ? "Learning" : "Test",
            contributesToAdaptiveProfile: hasAdaptivePayload
        )
    }

    nonisolated private static func lengthLabel(for mode: TestLengthMode) -> String {
        switch mode {
        case .time:
            return "Time"
        case .words:
            return "Words"
        case .continuous:
            return "Continuous"
        }
    }

    nonisolated private static func contentLabel(for mode: TestContentMode) -> String {
        switch mode {
        case .commonWords:
            return "Common"
        case .codeWords:
            return "Code"
        case .numbers:
            return "Numbers"
        case .customWords:
            return "Custom"
        }
    }
}

@Model
final class TypingResult {
    var date: Date
    var mode: String
    var duration: TimeInterval
    var words: Int
    var wpm: Double
    var accuracy: Double
    var rawInput: String
    var errors: Int
    var adaptivePayloadJSON: String?
    var deduplicationID: String?
    
    nonisolated init(
        date: Date = .now,
        mode: String,
        duration: TimeInterval,
        words: Int,
        wpm: Double,
        accuracy: Double,
        rawInput: String,
        errors: Int,
        adaptivePayloadJSON: String? = nil,
        deduplicationID: String? = nil
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
        self.deduplicationID = deduplicationID
    }
}

extension TypingResult {
    var modeDescriptor: TypingResultModeDescriptor {
        TypingResultModeDescriptor.parse(mode: mode, adaptivePayloadJSON: adaptivePayloadJSON)
    }

    var adaptivePayload: AdaptiveSessionPayload? {
        AdaptiveTypingEngine.decodedPayload(from: adaptivePayloadJSON)
    }
}
