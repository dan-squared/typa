import Foundation

struct PersistedAppSettings: Codable, Sendable {
    var practiceModeRaw: String? = nil
    var sessionModeRaw: String? = SessionMode.learning.rawValue
    var testLengthModeRaw: String? = TestLengthMode.time.rawValue
    var testContentModeRaw: String? = TestContentMode.commonWords.rawValue
    var timeLimit: Int = 30
    var useTimeCap: Bool = false
    var wordLimit: Int = 25
    var dailyGoalMinutes: Int = 30
    var adaptiveTargetWPM: Double = 70
    var adaptiveAlphabetScale: Double = 0.0
    var adaptiveRecoverKeys: Bool = true
    var adaptiveNaturalWords: Bool = true
    var adaptiveUnlockStrategyRaw: String = AdaptiveUnlockStrategy.frequencyFirst.rawValue
    var keyboardLayoutRaw: String = KeyboardLayoutOption.qwerty.rawValue
    var lessonLength: Double = 0.0
    var repeatWords: Int = 1
    var includeCapitals: Bool = false
    var includePunctuation: Bool = false
    var capitalsProbability: Double = 0.0
    var punctuationProbability: Double = 0.0
    var includeNumbers: Bool = false // Legacy decode-only
    var numbersUseBenford: Bool = true
    var customTextLettersOnly: Bool = true
    var customTextLowercase: Bool = true
    var errorModeRaw: String = ErrorMode.off.rawValue
    var minAccuracy: Double = 0.0
    var autoRestart: Bool = false
    var caretStyleRaw: String = CaretStyle.bar.rawValue
    var caretColorRaw: String = CaretColorPreset.custom.rawValue
    var caretColorRed: Double = 234.0 / 255.0
    var caretColorGreen: Double = 51.0 / 255.0
    var caretColorBlue: Double = 35.0 / 255.0
    var smoothCaret: Bool = true
    var blinkRate: Double = 0.5
    var paceCaret: Bool = false // Legacy decode-only
    var soundVolume: Double = 0.5
    var keySoundPackRaw: String = SoundPack.off.rawValue
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
    var customWordLimitEnabled: Bool = false // Legacy decode-only
    var themeRaw: String = AppTheme.system.rawValue
    var languageRaw: String = Language.english.rawValue
    var customSnippetLibraries: [PersistedCustomSnippetLibrary] = [
        PersistedCustomSnippetLibrary(
            id: UUID(),
            name: "Custom Text",
            wordsRaw: ""
        )
    ]
    var selectedSnippetLibraryID: UUID?
}

extension PersistedAppSettings {
    @MainActor
    init(_ settings: AppSettings) {
        self.practiceModeRaw = nil
        self.sessionModeRaw = settings.sessionMode.rawValue
        self.testLengthModeRaw = settings.testLengthMode.rawValue
        self.testContentModeRaw = settings.testContentMode.rawValue
        self.timeLimit = settings.timeLimit
        self.useTimeCap = settings.useTimeCap
        self.wordLimit = settings.wordLimit
        self.dailyGoalMinutes = settings.dailyGoalMinutes
        self.adaptiveTargetWPM = settings.adaptiveTargetWPM
        self.adaptiveAlphabetScale = settings.adaptiveAlphabetScale
        self.adaptiveRecoverKeys = settings.adaptiveRecoverKeys
        self.adaptiveNaturalWords = settings.adaptiveNaturalWords
        self.adaptiveUnlockStrategyRaw = settings.adaptiveUnlockStrategy.rawValue
        self.keyboardLayoutRaw = settings.keyboardLayout.rawValue
        self.lessonLength = settings.lessonLength
        self.repeatWords = settings.repeatWords
        self.includeCapitals = settings.capitalsProbability > 0
        self.includePunctuation = settings.punctuationProbability > 0
        self.capitalsProbability = settings.capitalsProbability
        self.punctuationProbability = settings.punctuationProbability
        self.numbersUseBenford = settings.numbersUseBenford
        self.customTextLettersOnly = settings.customTextLettersOnly
        self.customTextLowercase = settings.customTextLowercase
        self.errorModeRaw = settings.errorMode.rawValue
        self.minAccuracy = settings.minAccuracy
        self.autoRestart = settings.autoRestart
        self.caretStyleRaw = settings.caretStyle.rawValue
        self.caretColorRaw = settings.caretColor.rawValue
        self.caretColorRed = settings.caretColorRed
        self.caretColorGreen = settings.caretColorGreen
        self.caretColorBlue = settings.caretColorBlue
        self.smoothCaret = settings.smoothCaret
        self.blinkRate = settings.blinkRate
        self.soundVolume = settings.soundVolume
        self.keySoundPackRaw = settings.keySoundPack.rawValue
        self.errorSound = settings.errorSound
        self.fontSize = settings.fontSize
        self.lineHeight = settings.lineHeight
        self.letterSpacing = settings.letterSpacing
        self.upcomingTextOpacity = settings.upcomingTextOpacity
        self.noiseEnabled = settings.noiseEnabled
        self.noiseIntensity = settings.noiseIntensity
        self.showLiveStats = settings.showLiveStats
        self.quickEnd = settings.quickEnd
        self.customAutoShuffle = settings.customAutoShuffle
        self.themeRaw = settings.themeRaw
        self.languageRaw = settings.languageRaw
        self.customSnippetLibraries = settings.customSnippetLibraries.map(PersistedCustomSnippetLibrary.init)
        self.selectedSnippetLibraryID = settings.selectedSnippetLibraryID
    }

