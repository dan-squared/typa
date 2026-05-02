import Foundation
import SwiftUI

enum SessionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case learning, test
    var id: String { rawValue }
}

enum TestLengthMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case time, words, continuous
    var id: String { rawValue }
}

enum TestContentMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case commonWords, codeWords, numbers, customWords
    var id: String { rawValue }
}

enum AdaptiveUnlockStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case layoutAware
    case frequencyFirst

    var id: String { rawValue }
}

enum KeyboardLayoutFamily: String, Codable, Sendable {
    case qwerty
    case colemak
    case dvorak
}

enum KeyboardLayoutOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case qwerty
    case qwertyUk
    case colemak
    case dvorak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qwerty:
            return "QWERTY"
        case .qwertyUk:
            return "QWERTY (UK)"
        case .colemak:
            return "Colemak"
        case .dvorak:
            return "Dvorak"
        }
    }

    nonisolated var family: KeyboardLayoutFamily {
        switch self {
        case .qwerty, .qwertyUk:
            return .qwerty
        case .colemak:
            return .colemak
        case .dvorak:
            return .dvorak
        }
    }

    nonisolated var rows: [[String]] {
        switch self {
        case .qwerty:
            return [
                ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
                Array("qwertyuiop").map(String.init) + ["[", "]", "\\"],
                Array("asdfghjkl").map(String.init) + [";", "'"],
                Array("zxcvbnm").map(String.init) + [",", ".", "/"]
            ]
        case .qwertyUk:
            return [
                ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
                Array("qwertyuiop").map(String.init) + ["[", "]"],
                Array("asdfghjkl").map(String.init) + [";", "'", "#"],
                ["\\"] + Array("zxcvbnm").map(String.init) + [",", ".", "/"]
            ]
        case .colemak:
            return [
                ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="],
                Array("qwfpgjluy").map(String.init) + [";", "[", "]", "\\"],
                Array("arstdhneio").map(String.init) + ["'"],
                Array("zxcvbkm").map(String.init) + [",", ".", "/"]
            ]
        case .dvorak:
            return [
                ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "[", "]"],
                ["'", ",", ".", "p", "y", "f", "g", "c", "r", "l", "/", "=", "\\"],
                Array("aoeuidhtns").map(String.init) + ["-"],
                [";", "q", "j", "k", "x", "b", "m", "w", "v", "z"]
            ]
        }
    }
}

enum LegacyPracticeMode: String, Codable, Sendable {
    case time, words, quote, custom, unlimited
}

enum ErrorMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, letter, word
    var id: String { rawValue }
}

enum CaretStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case bar, block, underline
    var id: String { rawValue }
}

enum CaretColorPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case systemBlue, vibrantGreen, softRed, yellow, purple, custom
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .systemBlue: return .blue
        case .vibrantGreen: return .green
        case .softRed: return .red
        case .yellow: return .yellow
        case .purple: return .purple
        case .custom: return .blue // Can be extended to read a custom hex
        }
    }
}

enum SoundPack: String, Codable, CaseIterable, Identifiable, Sendable {
    case off, clicky, cream, alpaca, akira
    var id: String { rawValue }
}

