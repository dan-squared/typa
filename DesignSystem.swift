import SwiftUI

// MARK: - Spacing Scale

enum Spacing {
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Corner Radii

enum CornerRadius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 10
    static let large: CGFloat = 16
}

// MARK: - Semantic Colors

struct DesignColors {
    let colorScheme: ColorScheme

    // Backgrounds
    var background: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.08, blue: 0.09)
            : Color(red: 0.96, green: 0.96, blue: 0.97)
    }

    var surface: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.black.opacity(0.08)
    }

    var surfaceElevated: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.12)
    }

    // Text
    var primaryText: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.96)
            : Color.black.opacity(0.88)
    }

    var secondaryText: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.72)
            : Color.black.opacity(0.66)
    }

    var tertiaryText: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.52)
            : Color.black.opacity(0.50)
    }

    // Semantic
    var accent: Color {
        .accentColor
    }

    var success: Color {
        Color(red: 0.30, green: 0.78, blue: 0.48)
    }

    var warning: Color {
        colorScheme == .dark
            ? Color(red: 0.52, green: 0.72, blue: 1.0)
            : Color(red: 0.20, green: 0.45, blue: 0.82)
    }

    var error: Color {
        Color(red: 0.88, green: 0.30, blue: 0.28)
    }

    // Borders & Separators
    var border: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.14)
    }

    var borderSubtle: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.08)
    }

    // Card
    var cardFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.04)
    }

    var cardBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.08)
    }

    // Tooltip
    var tooltipFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.10)
    }

    // Shadows
    var shadowColor: Color {
        Color.black.opacity(colorScheme == .dark ? 0.16 : 0.06)
    }

    // Noise overlay tuning
    var noiseOverlayOpacity: Double {
        colorScheme == .dark ? 0.42 : 0.34
    }

#if os(macOS)
    var windowMaterial: NSVisualEffectView.Material {
        colorScheme == .dark ? .hudWindow : .headerView
    }
#endif
}

// MARK: - Environment Key

private struct DesignColorsKey: EnvironmentKey {
    static let defaultValue = DesignColors(colorScheme: .dark)
}

extension EnvironmentValues {
    var ds: DesignColors {
        get { self[DesignColorsKey.self] }
        set { self[DesignColorsKey.self] = newValue }
    }
}

// MARK: - View Modifier to inject design colors

struct DesignSystemModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .environment(\.ds, DesignColors(colorScheme: colorScheme))
    }
}

extension View {
    func withDesignSystem() -> some View {
        modifier(DesignSystemModifier())
    }
}

// MARK: - Typography

enum Typo {
    /// Hero metrics on results screen (WPM)
    static let displayLarge = Font.system(size: 48, weight: .bold, design: .monospaced)

    /// Secondary metrics (accuracy)
    static let displayMedium = Font.system(size: 34, weight: .semibold, design: .monospaced)

    /// Mini metrics (consistency, time, etc.)
    static let displaySmall = Font.system(size: 24, weight: .semibold, design: .monospaced)

    /// Metric labels
    static let label = Font.system(size: 12, weight: .medium, design: .monospaced)

    /// Body text for controls, help text
    static let body = Font.system(size: 13, weight: .regular, design: .default)

    /// Small captions
    static let caption = Font.system(size: 11, weight: .regular, design: .monospaced)

    /// Live stats badge values
    static let badgeValue = Font.system(size: 14, weight: .thin, design: .monospaced)

    /// Live stats badge labels
    static let badgeLabel = Font.system(size: 12, weight: .regular, design: .monospaced)

    /// Chart tooltip
    static let tooltip = Font.system(size: 12, weight: .regular, design: .monospaced)

    /// Analytics header
    static let sectionHeader = Font.system(size: 34, weight: .bold, design: .monospaced)
}

// MARK: - Animation Curves

enum Motion {
    /// Hover states: fast, subtle
    static let hover = Animation.easeOut(duration: 0.15)

    /// Structural layout changes (show/hide panels, viewport scroll)
    static let structural = Animation.spring(response: 0.28, dampingFraction: 0.86)

    /// Entrance animations (fade in, scale up)
    static let entrance = Animation.spring(response: 0.36, dampingFraction: 0.82)

    /// Caret movement
    static let caret = Animation.interactiveSpring(response: 0.18, dampingFraction: 0.82, blendDuration: 0.06)

    /// Count-up number animation
    static let countUp = Animation.easeOut(duration: 0.5)

    /// Quick press feedback
    static let press = Animation.easeOut(duration: 0.12)

    /// Viewport scroll (restrained spring)
    static let viewportScroll = Animation.spring(response: 0.32, dampingFraction: 0.92)

    /// Stagger delay between sequential items
    static func stagger(index: Int, base: Double = 0.06) -> Animation {
        entrance.delay(Double(index) * base)
    }
}

// MARK: - Shared Card Background

struct DSCardBackground: View {
    @Environment(\.ds) private var ds

    var body: some View {
        RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
            .fill(ds.cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                    .stroke(ds.cardBorder, lineWidth: 1)
            )
    }
}

// MARK: - Shared Glass Card

struct DSGlassCard: View {
    @Environment(\.ds) private var ds
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
            .fill(
                colorScheme == .dark
                    ? Color.white.opacity(0.04)
                    : Color.white.opacity(0.55)
            )
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                    .stroke(ds.borderSubtle, lineWidth: 0.8)
            )
            .shadow(color: ds.shadowColor, radius: 6, y: 2)
    }
}

// MARK: - Transparent Card (minimal)

struct DSTransparentCard: View {
    @Environment(\.ds) private var ds
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
            .fill(
                colorScheme == .dark
                    ? Color.white.opacity(0.03)
                    : Color.black.opacity(0.02)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.large, style: .continuous)
                    .stroke(ds.borderSubtle, lineWidth: 0.6)
            )
    }
}

// MARK: - Hit Area Modifier

struct MinHitArea: ViewModifier {
    let size: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }
}

extension View {
    func minHitArea(_ size: CGFloat = 44) -> some View {
        modifier(MinHitArea(size: size))
    }
}

// MARK: - Animated Count-Up Number

struct AnimatedNumber: View {
    let value: Int
    let font: Font
    let suffix: String

    @State private var displayValue: Double = 0
    @State private var animationTask: Task<Void, Never>?

    init(_ value: Int, font: Font = Typo.displayMedium, suffix: String = "") {
        self.value = value
        self.font = font
        self.suffix = suffix
    }

    var body: some View {
        Text("\(Int(displayValue))\(suffix)")
            .font(font)
            .monospacedDigit()
            .onAppear {
                animateCountUp()
            }
            .onChange(of: value) { _, newValue in
                animateCountUp(to: newValue)
            }
            .onDisappear {
                animationTask?.cancel()
                animationTask = nil
            }
    }

    private func animateCountUp(to target: Int? = nil) {
        let targetValue = Double(target ?? value)
        let startingValue = displayValue
        animationTask?.cancel()

        let duration: Double = 0.5
        let steps = 30
        let stepDurationNanoseconds = UInt64((duration / Double(steps)) * 1_000_000_000)

        animationTask = Task { @MainActor in
            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let progress = Double(step) / Double(steps)
                let eased = 1 - pow(1 - progress, 3)
                displayValue = startingValue + ((targetValue - startingValue) * eased)

                if step < steps {
                    try? await Task.sleep(nanoseconds: stepDurationNanoseconds)
                }
            }

            if !Task.isCancelled {
                displayValue = targetValue
            }
        }
    }
}
