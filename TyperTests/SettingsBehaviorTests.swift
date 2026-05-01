import Testing
@testable import Typer

struct SettingsBehaviorTests {
    @Test
    func applyLegacyPracticeModeMapsCustomToCustomWordTestMode() {
        var settings = AppSettings.default

        settings.applyLegacyPracticeMode(.custom)

        #expect(settings.sessionMode == .test)
        #expect(settings.testLengthMode == .words)
        #expect(settings.testContentMode == .customWords)
    }

    @Test
    func wordCountAvailabilityReflectsNumbersModeRestriction() {
        var settings = AppSettings.default
        settings.sessionMode = .test
        settings.testLengthMode = .words
        settings.testContentMode = .numbers

        #expect(settings.wordCountAvailability == .disabled("Numbers use fixed 50-character groups."))
    }

    @Test
    func resultModeIdentifierIncludesTestLengthAndContent() {
        var settings = AppSettings.default
        settings.sessionMode = .test
        settings.testLengthMode = .continuous
        settings.testContentMode = .codeWords

        #expect(settings.resultModeIdentifier == "test:continuous:codeWords")
    }

    @Test
    func applySettingsNormalizesFontSizeToFortyTwoPointMaximum() {
        let appState = AppState()
        var settings = appState.settings
        settings.fontSize = 60

        appState.applySettings(settings)

        #expect(appState.settings.fontSize == 42)
    }
}
