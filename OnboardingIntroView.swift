import SwiftUI
import AppKit

struct OnboardingIntroView: View {
    let onWindowReveal: () -> Void
    let onBeginFinish: () -> Void
    let onFinish: () -> Void

    @Environment(\.ds) private var ds
    @Environment(\.colorScheme) private var colorScheme
    @State private var step = 0
    @State private var hasAppeared = false
    @State private var transitionDirection: CGFloat = 1
    @State private var isFinishing = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            illustration: .welcome,
            eyebrow: "Welcome",
            title: "Find Your Flow",
            body: "A calmer typing trainer designed to keep practice focused, clean, and easy to return to."
        ),
        OnboardingPage(
            illustration: .adaptive,
            eyebrow: "Adaptive",
            title: "Train What Slows You Down",
            body: "Adaptive lessons watch your live accuracy and target the keys and patterns that need more reps."
        ),
        OnboardingPage(
            illustration: .modes,
            eyebrow: "Practice Modes",
            title: "Practice, Then Push",
            body: "Build confidence in Learning mode, then switch into focused tests when you want a cleaner read on speed."
        ),
        OnboardingPage(
            illustration: .finished,
            eyebrow: "Start",
            title: "Ready When You Are",
            body: "Your profile, settings, and history stay local on your Mac. Step in and start typing."
        )
    ]

    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()

            // Centered floating card
            onboardingCard
                .frame(width: 392)
                .padding(.vertical, 24)
                .padding(.horizontal, 12)
                .opacity(cardOpacity)
                .scaleEffect(cardScale)
                .offset(y: cardOffsetY)
                .blur(radius: isFinishing ? 6 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.86), value: hasAppeared)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: isFinishing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            onWindowReveal()
            guard !hasAppeared else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Card

    private var onboardingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 48)

            // Icon Area
            HStack {
                Spacer()
                ZStack {
                    illustrationView(for: pages[step].illustration)
                        .id("illust-\(step)")
                        .zIndex(Double(step))
                        .transition(illustrationTransition)
                }
                .animation(.easeInOut(duration: 0.4), value: step)
                Spacer()
            }

            Spacer().frame(height: 36)

            // Content Area
            ZStack(alignment: .topLeading) {
                pageTextContent(for: pages[step])
                    .id("text-\(step)")
                    .zIndex(Double(step))
                    .transition(textTransition)
            }
            .frame(minHeight: 160, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.4), value: step)

            Spacer().frame(height: 36)

            // Footer
            HStack(alignment: .center, spacing: 0) {
                Button {
                    advance()
                } label: {
                    HStack(spacing: 4) {
                        Text(step == pages.count - 1 ? "Start" : "Continue")
                        if step < pages.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(isFinishing)

                Spacer()

                stepDots
            }
        }
        .frame(minHeight: 480)
        .padding(.horizontal, 34)
        .padding(.vertical, 32)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.06),
            radius: 30, y: 10
        )
    }

    // MARK: - Text Content

    private func pageTextContent(for page: OnboardingPage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(page.eyebrow)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(ds.accent.opacity(colorScheme == .dark ? 0.92 : 0.84))

            Text(page.title)
                .font(onboardingTitleFont)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(page.body)
                .font(onboardingBodyFont)
                .foregroundStyle(secondaryText)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Transitions

    private var textTransition: AnyTransition {
        .opacity
    }

    private var illustrationTransition: AnyTransition {
        .opacity
    }

    // MARK: - Card Appearance

    private var cardOpacity: Double {
        if isFinishing { return 0 }
        return hasAppeared ? 1 : 0
    }

    private var cardScale: CGFloat {
        if isFinishing { return 0.96 }
        return hasAppeared ? 1 : 0.94
    }

    private var cardOffsetY: CGFloat {
        if isFinishing { return -12 }
        return hasAppeared ? 0 : 16
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(
                colorScheme == .dark
                    ? Color(red: 0.11, green: 0.11, blue: 0.13).opacity(0.65)
                    : Color.white.opacity(0.65)
            )
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(ds.border.opacity(colorScheme == .dark ? 0.72 : 0.86), lineWidth: 0.9)
            )
            .overlay(alignment: .top) {
                cardGradient(for: step)
                    .frame(height: 320)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.95), location: 0),
                                .init(color: .white.opacity(0), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(
                        UnevenRoundedRectangle(
                            topLeadingRadius: 32,
                            bottomLeadingRadius: 0,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 32,
                            style: .continuous
                        )
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.18 : 0.55),
                                .white.opacity(0.04)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 0.8
                    )
            )
    }

    // MARK: - Gradient Fills

    private func cardGradient(for step: Int) -> some View {
        let gradients: [LinearGradient] = [
            // Welcome: light purple to light blue
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.5, green: 0.35, blue: 0.7).opacity(0.75),
                       Color(red: 0.3, green: 0.5, blue: 0.8).opacity(0.55)]
                    : [Color(red: 0.75, green: 0.85, blue: 1.0),
                       Color(red: 0.9, green: 0.75, blue: 1.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            // Adaptive: light green to light cyan
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.25, green: 0.6, blue: 0.45).opacity(0.75),
                       Color(red: 0.2, green: 0.5, blue: 0.7).opacity(0.55)]
                    : [Color(red: 0.7, green: 0.95, blue: 0.85),
                       Color(red: 0.75, green: 0.9, blue: 1.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            // Modes: yellow to orange
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.7, green: 0.45, blue: 0.2).opacity(0.75),
                       Color(red: 0.7, green: 0.35, blue: 0.4).opacity(0.55)]
                    : [Color(red: 1.0, green: 0.85, blue: 0.6),
                       Color(red: 1.0, green: 0.8, blue: 0.75)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            // Finished: blue to purple
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.35, green: 0.45, blue: 0.8).opacity(0.75),
                       Color(red: 0.5, green: 0.35, blue: 0.7).opacity(0.55)]
                    : [Color(red: 0.75, green: 0.85, blue: 1.0),
                       Color(red: 0.85, green: 0.75, blue: 1.0)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        ]

        return ZStack {
            gradients[step]
                .animation(.easeInOut(duration: 0.6), value: step)
        }
    }

    // MARK: - Illustrations

    @ViewBuilder
    private func illustrationView(for illustration: OnboardingPage.Illustration) -> some View {
        switch illustration {
        case .welcome:
            ZStack {
                squircle(width: 92)
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(iconColor)
            }
        case .adaptive:
            ZStack {
                squircle(width: 92)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
        case .modes:
            ZStack {
                squircle(width: 92)
                Image(systemName: "flag.checkered")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(iconColor)
            }
        case .finished:
            ZStack {
                squircle(width: 92)
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(iconColor)
            }
        }
    }

    private func squircle(width: CGFloat, height: CGFloat? = nil) -> some View {
        RoundedRectangle(cornerRadius: width * 0.26, style: .continuous)
            .fill(
                colorScheme == .dark
                    ? Color(white: 0.18)
                    : Color.white
            )
            .frame(width: width, height: height ?? width)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.06), radius: 12, y: 4)
    }

    private var iconColor: Color {
        colorScheme == .dark ? .white : Color(white: 0.2)
    }

    // MARK: - Step Dots

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == step ? Color(red: 0.3, green: 0.6, blue: 1.0) : Color.gray.opacity(0.2))
                    .frame(width: index == step ? 16 : 4, height: 4)
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: step)
            }
        }
    }

    // MARK: - Colors

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black.opacity(0.88)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.52)
    }

    private var onboardingTitleFont: Font {
        .system(size: 29, weight: .semibold)
    }

    private var onboardingBodyFont: Font {
        .system(size: 14, weight: .regular)
    }

    // MARK: - Actions

    private func advance() {
        guard !isFinishing else { return }
        if step < pages.count - 1 {
            transitionDirection = 1
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                step += 1
            }
            return
        }

        onBeginFinish()
        isFinishing = true
        onFinish()
    }
}

private struct OnboardingPage {
    enum Illustration {
        case welcome
        case adaptive
        case modes
        case finished
    }

    let illustration: Illustration
    let eyebrow: String
    let title: String
    let body: String
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        OnboardingPrimaryButtonView(configuration: configuration)
    }
}

private struct OnboardingPrimaryButtonView: View {
    let configuration: ButtonStyleConfiguration
    
    var body: some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .default))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(red: 0.18, green: 0.55, blue: 0.95))
            )
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.4), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) {
                if configuration.isPressed {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
    }
}