struct CustomSnippetLibrary: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var wordsRaw: String

    var words: [String] {
        wordsRaw
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    // 1. Practice Modes
    var sessionMode: SessionMode = .learning
    var testLengthMode: TestLengthMode = .time
    var testContentMode: TestContentMode = .commonWords
    var timeLimit: Int = 30 // 15, 30, 60, 120
    var useTimeCap: Bool = false
    var wordLimit: Int = 25 // 10, 25, 50, 100
    var dailyGoalMinutes: Int = 15

    // 1a. Adaptive Training
    var adaptiveTargetWPM: Double = 60
    var adaptiveAlphabetScale: Double = 0.05
    var adaptiveRecoverKeys: Bool = true
    var adaptiveNaturalWords: Bool = true
    var adaptiveUnlockStrategy: AdaptiveUnlockStrategy = .frequencyFirst
    var keyboardLayout: KeyboardLayoutOption = .qwerty
    var lessonLength: Double = 0.25
    var repeatWords: Int = 2
    
    // 2. Customization Settings
    var capitalsProbability: Double = 0.0
    var punctuationProbability: Double = 0.0
    var numbersUseBenford: Bool = true
    var customTextLettersOnly: Bool = true
    var customTextLowercase: Bool = true
    
    var errorMode: ErrorMode = .off
    var minAccuracy: Double = 0.0 // 0 means off
    var autoRestart: Bool = false
    
    var caretStyle: CaretStyle = .bar
    var caretColor: CaretColorPreset = .custom
    var caretColorRed: Double = 234.0 / 255.0
    var caretColorGreen: Double = 51.0 / 255.0
    var caretColorBlue: Double = 35.0 / 255.0
    var smoothCaret: Bool = true
    var blinkRate: Double = 0.5 // 0 for solid
    var soundVolume: Double = 0.5
    var keySoundPack: SoundPack = .alpaca
    var errorSound: Bool = true
    
    var fontSize: Double = 30.0
    var lineHeight: Double = 1.5
    var letterSpacing: Double = 0.0
    var upcomingTextOpacity: Double = 0.78
    var noiseEnabled: Bool = true
    var noiseIntensity: Double = 0.35
    
    var showLiveStats: Bool = true
    var quickEnd: Bool = false
    var customAutoShuffle: Bool? = nil
    
    var themeRaw: String = AppTheme.system.rawValue
    var languageRaw: String = Language.english.rawValue
    var customSnippetLibraries: [CustomSnippetLibrary] = [
        CustomSnippetLibrary(
            name: "Custom Text",
            wordsRaw: ""
        )
    ]
    var selectedSnippetLibraryID: UUID?
    
    nonisolated static let `default` = AppSettings()
}

struct SettingAvailability: Equatable, Sendable {
    let isEnabled: Bool
    let reason: String?

    static let enabled = SettingAvailability(isEnabled: true, reason: nil)

    static func disabled(_ reason: String) -> SettingAvailability {
        SettingAvailability(isEnabled: false, reason: reason)
    }

    nonisolated static func == (lhs: SettingAvailability, rhs: SettingAvailability) -> Bool {
        lhs.isEnabled == rhs.isEnabled && lhs.reason == rhs.reason
    }
}

extension AppSettings {
    var isLearningMode: Bool {
        sessionMode == .learning
    }

    var isTestMode: Bool {
        sessionMode == .test
    }

    var isCustomAutoShuffleEnabled: Bool {
        customAutoShuffle ?? false
    }

    nonisolated var keyboardLayoutFamily: KeyboardLayoutFamily {
        keyboardLayout.family
    }

    var caretDisplayColor: Color {
        Color(red: caretColorRed, green: caretColorGreen, blue: caretColorBlue)
    }

    var resultModeIdentifier: String {
        switch sessionMode {
        case .learning:
            return SessionMode.learning.rawValue
        case .test:
            return "\(SessionMode.test.rawValue):\(testLengthMode.rawValue):\(testContentMode.rawValue)"
        }
    }

    var wordCountAvailability: SettingAvailability {
        guard isTestMode else {
            return .disabled("Learning manages lesson length.")
        }

        switch testLengthMode {
        case .words:
            switch testContentMode {
            case .commonWords, .codeWords:
                return .enabled
            case .numbers:
                return .disabled("Numbers use fixed 50-character groups.")
            case .customWords:
                return .disabled("Custom text uses fragment length and repeat settings.")
            }
        case .time:
            return .disabled("Available in test words mode.")
        case .continuous:
            return .disabled("Continuous mode has no word cap.")
        }
    }

    mutating func applyLegacyPracticeMode(_ mode: LegacyPracticeMode?) {
        guard let mode else { return }

        switch mode {
        case .time:
            sessionMode = .learning
            testLengthMode = .time
            testContentMode = .commonWords
        case .words:
            sessionMode = .learning
            testLengthMode = .words
            testContentMode = .commonWords
        case .quote:
            sessionMode = .test
            testLengthMode = .words
            testContentMode = .commonWords
        case .custom:
            sessionMode = .test
            testLengthMode = .words
            testContentMode = .customWords
        case .unlimited:
            sessionMode = .learning
            testLengthMode = .continuous
            testContentMode = .commonWords
        }
    }
}