    @MainActor
    var appSettings: AppSettings {
        let keyboardLayout = KeyboardLayoutOption(rawValue: keyboardLayoutRaw) ?? .qwerty
        var settings = AppSettings(
            sessionMode: SessionMode(rawValue: sessionModeRaw ?? "") ?? .learning,
            testLengthMode: TestLengthMode(rawValue: testLengthModeRaw ?? "") ?? .time,
            testContentMode: TestContentMode(rawValue: testContentModeRaw ?? "") ?? .commonWords,
            timeLimit: timeLimit,
            useTimeCap: useTimeCap,
            wordLimit: wordLimit,
            dailyGoalMinutes: dailyGoalMinutes,
            adaptiveTargetWPM: adaptiveTargetWPM,
            adaptiveAlphabetScale: adaptiveAlphabetScale,
            adaptiveRecoverKeys: adaptiveRecoverKeys,
            adaptiveNaturalWords: adaptiveNaturalWords,
            adaptiveUnlockStrategy: AdaptiveUnlockStrategy(rawValue: adaptiveUnlockStrategyRaw) ?? .frequencyFirst,
            keyboardLayout: keyboardLayout,
            lessonLength: lessonLength,
            repeatWords: repeatWords,
            capitalsProbability: capitalsProbability > 0 ? capitalsProbability : (includeCapitals ? 0.2 : 0.0),
            punctuationProbability: punctuationProbability > 0 ? punctuationProbability : (includePunctuation ? 0.2 : 0.0),
            numbersUseBenford: numbersUseBenford,
            customTextLettersOnly: customTextLettersOnly,
            customTextLowercase: customTextLowercase,
            errorMode: ErrorMode(rawValue: errorModeRaw) ?? .off,
            minAccuracy: minAccuracy,
            autoRestart: autoRestart,
            caretStyle: CaretStyle(rawValue: caretStyleRaw) ?? .bar,
            caretColor: CaretColorPreset(rawValue: caretColorRaw) ?? .custom,
            caretColorRed: caretColorRed,
            caretColorGreen: caretColorGreen,
            caretColorBlue: caretColorBlue,
            smoothCaret: smoothCaret,
            blinkRate: blinkRate,
            soundVolume: soundVolume,
            keySoundPack: SoundPack(rawValue: keySoundPackRaw) ?? .off,
            errorSound: errorSound,
            fontSize: fontSize,
            lineHeight: lineHeight,
            letterSpacing: letterSpacing,
            upcomingTextOpacity: upcomingTextOpacity,
            noiseEnabled: noiseEnabled,
            noiseIntensity: noiseIntensity,
            showLiveStats: showLiveStats,
            quickEnd: quickEnd,
            customAutoShuffle: customAutoShuffle,
            themeRaw: themeRaw,
            languageRaw: languageRaw,
            customSnippetLibraries: customSnippetLibraries.map(\.snippetLibrary),
            selectedSnippetLibraryID: selectedSnippetLibraryID
        )
        settings.applyLegacyPracticeMode(LegacyPracticeMode(rawValue: practiceModeRaw ?? ""))
        return settings
    }
}

struct PersistedCustomSnippetLibrary: Codable, Sendable {
    var id: UUID
    var name: String
    var wordsRaw: String
}

extension PersistedCustomSnippetLibrary {
    @MainActor
    init(_ library: CustomSnippetLibrary) {
        self.id = library.id
        self.name = library.name
        self.wordsRaw = library.wordsRaw
    }

    @MainActor
    var snippetLibrary: CustomSnippetLibrary {
        CustomSnippetLibrary(id: id, name: name, wordsRaw: wordsRaw)
    }
}
