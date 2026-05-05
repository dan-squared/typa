import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct AdaptiveAnalysisView: View {
    @Bindable var appState: AppState
    @Environment(\.ds) private var ds
    @Environment(\.modelContext) private var modelContext

    @State private var selectedRange: AdaptiveAnalyticsRange
    @State private var selectedProgressRange: AdaptiveAnalyticsRange
    @State private var hoveredChartDate: Date?
    @State private var hoveredChartLocation: CGPoint?
    @State private var showImportPicker = false
    @State private var statusMessage: String?
    @State private var isImporting = false
    @State private var deletingSessionID: String?
    @State private var trainingProfile: AdaptiveTrainingProfileSnapshot
    @State private var selectedKey: String?
    @State private var progressSmoothness = 0.35
    @State private var isHistoryExpanded = false

    // Cached derived data to avoid redundant recomputation on every body evaluation.
    @State private var cachedFilteredSessions: [TrainingProfileSession] = []
    @State private var cachedActivityCells: [AdaptiveActivityCell] = []
    @State private var cachedActivityWeeks: [[AdaptiveActivityCell]] = []
    @State private var cachedMaxActivityCount: Int = 1
    @State private var cachedSmoothedPoints: [AdaptiveSmoothedMetricPoint] = []
    @State private var cachedChartSessions: [TrainingProfileSession] = []
    @State private var cachedKeyboardKeys: [AdaptiveKeyProfile] = []
    @State private var cachedHistoryEntries: [AdaptiveSessionHistoryEntry] = []
    @State private var cachedAnalysisTaskInput: AdaptiveAnalysisTaskInput?

    init(appState: AppState) {
        self.appState = appState
        _selectedRange = State(initialValue: .all)
        _selectedProgressRange = State(initialValue: .all)
        _trainingProfile = State(initialValue: appState.profileSnapshot)
    }

    private let profileCalendar = Calendar.current
    private let trafficRed = Color(red: 1.0, green: 0.37, blue: 0.38)
    private let trafficYellow = Color.accentColor
    private let trafficGreen = Color(red: 0.17, green: 0.82, blue: 0.31)

    private var isDeletingSession: Bool {
        deletingSessionID != nil
    }

    private var allSessions: [TrainingProfileSession] {
        appState.trainingRuntime.sessions
    }

    private var filteredSessions: [TrainingProfileSession] {
        cachedFilteredSessions
    }

    private var allLearningSessions: [TrainingProfileSession] {
        allSessions.filter { $0.modeDescriptor.sessionMode == .learning }
    }

    private var learningResults: [TrainingProfileSession] {
        cachedFilteredSessions.filter { $0.modeDescriptor.sessionMode == .learning }
    }

    private var adaptiveResults: [TrainingProfileSession] {
        cachedFilteredSessions.filter(\.contributesToAdaptiveProfile)
    }

    private var testResults: [TrainingProfileSession] {
        cachedFilteredSessions.filter { $0.modeDescriptor.sessionMode == .test }
    }

    private var hoveredResult: TrainingProfileSession? {
        guard let hoveredChartDate else { return nil }
        return cachedChartSessions.min {
            abs($0.date.timeIntervalSince(hoveredChartDate)) < abs($1.date.timeIntervalSince(hoveredChartDate))
        }
    }

    private var analysis: AdaptiveAnalysisSnapshot {
        trainingProfile.analysis
    }

    private var runtimeRecentEvents: [TrainingProfileEvent] {
        appState.trainingRuntime.recentEvents
    }

    private var runtimeLastLessonFeedback: AdaptiveLastLessonFeedback? {
        appState.trainingRuntime.lastLessonFeedback
    }

    private var averageWPM: Double {
        guard !cachedFilteredSessions.isEmpty else { return 0 }
        return cachedFilteredSessions.map(\.wpm).reduce(0, +) / Double(cachedFilteredSessions.count)
    }

    private var averageAccuracy: Double {
        guard !cachedFilteredSessions.isEmpty else { return 0 }
        return cachedFilteredSessions.map(\.accuracy).reduce(0, +) / Double(cachedFilteredSessions.count)
    }

    private var bestWPM: Double {
        cachedFilteredSessions.map(\.wpm).max() ?? 0
    }

    private var chartMaxY: Double {
        let highestWPM = max(cachedChartSessions.map(\.wpm).max() ?? 0, cachedSmoothedPoints.map(\.wpm).max() ?? 0)
        return max(120, ceil(max(highestWPM, 120) / 20) * 20)
    }

    private var smoothedProgressPoints: [AdaptiveSmoothedMetricPoint] {
        cachedSmoothedPoints
    }

    private var summarySnapshots: [AdaptiveSummarySnapshot] {
        [
            AdaptiveSummarySnapshot(
                title: "Selected Range",
                subtitle: "\(selectedRange.title) overview",
                metrics: [
                    AdaptiveSummaryMetric(label: "Lessons", value: "\(filteredSessions.count)", tone: .primary),
                    AdaptiveSummaryMetric(label: "Avg WPM", value: intString(averageWPM), tone: .accent),
                    AdaptiveSummaryMetric(label: "Best", value: intString(bestWPM), tone: .primary),
                    AdaptiveSummaryMetric(label: "Accuracy", value: percentString(averageAccuracy / 100), tone: .success)
                ]
            ),
            AdaptiveSummarySnapshot(
                title: "Training State",
                subtitle: adaptiveResults.isEmpty ? "Learning mode not active yet" : "Shared adaptive runtime",
                metrics: [
                    AdaptiveSummaryMetric(label: "Active Keys", value: adaptiveResults.isEmpty ? "—" : "\(analysis.activeAlphabetSize)", tone: .primary),
                    AdaptiveSummaryMetric(label: "Focus", value: adaptiveResults.isEmpty ? "—" : (analysis.currentLesson.focusedKey?.uppercased() ?? "Mixed"), tone: .accent),
                    AdaptiveSummaryMetric(
                        label: "Daily Goal",
                        value: trainingProfile.dailyGoal.targetMinutes > 0 ? "\(trainingProfile.dailyGoal.targetMinutes)m" : "Off",
                        tone: .success
                    ),
                    AdaptiveSummaryMetric(
                        label: "Target",
                        value: adaptiveResults.isEmpty ? "—" : "\(Int(analysis.currentLesson.targetWPM)) WPM",
                        tone: .primary
                    )
                ]
            )
        ]
    }

    private var activityCells: [AdaptiveActivityCell] {
        cachedActivityCells
    }

    private var activityWeeks: [[AdaptiveActivityCell]] {
        cachedActivityWeeks
    }

    private var maxActivityCount: Int {
        cachedMaxActivityCount
    }

    private var dailyGoalCardTitle: String {
        trainingProfile.dailyGoal.targetMinutes > 0 ? "Daily Goal" : "Daily Goal Off"
    }

    private var keyboardOrderedAnalysisKeys: [AdaptiveKeyProfile] {
        cachedKeyboardKeys
    }

    private var sessionHistoryEntries: [AdaptiveSessionHistoryEntry] {
        cachedHistoryEntries
    }

    var body: some View {
        GeometryReader { geo in
            let dashboardWidth = analysisDashboardWidth(for: geo.size.width)
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    header(for: dashboardWidth)

                    if filteredSessions.isEmpty {
                        ContentUnavailableView(
                            "No Sessions in This Range",
                            systemImage: "chart.bar.xaxis.ascending.badge.clock",
                            description: Text("Complete a practice session to unlock adaptive analysis.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 380)
                    } else if adaptiveResults.isEmpty {
                        profileSection(
                            title: "Overview",
                            subtitle: "Performance summary for the selected window.",
                            tint: trafficYellow
                        ) {
                            overviewSummarySection(for: dashboardWidth)
                        }
                        profileSection(
                            title: "Practice Rhythm",
                            subtitle: "Activity patterns, goals, and milestones.",
                            tint: trafficGreen
                        ) {
                            LazyVGrid(columns: detailColumns(for: dashboardWidth), spacing: Spacing.md) {
                                practiceCalendarCard
                                dailyGoalCard
                                recentEventsCard
                            }
                        }
                        ContentUnavailableView(
                            "No Learning Sessions Yet",
                            systemImage: "graduationcap.circle",
                            description: Text("Adaptive charts only build from Learning mode sessions. Test sessions are still saved in history below.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
                        historySection(minHeight: max(260, geo.size.height * 0.28), tint: trafficRed)
                    } else {
                        profileSection(
                            title: "Overview",
                            subtitle: "Performance summary for the selected window.",
                            tint: trafficYellow
                        ) {
                            overviewSummarySection(for: dashboardWidth)
                        }
                        profileSection(
                            title: "Practice Rhythm",
                            subtitle: "Calendar activity, goals, and milestones.",
                            tint: trafficGreen
                        ) {
                            LazyVGrid(columns: detailColumns(for: dashboardWidth), spacing: Spacing.md) {
                                practiceCalendarCard
                                dailyGoalCard
                                recentEventsCard
                            }
                        }
                        profileSection(
                            title: "Adaptive Engine",
                            subtitle: "Lesson plan, feedback, and performance progression.",
                            tint: trafficRed
                        ) {
                            LazyVGrid(columns: detailColumns(for: dashboardWidth), spacing: Spacing.md) {
                                currentTrainingPlanCard
                                lastLessonCard
                            }
                            progressChart
                        }
                        profileSection(
                            title: "Key Intelligence",
                            subtitle: "Heatmap, diagnostics, transitions, and confidence.",
                            tint: trafficYellow
                        ) {
                            LazyVGrid(columns: detailColumns(for: dashboardWidth), spacing: Spacing.md) {
                                keyboardHeatmapCard
                                selectedKeyDetailCard
                                weakestKeysCard
                                transitionHotPathsCard
                            }
                            selectedKeyTelemetryStrip
                            progressOverviewCard
                            keyProgressCard
                        }
                        historySection(minHeight: max(260, geo.size.height * 0.28), tint: trafficRed)
                    }
                }
                .frame(width: dashboardWidth, alignment: .center)
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(minWidth: 720, minHeight: 720)
        .font(Typo.body)
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.json, .commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .onAppear {
            rebuildCachedState()
        }
        .onChange(of: selectedRange) { _, _ in
            rebuildCachedState()
        }
        .onChange(of: appState.trainingRuntime.sessions.count) { _, _ in
            rebuildCachedState()
        }
        .onChange(of: progressSmoothness) { _, newValue in
            cachedSmoothedPoints = AdaptiveSmoothedMetricPoint.build(from: cachedChartSessions, smoothness: newValue)
        }
        .onChange(of: selectedProgressRange) { _, _ in
            rebuildChartState()
        }
        .onChange(of: appState.settings.keyboardLayout) { _, _ in
            rebuildKeyboardKeys()
        }
        .task(id: cachedAnalysisTaskInput) {
            guard let input = cachedAnalysisTaskInput else { return }
            let sharedRuntime = appState.trainingRuntime
            let useSharedRuntime = selectedRange == .all && sharedRuntime.sessions == input.sessions
            if useSharedRuntime {
                let snapshot = appState.profileSnapshot
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    trainingProfile = snapshot
                    selectedKey = snapshot.detail(for: selectedKey)?.key ?? snapshot.suggestedFocusKey
                    rebuildKeyboardKeys()
                }
            } else {
                let snapshot = await Task.detached(priority: .userInitiated) {
                    AdaptiveTrainingProfileBuilder.build(
                        sessions: input.sessions,
                        language: input.language,
                        settings: input.settings
                    )
                }.value
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    trainingProfile = snapshot
                    selectedKey = snapshot.detail(for: selectedKey)?.key ?? snapshot.suggestedFocusKey
                    rebuildKeyboardKeys()
                }
            }
        }
    }

    private func header(for width: CGFloat) -> some View {
        let stackVertically = width < 920

        return Group {
            if stackVertically {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    headerCopy
                    headerControls(alignLeading: true, fullWidth: true)
                }
            } else {
                HStack(alignment: .top, spacing: Spacing.md) {
                    headerCopy
                    Spacer()
                    headerControls(alignLeading: false, fullWidth: false)
                }
            }
        }
    }

    private func overviewSummarySection(for width: CGFloat) -> some View {
        LazyVGrid(columns: summaryColumns(for: width), spacing: Spacing.sm) {
            ForEach(summarySnapshots) { snapshot in
                summarySnapshotCard(snapshot)
            }
        }
    }

    @ViewBuilder
    private func profileSection<Content: View>(
        title: String,
        subtitle: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.xs) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundStyle(ds.primaryText)

                Text("—")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ds.tertiaryText)

                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ds.tertiaryText)
                    .lineLimit(1)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func historySection(minHeight: CGFloat, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                isHistoryExpanded.toggle()
            } label: {
                HStack(alignment: .center, spacing: Spacing.sm) {
                    Circle()
                        .fill(tint)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("HISTORY".uppercased())
                            .font(Typo.label)
                            .foregroundStyle(ds.secondaryText)
                        Text("Saved sessions, import state, and cleanup controls.")
                            .font(Typo.caption)
                            .foregroundStyle(ds.tertiaryText)
                    }
                    Spacer()
                    Text(isHistoryExpanded ? "Collapse" : "Expand")
                        .font(Typo.caption)
                        .foregroundStyle(ds.secondaryText)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ds.secondaryText)
                        .rotationEffect(.degrees(isHistoryExpanded ? 90 : 0))
                        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.9), value: isHistoryExpanded)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(DSCardBackground())
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            if isHistoryExpanded {
                sessionHistory
                    .frame(minHeight: minHeight)
            }
        }
    }

    private var headerCopy: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Profile")
                .font(.system(size: 28, weight: .bold, design: .default))
            Text("\(learningResults.count) learning · \(testResults.count) test sessions")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(ds.secondaryText)
        }
    }

    private func headerControls(alignLeading: Bool, fullWidth: Bool) -> some View {
        VStack(alignment: alignLeading ? .leading : .trailing, spacing: Spacing.sm) {
            Picker("Range", selection: $selectedRange) {
                ForEach(AdaptiveAnalyticsRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: fullWidth ? .infinity : 320)

            HStack(spacing: Spacing.sm) {
                Button("Import Data") {
                    showImportPicker = true
                }
                .buttonStyle(.glass)
                .disabled(isImporting)

                Button("Export JSON") {
                    exportData()
                }
                .buttonStyle(.glass)
                .disabled(isImporting)
            }
            .frame(maxWidth: fullWidth ? .infinity : nil, alignment: alignLeading ? .leading : .trailing)
        }
    }

    private func summaryColumns(for width: CGFloat) -> [GridItem] {
        let count: Int
        switch width {
        case ..<700:
            count = 1
        default:
            count = 2
        }
        return Array(repeating: GridItem(.flexible(), spacing: Spacing.sm, alignment: .top), count: count)
    }

    private func detailColumns(for width: CGFloat) -> [GridItem] {
        let count: Int
        switch width {
        case ..<860:
            count = 1
        case ..<1200:
            count = 2
        default:
            count = 3
        }
        return Array(repeating: GridItem(.flexible(), spacing: Spacing.sm, alignment: .top), count: count)
    }

    private func chartColumns(for width: CGFloat) -> [GridItem] {
        let count = width < 1080 ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Spacing.sm, alignment: .top), count: count)
    }

    private func analysisDashboardWidth(for availableWidth: CGFloat) -> CGFloat {
        let horizontalPadding = Spacing.lg * 2
        return min(1180, max(680, availableWidth - horizontalPadding))
    }

    private func summarySnapshotCard(_ snapshot: AdaptiveSummarySnapshot) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ds.primaryText)
                Text(snapshot.subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ds.tertiaryText)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md)], spacing: Spacing.md) {
                ForEach(snapshot.metrics) { metric in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(ds.secondaryText)
                        Text(metric.value)
                            .font(Typo.displaySmall)
                            .monospacedDigit()
                            .foregroundStyle(color(for: metric.tone))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .padding(Spacing.lg)
        .background(DSGlassCard())
    }

    private var practiceCalendarCard: some View {
        let cellSize: CGFloat = 10
        let cellSpacing: CGFloat = 3

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center) {
                Text("Practice Calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ds.primaryText)
                Spacer()
                Text("Last 12 months")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ds.tertiaryText)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Month labels row
                    HStack(alignment: .bottom, spacing: cellSpacing) {
                        // Spacer for weekday label column
                        Color.clear
                            .frame(width: 28, height: 14)

                        ForEach(Array(activityWeeks.enumerated()), id: \.offset) { weekIndex, week in
                            Color.clear
                                .frame(width: cellSize, height: 14)
                                .overlay(alignment: .leading) {
                                    Text(monthLabel(for: weekIndex, week: week))
                                        .font(.system(size: 9, weight: .regular))
                                        .foregroundStyle(ds.tertiaryText)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                        }
                    }
                    .padding(.bottom, 4)

                    // Grid: weekday labels on left + cells
                    HStack(alignment: .top, spacing: cellSpacing) {
                        // Weekday labels column
                        VStack(alignment: .trailing, spacing: cellSpacing) {
                            ForEach(0..<7, id: \.self) { dayIndex in
                                Text(calendarDayLabel(for: dayIndex))
                                    .font(.system(size: 9, weight: .regular))
                                    .foregroundStyle(ds.tertiaryText)
                                    .frame(width: 28, height: cellSize, alignment: .trailing)
                            }
                        }

                        // Week columns
                        ForEach(activityWeeks.indices, id: \.self) { weekIndex in
                            VStack(spacing: cellSpacing) {
                                ForEach(0..<7, id: \.self) { dayIndex in
                                    if dayIndex < activityWeeks[weekIndex].count {
                                        let day = activityWeeks[weekIndex][dayIndex]
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .fill(activityColor(for: day.count))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                                    .stroke(day.isToday ? trafficYellow.opacity(0.85) : .clear, lineWidth: 1)
                                            )
                                            .frame(width: cellSize, height: cellSize)
                                            .help("\(day.count) sessions · \(day.date.formatted(date: .abbreviated, time: .omitted))")
                                    } else {
                                        Color.clear
                                            .frame(width: cellSize, height: cellSize)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: Spacing.xs) {
                Spacer()
                Text("Less")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(ds.tertiaryText)
                ForEach(0..<4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(activityLegendColor(level: level))
                        .frame(width: cellSize, height: cellSize)
                }
                Text("More")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(ds.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(Spacing.lg)
        .background(DSGlassCard())
    }

    private var dailyGoalCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(dailyGoalCardTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ds.primaryText)

            if trainingProfile.dailyGoal.targetMinutes == 0 {
                Text("Set a daily goal in Settings to track practice targets here.")
                    .foregroundStyle(ds.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(trainingProfile.dailyGoal.completedMinutes)")
                            .font(Typo.displayMedium)
                            .monospacedDigit()
                        Text("/ \(trainingProfile.dailyGoal.targetMinutes) min")
                            .font(Typo.body)
                            .foregroundStyle(ds.secondaryText)
                    }

                    ProgressView(value: trainingProfile.dailyGoal.progress)
                        .tint(trainingProfile.dailyGoal.isComplete ? ds.success : trafficYellow)

                    Text(
                        trainingProfile.dailyGoal.isComplete
                            ? "Goal reached. The next target is raised automatically and can still be changed in Settings."
                            : "Today's practice progress updates live from completed sessions."
                    )
                    .font(Typo.caption)
                    .foregroundStyle(ds.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                    if trainingProfile.streakDays > 0 {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(trafficYellow)
                            Text("\(trainingProfile.streakDays)-day learning streak")
                                .font(Typo.caption)
                                .foregroundStyle(ds.secondaryText)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .padding(Spacing.lg)
        .background(DSGlassCard())
    }

    private var currentTrainingPlanCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Training Plan")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ds.primaryText)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)], spacing: Spacing.sm) {
                compactMetricTile(
                    title: "Source",
                    value: analysis.currentLesson.source.capitalized,
                    detail: analysis.currentLesson.focusedKey.map { "focus \($0.uppercased())" } ?? "mixed focus",
                    tint: trafficYellow
                )
                compactMetricTile(
                    title: "Forecast",
                    value: analysis.forecast?.remainingLessons.map(String.init) ?? "—",
                    detail: analysis.forecast == nil ? "needs more signal" : "lessons remaining",
                    tint: ds.success
                )
                compactMetricTile(
                    title: "Learning Rate",
                    value: analysis.forecast.map { String(format: "%+.1f", $0.learningRateCPMPerLesson) } ?? "—",
                    detail: "cpm per lesson",
                    tint: ds.primaryText
                )
                compactMetricTile(
                    title: "Certainty",
                    value: analysis.forecast.map { percentString($0.certainty) } ?? "—",
                    detail: "forecast confidence",
                    tint: ds.warning
                )
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: Spacing.sm)], spacing: Spacing.sm) {
                summaryBadge(title: "Words", value: appState.settings.adaptiveNaturalWords ? "Natural" : "Pseudo", color: trafficYellow)
                summaryBadge(title: "Unlock", value: appState.settings.adaptiveUnlockStrategy == .layoutAware ? "Keyboard" : "Frequency", color: trafficYellow)
                summaryBadge(title: "Keyboard", value: appState.settings.keyboardLayout.title, color: trafficGreen)
                summaryBadge(title: "Recover", value: appState.settings.adaptiveRecoverKeys ? "On" : "Off", color: trafficRed)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Active Alphabet")
                    .font(Typo.caption)
                    .foregroundStyle(ds.secondaryText)
                FlowKeyCaps(keys: analysis.currentLesson.activeAlphabet, focusedKey: analysis.currentLesson.focusedKey)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .padding(Spacing.lg)
        .background(DSGlassCard())
    }

    private var keyboardHeatmapCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Keyboard Analysis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ds.primaryText)
                Spacer()
                Text(appState.settings.keyboardLayout.title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ds.tertiaryText)
            }

            VStack(alignment: .center, spacing: Spacing.sm) {
                ForEach(Array(appState.settings.keyboardLayout.rows.enumerated()), id: \.offset) { index, row in
                    KeyboardHeatmapRow(keys: row, intensity: analysis.keyboard.keyIntensity)
                        .padding(.leading, CGFloat(index) * 18)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Spacing.sm)], spacing: Spacing.sm) {
                keyboardMetric(title: "Home Row", value: percentString(analysis.keyboard.homeRowRatio), tint: ds.success)
                keyboardMetric(title: "Top Row", value: percentString(analysis.keyboard.topRowRatio), tint: ds.warning)
                keyboardMetric(title: "Bottom Row", value: percentString(analysis.keyboard.bottomRowRatio), tint: ds.warning)
                keyboardMetric(title: "Same Hand", value: percentString(analysis.keyboard.sameHandRatio), tint: ds.error)
                keyboardMetric(title: "Same Finger", value: percentString(analysis.keyboard.sameFingerRatio), tint: ds.error)
            }
        }
        .padding(Spacing.lg)
        .background(DSGlassCard())
    }

    private var recentEventsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Recent Events")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ds.primaryText)

            if runtimeRecentEvents.isEmpty {
                Text("Milestones appear here as you unlock keys, hit speed records, and complete daily goals.")
                    .foregroundStyle(ds.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(runtimeRecentEvents.sorted(by: { $0.date > $1.date }).prefix(3)) { event in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack(alignment: .center, spacing: Spacing.sm) {
                                Label(event.title, systemImage: symbol(for: event.kind))
                                    .font(Typo.body)
                                    .foregroundStyle(ds.primaryText)
                                Spacer(minLength: 0)
                                Text(event.date, format: .dateTime.month().day())
                                    .font(Typo.tooltip)
                                    .foregroundStyle(ds.tertiaryText)
                            }

                            Text(event.detail)
                                .font(Typo.caption)
                                .foregroundStyle(ds.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.sm)
                        .background(ds.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .padding(Spacing.lg)
        .background(DSGlassCard())
    }

    private var lastLessonCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Last Lesson")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ds.primaryText)

            if let feedback = runtimeLastLessonFeedback {
                HStack(spacing: Spacing.sm) {
                    summaryBadge(title: "Focus", value: feedback.focusedKey?.uppercased() ?? "Mixed", color: trafficYellow)
                    summaryBadge(title: "Steps", value: "\(feedback.stepCount)", color: ds.primaryText)
                }

                lessonFeedbackGroup(
                    title: "Miss Digraphs",
                    emptyText: "No miss digraphs recorded in the latest learning session.",
                    entries: feedback.topMissedDigraphs.map { "\($0.pair) ×\($0.count)" }
                )

                lessonFeedbackGroup(
                    title: "Correction Hotspots",
                    emptyText: "No correction hotspots recorded.",
                    entries: feedback.correctionHotspots.map { "\($0.pair) ×\($0.count)" }
                )
            } else {
                Text("Complete a few learning sessions to unlock per-lesson feedback.")
                    .foregroundStyle(ds.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .padding(Spacing.lg)
        .background(DSGlassCard())
    }

    private var adaptiveStateChartCard: some View {
        EmptyView()
    }

    private var progressChart: some View {
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Progress Over Time")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ds.primaryText)
                Spacer()
                Text("WPM and accuracy trends")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ds.tertiaryText)
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Picker("Progress Range", selection: $selectedProgressRange) {
                    ForEach(AdaptiveAnalyticsRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Smoothing")
                        .font(Typo.caption)
                        .foregroundStyle(ds.secondaryText)
                    Spacer()
                    Text("\(Int((progressSmoothness * 100).rounded()))%")
                        .font(Typo.caption)
                        .foregroundStyle(ds.secondaryText)
                        .monospacedDigit()
                }
                Slider(value: $progressSmoothness, in: 0...0.9, step: 0.05)
            }

            combinedProgressChart

            // Legend
            HStack(spacing: Spacing.md) {
                HStack(spacing: Spacing.xxs) {
                    Circle().fill(trafficYellow).frame(width: 7, height: 7)
                    Text("WPM")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ds.secondaryText)
                }
                HStack(spacing: Spacing.xxs) {
                    Circle().fill(ds.success).frame(width: 7, height: 7)
                    Text("Accuracy")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ds.secondaryText)
                }
            }
        }
        .padding(Spacing.lg)
        .background(DSGlassCard())
    }

    private var weakestKeysCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Weakest Keys")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ds.primaryText)

            if analysis.weakestKeys.isEmpty {
                Text("Weak keys appear after enough adaptive sessions to estimate confidence.")
                    .foregroundStyle(ds.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(analysis.weakestKeys) { key in
                        Button {
                            selectedKey = key.key
                        } label: {
                            HStack(alignment: .center, spacing: Spacing.sm) {
                                Text(key.key.uppercased())
                                    .font(Typo.displaySmall)
                                    .frame(width: 32, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Confidence \(percentString(key.confidence ?? 0))")
                                        .font(Typo.caption)
                                    Text("Accuracy \(percentString(key.accuracy))")
                                        .font(Typo.caption)
                                        .foregroundStyle(ds.secondaryText)
                                }
                                Spacer()
                                Text(key.latestTimeMS.map { "\(Int($0.rounded())) ms" } ?? "new")
                                    .font(Typo.caption)
                                    .foregroundStyle(ds.secondaryText)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .padding(Spacing.lg)
        .background(DSGlassCard())
    }

    private var transitionHotPathsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Transition Hot Paths")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ds.primaryText)

            if analysis.transitions.isEmpty {
                Text("Transition telemetry appears after a few adaptive sessions.")
                    .foregroundStyle(ds.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(analysis.transitions) { transition in
                        HStack(alignment: .center, spacing: Spacing.sm) {
                            Text("\(transition.fromKey.uppercased())\(transition.toKey.uppercased())")
                                .font(Typo.displaySmall)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(transition.count)x")
                                    .font(Typo.caption)
                                    .monospacedDigit()
                                Text("\(Int(transition.averageTimeMS.rounded())) ms")
                                    .font(Typo.caption)
                                    .foregroundStyle(ds.secondaryText)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240, alignment: .topLeading)
        .padding(Spacing.lg)
        .background(DSGlassCard())
    }

    private var selectedKeyDetailCard: some View {
        let selectableKeys = keyboardOrderedAnalysisKeys
            .filter { $0.samples > 0 || $0.isIncluded || $0.misses > 0 }

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Key Detail")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ds.primaryText)
                Spacer()
                if !selectableKeys.isEmpty {
                    Picker("Key", selection: Binding(
                        get: { selectedKey ?? trainingProfile.suggestedFocusKey ?? selectableKeys.first?.key ?? "a" },
                        set: { selectedKey = $0 }
                    )) {
                        ForEach(selectableKeys) { key in
                            Text(key.key.uppercased()).tag(key.key)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }
            }

            if let detail = trainingProfile.detail(for: selectedKey ?? trainingProfile.suggestedFocusKey) {
                let selectedProfile = analysis.allKeys.first(where: { $0.key == detail.key })
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(detail.key.uppercased())
                                .font(Typo.displayMedium)
                            Text(detail.stateLabel)
                                .font(Typo.caption)
                                .foregroundStyle(ds.secondaryText)
                            Text("accuracy \(percentString(detail.accuracy))")
                                .font(Typo.caption)
                                .foregroundStyle(ds.secondaryText)
                        }
                        Spacer()
                        summaryBadge(
                            title: "Need",
                            value: percentString(min(1, detail.needScore / 1.8)),
                            color: selectedProfile.map { keyStatusColor(for: $0) } ?? ds.warning
                        )
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: Spacing.sm)], spacing: Spacing.sm) {
                        detailMetricPanel("Current", percentString(detail.confidence ?? 0))
                        detailMetricPanel("Best", percentString(detail.bestConfidence ?? 0))
                        detailMetricPanel("Latest", detail.latestTimeMS.map { "\(Int($0.rounded())) ms" } ?? "—")
                        detailMetricPanel("Best Time", detail.bestTimeMS.map { "\(Int($0.rounded())) ms" } ?? "—")
                        detailMetricPanel("Hits", "\(detail.hits)")
                        detailMetricPanel("Misses", "\(detail.misses)")
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)], spacing: Spacing.sm) {
                        transitionGroup(title: "Incoming", transitions: detail.incomingTransitions)
                        transitionGroup(title: "Outgoing", transitions: detail.outgoingTransitions)
                    }
                }
            } else if selectableKeys.isEmpty {
                Text("Key detail appears once adaptive analysis finishes loading for the selected range.")
                    .foregroundStyle(ds.secondaryText)
            } else {
                Text("Key detail appears once a learning key becomes active.")
                    .foregroundStyle(ds.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .padding(Spacing.lg)
        .background(DSGlassCard())
    }

    private var selectedKeyTelemetryStrip: some View {
        let activeAlphabet = analysis.currentLesson.activeAlphabet
        let activeProfiles = activeAlphabet.compactMap { key in
            analysis.allKeys.first(where: { $0.key == key })
        }
        let currentKey = analysis.allKeys.first(where: { $0.key == (selectedKey ?? trainingProfile.suggestedFocusKey) })
        let currentDetail = trainingProfile.detail(for: currentKey?.key)

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Key Telemetry")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ds.primaryText)
                Spacer()
                Text("per-key snapshot")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ds.tertiaryText)
            }

            ViewThatFits(in: .horizontal) {
                telemetryMetricsRow(currentDetail: currentDetail, currentKey: currentKey)
                ScrollView(.horizontal, showsIndicators: false) {
                    telemetryMetricsRow(currentDetail: currentDetail, currentKey: currentKey)
                }
            }

            HStack(alignment: .center, spacing: Spacing.sm) {
                Text("Alphabet:")
                    .font(Typo.body)
                    .foregroundStyle(ds.primaryText)

                if activeAlphabet.isEmpty {
                    Text("No active alphabet is available yet.")
                        .font(Typo.caption)
                        .foregroundStyle(ds.secondaryText)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(activeProfiles) { profile in
                                Button {
                                    selectedKey = profile.key
                                } label: {
                                    telemetryKeyChip(
                                        for: profile,
                                        isSelected: profile.key == (currentKey?.key ?? trainingProfile.suggestedFocusKey)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
            }

            HStack(alignment: .center, spacing: Spacing.sm) {
                Text("Current key:")
                    .font(Typo.body)
                    .foregroundStyle(ds.primaryText)

                if let detail = currentDetail, let currentKey {
                    telemetryKeyChip(for: currentKey, isSelected: true)

                    Text(keyStatusLabel(for: currentKey))
                        .font(Typo.body)
                        .foregroundStyle(ds.secondaryText)

                    Text("Current \(percentString(detail.confidence ?? 0))")
                        .font(Typo.caption)
                        .foregroundStyle(ds.secondaryText)
                        .monospacedDigit()

                    Text("Best \(percentString(detail.bestConfidence ?? 0))")
                        .font(Typo.caption)
                        .foregroundStyle(ds.secondaryText)
                        .monospacedDigit()

                    Text("Incoming \(detail.incomingTransitions.first?.pair ?? "—")")
                        .font(Typo.caption)
                        .foregroundStyle(ds.tertiaryText)
                        .monospacedDigit()

                    Text("Outgoing \(detail.outgoingTransitions.first?.pair ?? "—")")
                        .font(Typo.caption)
                        .foregroundStyle(ds.tertiaryText)
                        .monospacedDigit()
                } else {
                    Text("No adaptive key detail is available yet.")
                        .font(Typo.caption)
                        .foregroundStyle(ds.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .leading)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.lg)
        .background(DSCardBackground())
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                .stroke(ds.borderSubtle, lineWidth: 0.8)
        )
    }

    private var keyProgressCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Keyboard Key Progress")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ds.primaryText)
                Spacer()
                Text(appState.settings.keyboardLayout.title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ds.tertiaryText)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        keyProgressHeader("Key", width: 34, alignment: .leading)
                        keyProgressHeader("State", width: 70, alignment: .leading)
                        keyProgressHeader("Progress", width: 170, alignment: .leading)
                        keyProgressHeader("Speed", width: 68, alignment: .trailing)
                        keyProgressHeader("Acc", width: 54, alignment: .trailing)
                        keyProgressHeader("Hits", width: 50, alignment: .trailing)
                        keyProgressHeader("Miss", width: 50, alignment: .trailing)
                    }

                    ForEach(keyboardOrderedAnalysisKeys) { key in
                        GridRow {
                            Text(key.key.uppercased())
                                .font(Typo.body)
                                .frame(width: 34, alignment: .leading)

                            Text(keyStatusLabel(for: key))
                                .font(Typo.caption)
                                .foregroundStyle(ds.secondaryText)
                                .frame(width: 70, alignment: .leading)

                            keyProgressMeter(for: key)
                                .frame(width: 170, alignment: .leading)

                            Text(key.latestTimeMS.map { "\(Int($0.rounded()))" } ?? "—")
                                .font(Typo.caption)
                                .monospacedDigit()
                                .frame(width: 68, alignment: .trailing)

                            Text(percentString(key.accuracy))
                                .font(Typo.caption)
                                .monospacedDigit()
                                .frame(width: 54, alignment: .trailing)

                            Text("\(key.hits)")
                                .font(Typo.caption)
                                .monospacedDigit()
                                .frame(width: 50, alignment: .trailing)

                            Text("\(key.misses)")
                                .font(Typo.caption)
                                .monospacedDigit()
                                .foregroundStyle(key.misses > 0 ? ds.error : ds.secondaryText)
                                .frame(width: 50, alignment: .trailing)
                        }
                        GridRow {
                            Divider()
                                .gridCellColumns(7)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(Spacing.lg)
        .background(DSGlassCard())
    }

    private var progressOverviewCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center) {
                Text("Learning Progress")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ds.primaryText)
                Spacer()
                Text("outline = focused key")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ds.tertiaryText)
            }

            if trainingProfile.progressOverview.columns.isEmpty {
                Text("Complete a few learning sessions to unlock the progress overview.")
                    .foregroundStyle(ds.secondaryText)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .bottom, spacing: 6) {
                            Text(" ")
                                .frame(width: 20)
                            ForEach(trainingProfile.progressOverview.columns) { column in
                                progressOverviewHeader(column)
                            }
                        }

                        ForEach(trainingProfile.progressOverview.rows) { row in
                            HStack(spacing: 6) {
                                Text(row.key.uppercased())
                                    .font(Typo.tooltip)
                                    .foregroundStyle(ds.secondaryText)
                                    .frame(width: 20, alignment: .leading)

                                ForEach(row.samples) { sample in
                                    progressOverviewCell(sample)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(Spacing.lg)
        .background(DSGlassCard())
    }

    private var sessionHistory: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center) {
                Text("Session History")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ds.primaryText)
                Spacer()
                Text("\(filteredSessions.count) sessions")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(ds.tertiaryText)
                    .monospacedDigit()
            }

            VStack(spacing: 0) {
                ForEach(Array(sessionHistoryEntries.enumerated()), id: \.element.id) { index, entry in
                    HStack(alignment: .center, spacing: Spacing.md) {
                        // Mode badge
                        Text(entry.session.modeDescriptor.sessionMode == .learning ? "L" : "T")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(entry.session.modeDescriptor.sessionMode == .learning ? ds.success : trafficYellow)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(entry.session.modeDescriptor.sessionMode == .learning ? ds.success.opacity(0.12) : trafficYellow.opacity(0.12))
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: Spacing.xs) {
                                Text("\(entry.session.wpm, specifier: "%.0f") WPM")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                Text("·")
                                    .foregroundStyle(ds.tertiaryText)
                                Text("\(entry.session.accuracy, specifier: "%.0f")%")
                                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                                    .foregroundStyle(ds.secondaryText)
                            }
                            HStack(spacing: Spacing.xs) {
                                Text(entry.session.date, format: .dateTime.month().day().hour().minute())
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(ds.tertiaryText)
                                if let focusKey = entry.session.adaptivePayload?.lesson.focusedKey {
                                    Text("focus \(focusKey.uppercased())")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(ds.tertiaryText)
                                }
                            }
                        }

                        Spacer()

                        Button(role: .destructive) {
                            deleteSession(entry)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(ds.tertiaryText)
                                .frame(width: 26, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(ds.surface)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isImporting || isDeletingSession)
                        .opacity(deletingSessionID == entry.id ? 0.45 : 1)
                    }
                    .padding(.vertical, Spacing.xs)

                    if index < sessionHistoryEntries.count - 1 {
                        Divider()
                            .opacity(0.5)
                    }
                }
            }

            if isImporting || statusMessage != nil {
                HStack(spacing: Spacing.xs) {
                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(ds.secondaryText)
                    }
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(ds.surface)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .padding(Spacing.lg)
        .background(DSGlassCard())
    }

    private func deleteSession(_ entry: AdaptiveSessionHistoryEntry) {
        guard deletingSessionID == nil else { return }
        deletingSessionID = entry.id
        statusMessage = "Deleting session…"
        let container = modelContext.container
        let deduplicationKey = entry.session.deduplicationKey

        Task {
            do {
                let historyStore = HistoryStoreActor(modelContainer: container)
                let deleted = try await historyStore.deleteSession(matching: deduplicationKey)
                await MainActor.run {
                    deletingSessionID = nil
                    if deleted {
                        appState.removeTrainingHistorySession(with: deduplicationKey)
                        statusMessage = "Deleted session from history."
                    } else {
                        statusMessage = "Could not locate the stored session to delete."
                    }
                }
            } catch {
                await MainActor.run {
                    deletingSessionID = nil
                    statusMessage = "Delete failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func keyboardMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(Typo.caption)
                .foregroundStyle(ds.secondaryText)
            Text(value)
                .font(Typo.displaySmall)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryBadge(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(Typo.caption)
                .foregroundStyle(ds.secondaryText)
            Text(value)
                .font(Typo.body)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(ds.tooltipFill, in: RoundedRectangle(cornerRadius: CornerRadius.small))
    }

    private func compactMetricTile(title: String, value: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title.uppercased())
                .font(Typo.tooltip)
                .foregroundStyle(ds.secondaryText)
            Text(value)
                .font(Typo.displaySmall)
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(Typo.caption)
                .foregroundStyle(ds.tertiaryText)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(DSCardBackground())
    }

    private func detailMetricPanel(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(Typo.tooltip)
                .foregroundStyle(ds.secondaryText)
            Text(value)
                .font(Typo.caption)
                .monospacedDigit()
                .foregroundStyle(ds.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(DSCardBackground())
    }

    private func transitionGroup(title: String, transitions: [AdaptiveTransitionDetail]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title.uppercased())
                .font(Typo.caption)
                .foregroundStyle(ds.secondaryText)

            if transitions.isEmpty {
                Text("Not enough signal yet")
                    .font(Typo.caption)
                    .foregroundStyle(ds.secondaryText)
            } else {
                ForEach(transitions) { transition in
                    Text("\(transition.pair) · \(Int(transition.averageTimeMS.rounded())) ms")
                        .font(Typo.caption)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(DSCardBackground())
    }

    private func lessonFeedbackGroup(title: String, emptyText: String, entries: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title.uppercased())
                .font(Typo.caption)
                .foregroundStyle(ds.secondaryText)

            if entries.isEmpty {
                Text(emptyText)
                    .font(Typo.caption)
                    .foregroundStyle(ds.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(entries, id: \.self) { entry in
                    Text(entry)
                        .font(Typo.caption)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(DSCardBackground())
    }

    private func color(for kind: TrainingProfileEventKind) -> Color {
        switch kind {
        case .unlockedKey:
            return trafficGreen
        case .newBestSpeed:
            return trafficYellow
        case .dailyGoal:
            return trafficYellow
        case .streak:
            return trafficRed
        }
    }

    private func symbol(for kind: TrainingProfileEventKind) -> String {
        switch kind {
        case .unlockedKey:
            return "keyboard"
        case .newBestSpeed:
            return "gauge.with.dots.needle.100percent"
        case .dailyGoal:
            return "checkmark.circle.fill"
        case .streak:
            return "flame.fill"
        }
    }

    private func keyStatusLabel(for key: AdaptiveKeyProfile) -> String {
        if key.isFocused {
            return "Focus"
        }
        if key.isForced {
            return "Forced"
        }
        if key.isIncluded {
            return "Active"
        }
        if key.samples > 0 || key.misses > 0 {
            return "Learned"
        }
        return "Queued"
    }

    private func keyStatusColor(for key: AdaptiveKeyProfile) -> Color {
        if key.isFocused {
            return ds.warning
        }
        if key.isIncluded {
            return ds.success
        }
        if key.misses > 0 {
            return ds.error
        }
        return ds.secondaryText
    }

    private func color(for tone: AdaptiveSummaryTone) -> Color {
        switch tone {
        case .primary:
            return ds.primaryText
        case .accent:
            return trafficYellow
        case .success:
            return trafficGreen
        }
    }

    private func keyProgressMeter(for key: AdaptiveKeyProfile) -> some View {
        let progress = min(1.25, max(0, key.confidence ?? key.bestConfidence ?? 0))
        let cappedProgress = min(1, progress)
        let tint: Color
        switch progress {
        case 1...:
            tint = ds.success
        case 0.7..<1:
            tint = ds.warning
        default:
            tint = ds.error
        }

        return VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 8)

                Capsule()
                    .fill(tint)
                    .frame(width: max(10, 170 * cappedProgress), height: 8)

                Rectangle()
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 1, height: 12)
                    .offset(x: 170 - 1)
            }

            Text("\(Int((progress * 100).rounded()))%")
                .font(Typo.caption)
                .foregroundStyle(ds.secondaryText)
                .monospacedDigit()
        }
    }

    private func keyProgressHeader(_ title: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(title.uppercased())
            .font(Typo.caption)
            .foregroundStyle(ds.secondaryText)
            .frame(width: width, alignment: alignment)
    }

    /// Combined dual-line chart showing WPM (left axis) and Accuracy (right axis) in one view.
    private var combinedProgressChart: some View {
        let points = smoothedProgressPoints
        let wpmMax = chartMaxY
        let accMax = 100.0

        return ZStack(alignment: .topLeading) {
            Chart {
                // WPM line
                ForEach(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("WPM", point.wpm),
                        series: .value("Series", "WPM")
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(trafficYellow)
                    .lineStyle(.init(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                }

                // Accuracy line — normalized to WPM scale so both share the same Y axis visually
                ForEach(points) { point in
                    let normalizedAccuracy = (point.accuracy / accMax) * wpmMax
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Accuracy", normalizedAccuracy),
                        series: .value("Series", "Accuracy")
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(ds.success)
                    .lineStyle(.init(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                }

                // Hover indicator
                if let hoveredResult {
                    RuleMark(x: .value("Selected", hoveredResult.date))
                        .foregroundStyle(.secondary.opacity(0.45))
                        .lineStyle(.init(lineWidth: 1, dash: [4, 4]))

                    PointMark(
                        x: .value("Date", hoveredResult.date),
                        y: .value("WPM", hoveredResult.wpm)
                    )
                    .foregroundStyle(trafficYellow)
                    .symbolSize(34)

                    let normalizedHoveredAcc = (hoveredResult.accuracy / accMax) * wpmMax
                    PointMark(
                        x: .value("Date", hoveredResult.date),
                        y: .value("Accuracy", normalizedHoveredAcc)
                    )
                    .foregroundStyle(ds.success)
                    .symbolSize(34)
                }
            }
            .chartYScale(domain: 0...wpmMax)
            .chartYAxis {
                // Left axis: WPM
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))")
                                .font(.system(size: 9))
                                .foregroundStyle(trafficYellow.opacity(0.8))
                        }
                    }
                }
                // Right axis: Accuracy (rescaled)
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            let accuracyValue = (v / wpmMax) * accMax
                            Text("\(Int(accuracyValue.rounded()))%")
                                .font(.system(size: 9))
                                .foregroundStyle(ds.success.opacity(0.8))
                        }
                    }
                }
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
                                hoveredChartDate = proxy.value(atX: x)
                                hoveredChartLocation = location
                            case .ended:
                                hoveredChartDate = nil
                                hoveredChartLocation = nil
                            }
                        }
                }
            }
            .frame(height: 180)

            // Hover tooltip
            GeometryReader { overlayGeo in
                if let hoveredResult,
                   let hoveredChartLocation {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(hoveredResult.date, format: .dateTime.month().day().hour().minute())
                        Text("\(Int(hoveredResult.wpm.rounded())) WPM")
                            .foregroundStyle(trafficYellow)
                        Text("\(Int(hoveredResult.accuracy.rounded()))%")
                            .foregroundStyle(ds.success)
                    }
                    .font(Typo.tooltip)
                    .padding(Spacing.xs)
                    .background(ds.tooltipFill, in: RoundedRectangle(cornerRadius: CornerRadius.small))
                    .position(
                        x: clamped(hoveredChartLocation.x + 88, min: 92, max: overlayGeo.size.width - 92),
                        y: clamped(hoveredChartLocation.y - 20, min: 28, max: overlayGeo.size.height - 28)
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func telemetryMetricLabel(_ title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Text("\(title):")
                .font(Typo.body)
                .foregroundStyle(ds.primaryText)
            Text(value)
                .font(Typo.body)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
    }

    private func telemetryMetricsRow(
        currentDetail: AdaptiveKeyDetail?,
        currentKey: AdaptiveKeyProfile?
    ) -> some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Text("Metrics:")
                .font(Typo.body)
                .foregroundStyle(ds.primaryText)

            if let detail = currentDetail, let currentKey {
                telemetryMetricLabel("Last speed", value: speedString(for: detail.latestTimeMS), tint: ds.primaryText)
                telemetryMetricLabel("Top speed", value: speedString(for: detail.bestTimeMS), tint: ds.primaryText)
                telemetryMetricLabel("Accuracy", value: percentString(detail.accuracy), tint: ds.success)
                telemetryMetricLabel("Misses", value: "\(detail.misses)", tint: detail.misses > 0 ? ds.error : ds.secondaryText)
                telemetryMetricLabel("Samples", value: "\(detail.sampleCount)", tint: keyStatusColor(for: currentKey))
            } else {
                Text("Select a tracked key to inspect its current signal.")
                    .font(Typo.caption)
                    .foregroundStyle(ds.secondaryText)
            }
        }
    }

    private func telemetryKeyChip(for key: AdaptiveKeyProfile, isSelected: Bool) -> some View {
        let fill = keyStatusColor(for: key).opacity(isSelected ? 0.64 : 0.26)

        return Text(key.key.uppercased())
            .font(Typo.caption.weight(.semibold))
            .foregroundStyle(isSelected ? ds.primaryText : ds.secondaryText)
            .monospaced()
            .frame(width: 32, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(isSelected ? ds.border : ds.borderSubtle, lineWidth: isSelected ? 1.2 : 0.8)
            )
    }

    private func speedString(for timeMS: Double?) -> String {
        guard let timeMS, timeMS.isFinite, timeMS > 0 else { return "—" }
        let wpm = 60_000 / (timeMS * 5)
        return String(format: "%.1f wpm", wpm)
    }

    private func progressOverviewHeader(_ column: AdaptiveProgressOverviewColumn) -> some View {
        VStack(spacing: 2) {
            Text(column.date.formatted(.dateTime.day()))
                .font(Typo.tooltip)
                .foregroundStyle(ds.secondaryText)
            Text(column.focusedKey?.uppercased() ?? "·")
                .font(Typo.tooltip)
                .foregroundStyle(ds.tertiaryText)
        }
        .frame(width: 18)
        .help("\(column.date.formatted(date: .abbreviated, time: .shortened)) · focus \(column.focusedKey?.uppercased() ?? "mixed") · \(column.activeAlphabetSize) active keys")
    }

    private func progressOverviewCell(_ sample: AdaptiveProgressOverviewSample) -> some View {
        let progress = min(1.25, max(0, sample.confidence ?? sample.bestConfidence ?? 0))
        let fill: Color
        if !sample.isActive && progress <= 0 {
            fill = ds.surfaceElevated
        } else if progress >= 1 {
            fill = ds.success.opacity(sample.isActive ? 0.9 : 0.45)
        } else if progress >= 0.7 {
            fill = ds.warning.opacity(sample.isActive ? 0.88 : 0.42)
        } else if progress > 0 {
            fill = ds.error.opacity(sample.isActive ? 0.84 : 0.38)
        } else {
            fill = ds.surface.opacity(0.7)
        }

        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(sample.isFocused ? trafficYellow : ds.borderSubtle, lineWidth: sample.isFocused ? 1.2 : 0.8)
            )
            .frame(width: 18, height: 18)
            .help("\(sample.key.uppercased()) · \(sample.confidence.map { percentString($0) } ?? "new")")
    }

    private func percentString(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func intString(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    private static let shortDurationFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.minute]
        f.unitsStyle = .abbreviated
        f.zeroFormattingBehavior = .dropAll
        return f
    }()

    private static let longDurationFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .abbreviated
        f.zeroFormattingBehavior = .dropAll
        return f
    }()

    private func durationString(_ duration: TimeInterval) -> String {
        let clamped = max(0, duration)
        let formatter = clamped >= 3600 ? Self.longDurationFormatter : Self.shortDurationFormatter
        return formatter.string(from: clamped) ?? "0m"
    }

    private func monthLabel(for weekIndex: Int, week: [AdaptiveActivityCell]) -> String {
        guard let firstDay = week.first?.date else { return "" }
        return shouldLabelMonth(for: weekIndex, week: week)
            ? firstDay.formatted(.dateTime.month(.abbreviated))
            : ""
    }

    private func weekdayLabel(for index: Int) -> String {
        switch index {
        case 1:
            return "Mon"
        case 3:
            return "Wed"
        case 5:
            return "Fri"
        default:
            return ""
        }
    }

    private func calendarDayLabel(for index: Int) -> String {
        switch index {
        case 1: return "Mon"
        case 3: return "Wed"
        case 5: return "Fri"
        default: return ""
        }
    }

    private func shouldLabelMonth(for weekIndex: Int, week: [AdaptiveActivityCell]) -> Bool {
        guard let firstDay = week.first?.date else { return false }
        guard weekIndex > 0 else { return false }
        let previousWeek = activityWeeks[weekIndex - 1]
        guard let previousDay = previousWeek.first?.date else { return false }
        return profileCalendar.component(.month, from: firstDay) != profileCalendar.component(.month, from: previousDay)
    }

    private func activityLegendColor(level: Int) -> Color {
        switch level {
        case 0:
            return ds.surfaceElevated
        case 1:
            return trafficYellow.opacity(0.22)
        case 2:
            return trafficYellow.opacity(0.46)
        default:
            return trafficYellow.opacity(0.82)
        }
    }

    private func activityColor(for count: Int) -> Color {
        guard count > 0 else { return ds.surfaceElevated }
        let normalized = Double(count) / Double(maxActivityCount)
        switch normalized {
        case 0..<0.34:
            return trafficYellow.opacity(0.22)
        case 0.34..<0.67:
            return trafficYellow.opacity(0.46)
        default:
            return trafficYellow.opacity(0.82)
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: Spacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(Typo.caption)
                .foregroundStyle(ds.secondaryText)
        }
    }

    private func clamped(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first else { return }
            isImporting = true
            statusMessage = "Importing \(fileURL.lastPathComponent)…"

            let container = modelContext.container
            Task {
                do {
                    let importer = HistoryStoreActor(modelContainer: container)
                    let loadResult = try await Task.detached(priority: .userInitiated) {
                        try HistoryImportPipeline.loadSessionBatch(from: fileURL)
                    }.value
                    let imported = try await importer.importSessions(loadResult.sessions)
                    await MainActor.run {
                        appState.reloadTrainingHistory(from: container)
                        isImporting = false
                        if loadResult.discardedRowCount > 0 {
                            statusMessage = imported.summaryText + " · skipped \(loadResult.discardedRowCount) malformed CSV rows"
                        } else {
                            statusMessage = imported.summaryText
                        }
                    }
                } catch {
                    await MainActor.run {
                        isImporting = false
                        statusMessage = "Import failed: \(error.localizedDescription)"
                    }
                }
            }
        case .failure(let error):
            isImporting = false
            statusMessage = "Import canceled: \(error.localizedDescription)"
        }
    }

    private func exportData() {
        let normalizedSessions = appState.trainingRuntime.sessions
            .sorted { $0.date < $1.date }
        let package = HistoryTransferPackage(
            exportedAt: .now,
            sessions: normalizedSessions.map(\.historyTransferSession)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        #if os(macOS)
        do {
            let payload = try encoder.encode(package)
            presentExportPanel(for: payload)
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
        #endif
    }

    #if os(macOS)
    @MainActor
    private func presentExportPanel(for payload: Data) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.nameFieldStringValue = "typer-history.json"

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let destinationURL = savePanel.url else {
                statusMessage = "Export canceled."
                return
            }

            do {
                try payload.write(to: destinationURL, options: .atomic)
                statusMessage = "Exported to \(destinationURL.lastPathComponent)"
            } catch {
                statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }

        if let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow {
            savePanel.beginSheetModal(for: targetWindow, completionHandler: completion)
        } else {
            savePanel.begin(completionHandler: completion)
        }
    }
    #endif

    // MARK: - Cached State Helpers

    /// Rebuilds all expensive derived state from the current sessions and range.
    /// Called once on appear and again only when `selectedRange` or session count changes.
    private func rebuildCachedState() {
        let startDate = selectedRange.startDate(from: .now)
        let sessions = allSessions
        let filtered = sessions.filter { session in
            guard let startDate else { return true }
            return session.date >= startDate
        }
        cachedFilteredSessions = filtered

        // Session history entries (latest 24)
        cachedHistoryEntries = Array(filtered.reversed().prefix(24)).map { session in
            AdaptiveSessionHistoryEntry(session: session)
        }

        // Activity cells (370+ days of calendar data)
        rebuildActivityCells()

        // Keyboard-ordered keys
        rebuildKeyboardKeys()

        // Task input (triggers the .task(id:) profile build)
        let newInput = AdaptiveAnalysisTaskInput(
            sessions: filtered,
            language: appState.language,
            settings: appState.settings
        )
        if newInput != cachedAnalysisTaskInput {
            cachedAnalysisTaskInput = newInput
        }

        rebuildChartState()
    }

    private func rebuildChartState() {
        let startDate = selectedProgressRange.startDate(from: .now)
        let filtered = cachedFilteredSessions.filter { session in
            guard let startDate else { return true }
            return session.date >= startDate
        }
        cachedChartSessions = filtered
        cachedSmoothedPoints = AdaptiveSmoothedMetricPoint.build(from: filtered, smoothness: progressSmoothness)
    }

    private func rebuildActivityCells() {
        let today = profileCalendar.startOfDay(for: .now)
        let weekday = profileCalendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        guard let currentWeekStart = profileCalendar.date(byAdding: .day, value: -daysFromMonday, to: today),
              let start = profileCalendar.date(byAdding: .day, value: -(52 * 7), to: currentWeekStart) else {
            cachedActivityCells = []
            cachedActivityWeeks = []
            cachedMaxActivityCount = 1
            return
        }

        let counts = Dictionary(
            grouping: allLearningSessions.map { profileCalendar.startOfDay(for: $0.date) },
            by: { $0 }
        ).mapValues(\.count)

        let cells = stride(from: 0, through: 370, by: 1).compactMap { offset -> AdaptiveActivityCell? in
            guard let date = profileCalendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let day = profileCalendar.startOfDay(for: date)
            return AdaptiveActivityCell(
                date: day,
                count: counts[day, default: 0],
                isToday: profileCalendar.isDateInToday(day)
            )
        }

        cachedActivityCells = cells
        cachedActivityWeeks = stride(from: 0, to: cells.count, by: 7).map { index in
            Array(cells[index..<min(index + 7, cells.count)])
        }
        cachedMaxActivityCount = max(1, cells.map(\.count).max() ?? 0)
    }

    private func rebuildKeyboardKeys() {
        let order = appState.settings.keyboardLayout.rows
            .flatMap { $0 }
            .filter { $0.range(of: "[a-z]", options: .regularExpression) != nil }
        let orderIndex = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })

        cachedKeyboardKeys = analysis.allKeys.sorted { lhs, rhs in
            let leftIndex = orderIndex[lhs.key] ?? Int.max
            let rightIndex = orderIndex[rhs.key] ?? Int.max
            if leftIndex == rightIndex {
                return lhs.key < rhs.key
            }
            return leftIndex < rightIndex
        }
    }
}

