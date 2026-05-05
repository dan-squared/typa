import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
import AVFoundation
#endif

struct SettingsView: View {
    @Bindable var appState: AppState
    @Environment(\.ds) private var ds
    @State private var draftSettings: AppSettings

    init(appState: AppState) {
        self.appState = appState
        _draftSettings = State(initialValue: appState.settings)
    }

    private var hasPendingChanges: Bool {
        draftSettings != appState.settings
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                GeneralSettingsTab(settings: $draftSettings)
                    .environment(appState)
                    .tabItem { Label("Practice", systemImage: "slider.horizontal.below.rectangle") }

                TrainingSettingsTab(settings: $draftSettings)
                    .tabItem { Label("Learning", systemImage: "keyboard") }

                AppearanceSettingsTab(settings: $draftSettings)
                    .tabItem { Label("Appearance", systemImage: "paintbrush") }

                AudioDataSettingsTab(settings: $draftSettings)
                    .environment(appState)
                    .tabItem { Label("Audio & Data", systemImage: "waveform.and.magnifyingglass") }

                SnippetLibrarySettingsTab(settings: $draftSettings)
                    .tabItem { Label("Custom", systemImage: "text.badge.plus") }
            }
            .padding()

            Divider()

            HStack(spacing: Spacing.sm) {
                if hasPendingChanges {
                    Circle()
                        .fill(ds.accent)
                        .frame(width: 7, height: 7)
                        .transition(.scale.combined(with: .opacity))
                }

                Text(hasPendingChanges ? "Unsaved changes" : "Up to date")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Revert") {
                    draftSettings = appState.settings
                }
                .disabled(!hasPendingChanges)

                Button("Apply") {
                    appState.applySettings(draftSettings)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasPendingChanges)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                hasPendingChanges
                    ? AnyShapeStyle(ds.surfaceElevated)
                    : AnyShapeStyle(.clear)
            )
            .animation(Motion.hover, value: hasPendingChanges)
        }
        .frame(minWidth: 760, idealWidth: 760, minHeight: 700, idealHeight: 700)
        .onChange(of: appState.settings, initial: false) { _, newValue in
            guard !hasPendingChanges else { return }
            draftSettings = newValue
        }
    }
}

// MARK: - Tabs

struct GeneralSettingsTab: View {
    @Binding var settings: AppSettings

    private var sessionModeBinding: Binding<SessionMode> {
        Binding(
            get: { settings.sessionMode },
            set: { settings.sessionMode = $0 }
        )
    }

    private var testLengthModeBinding: Binding<TestLengthMode> {
        Binding(
            get: { settings.testLengthMode },
            set: { settings.testLengthMode = $0 }
        )
    }

    private var testContentModeBinding: Binding<TestContentMode> {
        Binding(
            get: { settings.testContentMode },
            set: { settings.testContentMode = $0 }
        )
    }

    private var languageBinding: Binding<Language> {
        Binding(
            get: { Language(rawValue: settings.languageRaw) ?? .english },
            set: { settings.languageRaw = $0.rawValue }
        )
    }

