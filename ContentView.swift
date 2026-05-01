import SwiftUI

struct ContentView: View {
    @Bindable var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var controlsVisible = true
    @State private var isSettingsHovered = false
    @State private var isRestartHovered = false
    @State private var restartSpinAngle = 0.0
    @State private var controlsRestoreTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TypingView(appState: appState)
                .preferredColorScheme(appState.theme.colorScheme())

            if !appState.isShowingResults {
                HStack(spacing: Spacing.sm) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.45)) {
                            restartSpinAngle += 360
                        }
                        appState.shouldRestart = true
                    } label: {
                        DockIconButton(
                            systemImage: "arrow.clockwise",
                            rotationDegrees: restartSpinAngle,
                            isActiveAppearance: isRestartHovered
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Restart Session")
                    .onHover { hovering in
                        isRestartHovered = hovering
                    }

                    Button {
                        openSettings()
                    } label: {
                        DockIconButton(
                            systemImage: "slider.horizontal.3",
                            isActiveAppearance: isSettingsHovered
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Open Settings")
                    .onHover { hovering in
                        isSettingsHovered = hovering
                    }
                }
                .padding(Spacing.md)
                .opacity(controlsVisible && !appState.isFocusMode ? 1 : 0)
                .animation(Motion.hover, value: controlsVisible)
                .animation(Motion.structural, value: appState.isFocusMode)
                .animation(Motion.structural, value: isSettingsHovered)
            }
        }
        .contentShape(Rectangle())
        .onChange(of: appState.practiceChangeTick, initial: false) { _, _ in
            controlsRestoreTask?.cancel()
            isSettingsHovered = false
            isRestartHovered = false
            withAnimation(Motion.press) {
                controlsVisible = false
            }
            controlsRestoreTask = Task {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(Motion.structural) {
                        controlsVisible = true
                    }
                }
            }
        }
        .onDisappear {
            controlsRestoreTask?.cancel()
        }
    }
}

private struct DockIconButton: View {
    @Environment(\.ds) private var ds
    @State private var isHovered = false

    let systemImage: String
    var rotationDegrees: Double = 0
    var isAccent = false
    var isActiveAppearance = false
    var tracksLocalHover = true
    var iconSize: CGFloat = 16
    var frameSize: CGFloat = 34

    private var showsHoverChrome: Bool {
        (tracksLocalHover && isHovered) || isActiveAppearance
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: iconSize, weight: .medium))
            .foregroundStyle(isAccent ? ds.accent : ds.primaryText)
            .rotationEffect(.degrees(rotationDegrees))
            .frame(width: frameSize, height: frameSize)
            .background(
                ZStack {
                    if showsHoverChrome {
                        GlassPanelBackground(cornerRadius: CornerRadius.medium)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
            .shadow(color: showsHoverChrome ? ds.shadowColor.opacity(0.34) : .clear, radius: 12, y: 5)
            .scaleEffect(showsHoverChrome ? 1.05 : 1)
            .onHover { hovering in
                guard tracksLocalHover else { return }
                isHovered = hovering
            }
            .animation(Motion.hover, value: showsHoverChrome)
    }
}

struct GlassPanelBackground: View {
    @Environment(\.ds) private var ds

    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular.tint(.white.opacity(0.08)).interactive(), in: .rect(cornerRadius: cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(ds.border.opacity(0.68), lineWidth: 0.8)
                    )
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(ds.border.opacity(0.9), lineWidth: 1)
                    )
            }
        }
    }
}

struct SubtleMessageBackground: View {
    @Environment(\.ds) private var ds
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                colorScheme == .dark
                    ? Color.black.opacity(0.16)
                    : Color.white.opacity(0.16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ds.border.opacity(0.78), lineWidth: 0.9)
            )
            .shadow(color: ds.shadowColor.opacity(0.12), radius: 8, y: 3)
    }
}