private struct AdaptiveAnalysisTaskInput: Equatable {
    var sessions: [TrainingProfileSession]
    var language: Language
    var settings: AppSettings
}

private struct AdaptiveSessionHistoryEntry: Identifiable {
    let session: TrainingProfileSession

    var id: String {
        session.id
    }
}

private struct FlowKeyCaps: View {
    @Environment(\.ds) private var ds
    let keys: [String]
    let focusedKey: String?
    private let focusedTint = Color(red: 1.0, green: 0.79, blue: 0.18)

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: Spacing.xs)], spacing: Spacing.xs) {
            ForEach(keys, id: \.self) { key in
                let isFocused = focusedKey == key
                Text(key.uppercased())
                    .font(Typo.caption)
                    .foregroundStyle(isFocused ? ds.background : ds.primaryText)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous)
                            .fill(isFocused ? focusedTint : ds.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous)
                            .stroke(isFocused ? focusedTint.opacity(0.7) : ds.borderSubtle, lineWidth: 1)
                    )
            }
        }
    }
}

private struct KeyboardHeatmapRow: View {
    @Environment(\.ds) private var ds
    let keys: [String]
    let intensity: [String: Double]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { key in
                let value = intensity[key, default: 0]
                Text(key.uppercased())
                    .font(Typo.body)
                    .foregroundStyle(value > 0.48 ? ds.primaryText : ds.secondaryText)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous)
                            .fill(color(for: value))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous)
                            .stroke(ds.border, lineWidth: 1)
                    )
            }
        }
    }

    private func color(for value: Double) -> Color {
        if value > 0.95 { return ds.error.opacity(0.82) }
        if value > 0.72 { return ds.accent.opacity(0.78) }
        if value > 0.48 { return ds.warning.opacity(0.72) }
        if value > 0.24 { return ds.success.opacity(0.58) }
        return ds.surfaceElevated
    }
}