    private var testSourceDescription: String {
        switch settings.testContentMode {
        case .commonWords:
            return "Uses the active language list."
        case .codeWords:
            return "Uses short code-friendly words."
        case .numbers:
            return "Uses short number groups."
        case .customWords:
            return "Uses the selected custom library."
        }
    }

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Session Mode", selection: sessionModeBinding) {
                    Text("Learning").tag(SessionMode.learning)
                    Text("Test").tag(SessionMode.test)
                }
                .pickerStyle(.segmented)

                Text(
                    settings.isLearningMode
                        ? "Learning focuses on the keys that still need work."
                        : "Test mode lets you choose the source and run length."
                )
                .font(Typo.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if settings.isTestMode {
                Section("Test Setup") {
                    Picker("Test Length", selection: testLengthModeBinding) {
                        Text("Time").tag(TestLengthMode.time)
                        Text("Words").tag(TestLengthMode.words)
                        Text("Continuous").tag(TestLengthMode.continuous)
                    }
                    .pickerStyle(.segmented)

                    Picker("Word Source", selection: testContentModeBinding) {
                        Text("Common Words").tag(TestContentMode.commonWords)
                        Text("Code Words").tag(TestContentMode.codeWords)
                        Text("Numbers").tag(TestContentMode.numbers)
                        Text("Custom Words").tag(TestContentMode.customWords)
                    }

                    Text(testSourceDescription)
                        .font(Typo.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if settings.testContentMode == .numbers {
                        Toggle("Use Benford leading digits", isOn: $settings.numbersUseBenford)
                    }

                    if settings.testLengthMode != .time {
                        Toggle("Also stop when time runs out", isOn: $settings.useTimeCap)
                    }

                    if settings.testLengthMode == .time || settings.useTimeCap {
                        Picker("Time Limit", selection: $settings.timeLimit) {
                            ForEach([15, 30, 60, 120], id: \.self) { time in
                                Text("\(time) seconds").tag(time)
                            }
                        }
                    }

                    if settings.testLengthMode == .words, settings.wordCountAvailability.isEnabled {
                        Picker("Word Count", selection: $settings.wordLimit) {
                            ForEach([10, 25, 50, 100, 200], id: \.self) { count in
                                Text("\(count) words").tag(count)
                            }
                        }
                        Toggle("Stop on the last word", isOn: $settings.quickEnd)
                    } else if settings.testLengthMode == .words,
                              let reason = settings.wordCountAvailability.reason {
                        Text(reason)
                            .font(Typo.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section("Language") {
                Picker("Word List", selection: languageBinding) {
                    ForEach(Language.allCases) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
            }

            Section("Goals") {
                Picker("Daily Goal", selection: $settings.dailyGoalMinutes) {
                    Text("Off").tag(0)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("60 min").tag(60)
                    Text("90 min").tag(90)
                    Text("120 min").tag(120)
                }

                GoalDotSelector(selection: $settings.dailyGoalMinutes)

                Text("Tracks minutes practiced today.")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Typing Rules") {
                Picker("Error Mode", selection: $settings.errorMode) {
                    Text("Off").tag(ErrorMode.off)
                    Text("Letter Strict").tag(ErrorMode.letter)
                    Text("Word Strict").tag(ErrorMode.word)
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack {
                        Text("Minimum Accuracy")
                        Spacer()
                        Text(settings.minAccuracy == 0 ? "Off" : "\(Int(settings.minAccuracy.rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.minAccuracy, in: 0...100, step: 5)
                        .settingsSliderHaptics(value: settings.minAccuracy, range: 0...100, step: 5)
                }

                Toggle("Auto Restart", isOn: $settings.autoRestart)
                Text("Low-accuracy runs are not saved. Auto Restart is useful for drills.")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

struct TrainingSettingsTab: View {
    @Binding var settings: AppSettings
    @Environment(\.ds) private var ds
    @State private var advancedExpanded = false

    private var unlockThresholdLabel: String {
        "\(Int(settings.adaptiveTargetWPM.rounded())) WPM"
    }

    private var targetSpeedDescription: String {
        "Sets the pace learning aims for."
    }

    private var alphabetScaleLabel: String {
        let percentage = Int((settings.adaptiveAlphabetScale * 100).rounded())
        return percentage == 0 ? "Starter keys only" : "\(percentage)% more keys"
    }

    private var unlockStrategyDescription: String {
        switch settings.adaptiveUnlockStrategy {
        case .layoutAware:
            return "Unlocks keys by keyboard position."
        case .frequencyFirst:
            return "Unlocks keys by language frequency."
        }
    }

    private var textExtrasEnabled: Bool {
        settings.isLearningMode || (settings.isTestMode && (settings.testContentMode == .commonWords || settings.testContentMode == .codeWords))
    }

    private var textExtrasDescription: String {
        if textExtrasEnabled {
            return "Controls how often capitals and punctuation appear."
        }
        return "Available in learning and common/code word tests."
    }

    var body: some View {
        Form {
            if settings.isLearningMode {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Learning Path")
                            .font(.headline)
                        Text("Controls how learning mode unlocks new keys.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }

                Section("Progress") {
                    Text("Learning layout: QWERTY")
                        .font(Typo.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker("Unlock Order", selection: $settings.adaptiveUnlockStrategy) {
                        Text("Keyboard Order").tag(AdaptiveUnlockStrategy.layoutAware)
                        Text("Frequency First").tag(AdaptiveUnlockStrategy.frequencyFirst)
                    }

                    Text(unlockStrategyDescription)
                        .font(Typo.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        HStack {
                            Text("Target Speed")
                            Spacer()
                            Text(unlockThresholdLabel)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { settings.adaptiveTargetWPM },
                                set: { settings.adaptiveTargetWPM = $0.rounded() }
                            ),
                            in: 20...200
                        )
                            .tint(ds.accent)
                            .settingsSliderHaptics(value: settings.adaptiveTargetWPM, range: 20...200, step: 1)
                        HStack {
                            Text("20")
                            Spacer()
                            Text("Goal")
                            Spacer()
                            Text("200")
                        }
                        .font(Typo.caption)
                        .foregroundStyle(ds.tertiaryText)
                        Text(targetSpeedDescription)
                            .font(Typo.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        HStack {
                            Text("Lesson Length")
                            Spacer()
                            Text("\(100 + Int(round(settings.lessonLength * 100))) chars")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.lessonLength, in: 0...1, step: 0.05)
                            .settingsSliderHaptics(value: settings.lessonLength, range: 0...1, step: 0.05)
                    }
                }

                DisclosureGroup(isExpanded: $advancedExpanded) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Picker("Repeat Each Word", selection: $settings.repeatWords) {
                            ForEach(1..<11, id: \.self) { value in
                                Text("\(value)x").tag(value)
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            HStack {
                                Text("How Fast To Add New Keys")
                                Spacer()
                                Text(alphabetScaleLabel)
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $settings.adaptiveAlphabetScale, in: 0...1, step: 0.05)
                                .settingsSliderHaptics(value: settings.adaptiveAlphabetScale, range: 0...1, step: 0.05)
                        }

                        Toggle("Fix weak keys before adding more", isOn: $settings.adaptiveRecoverKeys)
                        Toggle("Use more real words when possible", isOn: $settings.adaptiveNaturalWords)
                    }
                } label: {
                    Text("Advanced Lesson Controls")
                }
                .disclosureGroupStyle(SettingsDisclosureGroupStyle())
            }

            Section("Text Extras") {
                Text(textExtrasDescription)
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack {
                        Text("Capital Letters")
                        Spacer()
                        Text("\(Int((settings.capitalsProbability * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.capitalsProbability, in: 0...1, step: 0.05)
                        .settingsSliderHaptics(value: settings.capitalsProbability, range: 0...1, step: 0.05)
                }

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack {
                        Text("Punctuation")
                        Spacer()
                        Text("\(Int((settings.punctuationProbability * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.punctuationProbability, in: 0...1, step: 0.05)
                        .settingsSliderHaptics(value: settings.punctuationProbability, range: 0...1, step: 0.05)
                }
            }
            .disabled(!textExtrasEnabled)
        }
        .formStyle(.grouped)
    }
}

struct AppearanceSettingsTab: View {
    @Binding var settings: AppSettings

    private var themeBinding: Binding<AppTheme> {
        Binding(
            get: { AppTheme(rawValue: settings.themeRaw) ?? .system },
            set: { settings.themeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            SettingsTypingPreview(settings: settings)
                .padding(.bottom, Spacing.sm)

            Section("Text") {
                Picker("Theme", selection: themeBinding) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }

                Slider(value: $settings.fontSize, in: 16...42, step: 2) {
                    Text("Font Size (\(Int(settings.fontSize)))")
                }
                .settingsSliderHaptics(value: settings.fontSize, range: 16...42, step: 2)

                Slider(value: $settings.lineHeight, in: 1.0...2.5, step: 0.1) {
                    Text("Line Height (\(settings.lineHeight, specifier: "%.1f"))")
                }
                .settingsSliderHaptics(value: settings.lineHeight, range: 1.0...2.5, step: 0.1)

                Slider(value: $settings.letterSpacing, in: -2...5, step: 0.5) {
                    Text("Letter Spacing")
                }
                .settingsSliderHaptics(value: settings.letterSpacing, range: -2...5, step: 0.5)

                Slider(value: $settings.upcomingTextOpacity, in: 0.35...1, step: 0.05) {
                    Text("Upcoming Text Visibility")
                }
                .settingsSliderHaptics(value: settings.upcomingTextOpacity, range: 0.35...1, step: 0.05)
            }

            Section("Caret") {
                Picker("Caret Style", selection: $settings.caretStyle) {
                    Text("Bar").tag(CaretStyle.bar)
                    Text("Block").tag(CaretStyle.block)
                    Text("Underline").tag(CaretStyle.underline)
                }
                .pickerStyle(.segmented)

                ColorPicker("Caret Color", selection: caretColorBinding, supportsOpacity: false)

                Toggle("Smooth Caret Animation", isOn: $settings.smoothCaret)

                Slider(value: $settings.blinkRate, in: 0...1, step: 0.1) {
                    Text(settings.blinkRate == 0 ? "Solid Caret" : "Blink Rate")
                }
                .settingsSliderHaptics(value: settings.blinkRate, range: 0...1, step: 0.1)
            }

            Section("Window") {
                Toggle("Noise Texture", isOn: $settings.noiseEnabled)

                Slider(value: $settings.noiseIntensity, in: 0...1.5, step: 0.05) {
                    Text("Texture Amount (\(settings.noiseIntensity, specifier: "%.2f"))")
                }
                .settingsSliderHaptics(value: settings.noiseIntensity, range: 0...1.5, step: 0.05)
                .disabled(!settings.noiseEnabled)

                Toggle("Show Live Stats", isOn: $settings.showLiveStats)
            }
        }
        .formStyle(.grouped)
    }
}

struct AudioDataSettingsTab: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Binding var settings: AppSettings
    @State private var statsExpanded = true
    @State private var isPresentingHistoryResetAlert = false
    @State private var isResettingHistory = false
    @State private var historyResetStatusMessage: String?

    private var historySummary: TrainingHistorySummary { appState.trainingHistorySummary }
    private var sessionsCount: Int { historySummary.sessionsCount }
    private var bestWPM: Int { historySummary.bestWPM }
    private var avgAccuracy: Int { historySummary.averageAccuracy }

    var body: some View {
        Form {
            Section("Key Sounds") {
                Picker("Keypress Sound", selection: $settings.keySoundPack) {
                    Text("Off").tag(SoundPack.off)
                    Text("Alpaca").tag(SoundPack.alpaca)
                    Text("Apex Pro (Akira)").tag(SoundPack.akira)
                }
                .onChange(of: settings.keySoundPack, initial: false) { _, pack in
                    playPreviewSound(for: pack)
                }

                Toggle("Play Error Sound", isOn: $settings.errorSound)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text("\(Int((settings.soundVolume * 100).rounded()))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.soundVolume, in: 0...1, step: 0.1)
                        .settingsSliderHaptics(value: settings.soundVolume, range: 0...1, step: 0.1)
                }
            }

            Section("Profile") {
                DisclosureGroup(isExpanded: $statsExpanded) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        statRow("Sessions", "\(sessionsCount)")
                        statRow("Best WPM", "\(bestWPM)")
                        statRow("Avg Accuracy", "\(avgAccuracy)%")

                        Button("Open Profile") {
                            appState.requestProfileWindowOpen()
                            openWindow(id: "history")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } label: {
                    Text("Session Summary")
                }
                .disclosureGroupStyle(SettingsDisclosureGroupStyle())
            }

            Section("Saved Progress") {
                Text("Deletes saved sessions and adaptive progress. Settings stay the same.")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Clear Saved History", role: .destructive) {
                    isPresentingHistoryResetAlert = true
                }
                .disabled(sessionsCount == 0 || isResettingHistory)

                if isResettingHistory {
                    ProgressView("Clearing history…")
                        .controlSize(.small)
                } else if let historyResetStatusMessage {
                    Text(historyResetStatusMessage)
                        .font(Typo.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Clear Saved History?", isPresented: $isPresentingHistoryResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear History", role: .destructive) {
                clearSavedHistory()
            }
        } message: {
            Text("This deletes saved sessions and adaptive progress. Settings stay the same.")
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(Typo.body)
                .monospacedDigit()
        }
    }

    private func clearSavedHistory() {
        isResettingHistory = true
        historyResetStatusMessage = nil
        let container = modelContext.container

        Task {
            do {
                let historyStore = HistoryStoreActor(modelContainer: container)
                let deletedCount = try await historyStore.deleteAllSessions()
                await MainActor.run {
                    appState.clearTrainingHistory()
                    isResettingHistory = false
                    historyResetStatusMessage = deletedCount == 0
                        ? "No saved history was found."
                        : "Cleared \(deletedCount) saved session\(deletedCount == 1 ? "" : "s")."
                }
            } catch {
                await MainActor.run {
                    isResettingHistory = false
                    historyResetStatusMessage = "Clear failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

private extension AppearanceSettingsTab {
    var caretColorBinding: Binding<Color> {
        Binding<Color>(
            get: {
                settings.caretDisplayColor
            },
            set: { newValue in
                #if os(macOS)
                let nsColor = NSColor(newValue).usingColorSpace(.deviceRGB) ?? .systemBlue
                settings.caretColorRed = Double(nsColor.redComponent)
                settings.caretColorGreen = Double(nsColor.greenComponent)
                settings.caretColorBlue = Double(nsColor.blueComponent)
                settings.caretColor = .custom
                #endif
            }
        )
    }
}

struct SnippetLibrarySettingsTab: View {
    @Binding var settings: AppSettings
    @State private var selectedID: UUID?
    @State private var draftName = ""
    @State private var draftWords = ""

    var body: some View {
        HStack(spacing: Spacing.md + Spacing.xxxs) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Custom Snippets")
                    .font(.headline)
                List(selection: $selectedID) {
                    ForEach(settings.customSnippetLibraries) { library in
                        Text(library.name)
                            .tag(library.id)
                    }
                }
                HStack {
                    Button("Add") {
                        let newLibrary = CustomSnippetLibrary(name: "Untitled Library", wordsRaw: "")
                        settings.customSnippetLibraries.append(newLibrary)
                        selectedID = newLibrary.id
                        settings.selectedSnippetLibraryID = newLibrary.id
                        loadSelected()
                    }
                    Button("Remove") {
                        guard let selectedID else { return }
                        settings.customSnippetLibraries.removeAll(where: { $0.id == selectedID })
                        if settings.customSnippetLibraries.isEmpty {
                            let fallbackLibrary = AppSettings.default.customSnippetLibraries[0]
                            settings.customSnippetLibraries = [fallbackLibrary]
                        }
                        self.selectedID = settings.customSnippetLibraries.first?.id
                        settings.selectedSnippetLibraryID = self.selectedID
                        loadSelected()
                    }
                    .disabled(selectedID == nil)
                }
            }
            .frame(width: 180)

            Form {
                if let selectedLibrary = settings.customSnippetLibraries.first(where: { $0.id == selectedID }) {
                    HStack {
                        Label("\(selectedLibrary.words.count) words", systemImage: "textformat.abc")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if selectedLibrary.words.isEmpty {
                            Label("Empty library", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }

                TextField("Library Name", text: $draftName)
                    .onChange(of: draftName, initial: false) { _, _ in
                        saveDraft()
                    }

                TextEditor(text: $draftWords)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 220)
                    .onChange(of: draftWords, initial: false) { _, _ in
                        saveDraft()
                    }

                Toggle("Randomize Words", isOn: customAutoShuffleBinding)
                Toggle("Letters Only", isOn: $settings.customTextLettersOnly)
                Toggle("Lowercase Text", isOn: $settings.customTextLowercase)
                Text("Sequential by default. Randomized when enabled.")
                    .font(Typo.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Section("Playback") {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        HStack {
                            Text("Fragment Length")
                            Spacer()
                            Text("\(100 + Int(round(settings.lessonLength * 100))) chars")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.lessonLength, in: 0...1, step: 0.05)
                    }

                    Picker("Repeat Each Word", selection: $settings.repeatWords) {
                        ForEach(1..<11, id: \.self) { value in
                            Text("\(value)x").tag(value)
                        }
                    }

                    Text("Used in custom-word tests.")
                        .font(Typo.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Use This Library For Test Mode") {
                    settings.selectedSnippetLibraryID = selectedID
                    settings.sessionMode = .test
                    settings.testContentMode = .customWords
                }
                .disabled(selectedID == nil)
            }
            .formStyle(.grouped)
        }
        .onAppear {
            if selectedID == nil {
                selectedID = settings.selectedSnippetLibraryID ?? settings.customSnippetLibraries.first?.id
            }
            if settings.selectedSnippetLibraryID == nil {
                settings.selectedSnippetLibraryID = selectedID
            }
            loadSelected()
        }
        .onChange(of: selectedID, initial: false) { _, newValue in
            settings.selectedSnippetLibraryID = newValue
            loadSelected()
        }
    }

    private func loadSelected() {
        guard let selectedID,
              let library = settings.customSnippetLibraries.first(where: { $0.id == selectedID }) else {
            draftName = ""
            draftWords = ""
            return
        }
        draftName = library.name
        draftWords = library.wordsRaw
    }

    private func saveDraft() {
        guard let selectedID,
              let index = settings.customSnippetLibraries.firstIndex(where: { $0.id == selectedID }) else { return }
        settings.customSnippetLibraries[index].name = draftName
        settings.customSnippetLibraries[index].wordsRaw = draftWords
    }

    private var customAutoShuffleBinding: Binding<Bool> {
        Binding(
            get: { settings.customAutoShuffle ?? false },
            set: { settings.customAutoShuffle = $0 }
        )
    }
}

// MARK: - Live Preview

struct SettingsTypingPreview: View {
    let settings: AppSettings
    @Environment(\.ds) private var ds
    @State private var measuredContentSize: CGSize = CGSize(width: 1, height: 1)

    var body: some View {
        VStack(spacing: Spacing.md) {
            Text("Live Preview")
                .font(Typo.label)
                .foregroundStyle(ds.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geometry in
                let cardPadding = Spacing.lg
                let contentScale = previewScale(in: geometry.size, padding: cardPadding)

                ZStack(alignment: .topLeading) {
                    previewContent
                        .fixedSize()
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: SettingsPreviewContentSizeKey.self,
                                    value: proxy.size
                                )
                            }
                        )
                        .scaleEffect(contentScale, anchor: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(cardPadding)
                .background(DSCardBackground())
            }
            .frame(height: 170)
        }
        .onPreferenceChange(SettingsPreviewContentSizeKey.self) { measuredContentSize = $0 }
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: previewLineSpacing) {
            HStack(spacing: 0) {
                Text("the quick ")
                    .foregroundStyle(ds.primaryText)

                ZStack(alignment: .leading) {
                    Text("b")
                        .foregroundStyle(ds.secondaryText)

                    LiquidCaret(
                        style: settings.caretStyle,
                        color: settings.caretDisplayColor,
                        fontSize: settings.fontSize,
                        isBlinking: settings.blinkRate > 0,
                        isIdle: false,
                        allowsContinuousAnimation: false
                    )
                    .offset(x: caretOffsetX, y: caretOffsetY)
                }

                Text("rown fox")
                    .foregroundStyle(ds.secondaryText)
                    .opacity(settings.upcomingTextOpacity)
            }

            Text("jumps over the lazy dog")
                .foregroundStyle(ds.secondaryText)
                .opacity(settings.upcomingTextOpacity)
        }
        .font(.system(size: settings.fontSize, design: .monospaced))
        .kerning(settings.letterSpacing)
    }

    private var previewLineSpacing: CGFloat {
        max(0, (settings.lineHeight - 1) * settings.fontSize * 0.55)
    }

    private func previewScale(in availableSize: CGSize, padding: CGFloat) -> CGFloat {
        guard measuredContentSize.width > 0, measuredContentSize.height > 0 else { return 1 }
        let widthScale = max(0.45, (availableSize.width - (padding * 2)) / measuredContentSize.width)
        let heightScale = max(0.45, (availableSize.height - (padding * 2)) / measuredContentSize.height)
        return min(1, widthScale, heightScale)
    }

    private var caretOffsetX: CGFloat {
        switch settings.caretStyle {
        case .bar:
            return -max(1.2, settings.fontSize * 0.05)
        case .block, .underline:
            return max(1, settings.fontSize * 0.03)
        }
    }

    private var caretOffsetY: CGFloat {
        switch settings.caretStyle {
        case .bar, .block:
            return max(1, settings.fontSize * 0.06)
        case .underline:
            return max(1, settings.fontSize * 0.05)
        }
    }
}

private struct SettingsPreviewContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        guard next != .zero else { return }
        value = next
    }
}

private struct GoalDotSelector: View {
    @Binding var selection: Int
    private let goals = [0, 15, 30, 45, 60, 90, 120]

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(goals, id: \.self) { goal in
                Button {
                    selection = goal
                } label: {
                    VStack(spacing: Spacing.xxs) {
                        Circle()
                            .fill(goal == selection ? Color.accentColor : Color.secondary.opacity(0.22))
                            .frame(width: goal == selection ? 9 : 7, height: goal == selection ? 9 : 7)
                        Text(goal == 0 ? "Off" : "\(goal)")
                            .font(Typo.caption)
                            .foregroundStyle(goal == selection ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.xxs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(goal == 0 ? "Turn daily goal off" : "Set daily goal to \(goal) minutes")
            }
        }
        .padding(.top, Spacing.xxs)
    }
}

private struct SettingsSliderHapticsModifier: ViewModifier {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double

    @State private var lastQuantizedValue: Int?

    func body(content: Content) -> some View {
        content
            .onAppear {
                lastQuantizedValue = quantizedValue(for: value)
            }
            .onChange(of: value, initial: false) { _, newValue in
                let quantized = quantizedValue(for: newValue)
                guard quantized != lastQuantizedValue else { return }
                lastQuantizedValue = quantized
                performHapticFeedback()
            }
    }

    private func quantizedValue(for value: Double) -> Int {
        let normalized = max(range.lowerBound, min(range.upperBound, value)) - range.lowerBound
        return Int((normalized / step).rounded())
    }

    private func performHapticFeedback() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        #endif
    }
}

private extension View {
    func settingsSliderHaptics(value: Double, range: ClosedRange<Double>, step: Double) -> some View {
        modifier(SettingsSliderHapticsModifier(value: value, range: range, step: step))
    }
}

private struct SettingsDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                withAnimation(Motion.hover) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.sm) {
                    configuration.label
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
                    .padding(.top, Spacing.sm)
            }
        }
    }
}

private func playPreviewSound(for pack: SoundPack) {
    #if os(macOS)
    guard pack != .off else { return }

    let previewCandidates: [(String, String)]
    switch pack {
    case .off:
        return
    case .alpaca:
        previewCandidates = [("alpaca/press_key1", "mp3")]
    case .akira:
        previewCandidates = [("Apex Pro TKL V2 Akira/akira_key1", "wav")]
    }

    for (name, fileExtension) in previewCandidates {
        if let url = previewSoundURL(named: name, fileExtension: fileExtension) {
            SettingsPreviewSoundPlayer.shared.play(url: url)
            break
        }
    }
    #endif
}

#if os(macOS)
private func previewSoundURL(named name: String, fileExtension: String) -> URL? {
    let resourceName = (name as NSString).lastPathComponent
    let resourceDirectory = (name as NSString).deletingLastPathComponent
    let subdirectory = resourceDirectory.isEmpty ? nil : resourceDirectory
    if let nestedURL = Bundle.main.url(forResource: resourceName, withExtension: fileExtension, subdirectory: subdirectory) {
        return nestedURL
    }
    return Bundle.main.url(forResource: resourceName, withExtension: fileExtension)
}
#endif

#if os(macOS)
@MainActor
private final class SettingsPreviewSoundPlayer {
    static let shared = SettingsPreviewSoundPlayer()

    private var player: AVAudioPlayer?

    func play(url: URL) {
        player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        player?.play()
    }
}
#endif