private enum AdaptiveAnalyticsRange: String, CaseIterable, Identifiable {
    case day
    case month
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "Day"
        case .month: return "Month"
        case .all: return "All"
        }
    }

    func startDate(from now: Date) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .day:
            return calendar.date(byAdding: .day, value: -1, to: now)
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: now)
        case .all:
            return nil
        }
    }
}

private struct AdaptiveTrendPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let readiness: Double
    let alphabetCoverage: Double
    let activeAlphabetCount: Int
    let focusedKey: String?
}

private struct AdaptiveSmoothedMetricPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let wpm: Double
    let accuracy: Double

    static func build(from sessions: [TrainingProfileSession], smoothness: Double) -> [AdaptiveSmoothedMetricPoint] {
        guard !sessions.isEmpty else { return [] }
        let clamped = max(0, min(0.9, smoothness))
        let alpha = max(0.05, 1 - clamped)

        var smoothedWPM = sessions[0].wpm
        var smoothedAccuracy = sessions[0].accuracy

        return sessions.map { session in
            smoothedWPM += (session.wpm - smoothedWPM) * alpha
            smoothedAccuracy += (session.accuracy - smoothedAccuracy) * alpha
            return AdaptiveSmoothedMetricPoint(
                date: session.date,
                wpm: smoothedWPM,
                accuracy: smoothedAccuracy
            )
        }
    }
}

private enum AdaptiveSummaryTone {
    case primary
    case accent
    case success
}

private struct AdaptiveSummaryMetric: Identifiable {
    var id: String { "\(label)|\(value)" }
    let label: String
    let value: String
    let tone: AdaptiveSummaryTone
}

private struct AdaptiveSummarySnapshot: Identifiable {
    var id: String { title }
    let title: String
    let subtitle: String
    let metrics: [AdaptiveSummaryMetric]
}

private struct AdaptiveActivityCell: Identifiable {
    var id: Date { date }
    let date: Date
    let count: Int
    let isToday: Bool
}

private struct AdaptiveAccuracyStreak: Identifiable {
    var id: Double { threshold }

    let threshold: Double
    let lessons: Int
    let bestWPM: Double
    let averageAccuracy: Double
    let startDate: Date?
    let endDate: Date?

    static func build(from sessions: [TrainingProfileSession]) -> [AdaptiveAccuracyStreak] {
        [1.0, 0.98, 0.95].map { threshold in
            longestStreak(for: threshold, in: sessions)
        }
    }

    private static func longestStreak(for threshold: Double, in sessions: [TrainingProfileSession]) -> AdaptiveAccuracyStreak {
        let requiredAccuracy = threshold * 100
        var bestSlice: ArraySlice<TrainingProfileSession> = []
        var currentStart: Int?

        for (index, session) in sessions.enumerated() {
            if session.accuracy >= requiredAccuracy {
                if currentStart == nil {
                    currentStart = index
                }
            } else if let start = currentStart {
                let slice = sessions[start..<index]
                if slice.count > bestSlice.count {
                    bestSlice = slice
                }
                currentStart = nil
            }
        }

        if let start = currentStart {
            let slice = sessions[start..<sessions.count]
            if slice.count > bestSlice.count {
                bestSlice = slice
            }
        }

        let bestWPM = bestSlice.map(\.wpm).max() ?? 0
        let averageAccuracy = bestSlice.isEmpty
            ? 0
            : bestSlice.map(\.accuracy).reduce(0, +) / Double(bestSlice.count)

        return AdaptiveAccuracyStreak(
            threshold: threshold,
            lessons: bestSlice.count,
            bestWPM: bestWPM,
            averageAccuracy: averageAccuracy / 100,
            startDate: bestSlice.first?.date,
            endDate: bestSlice.last?.date
        )
    }
}
