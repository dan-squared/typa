import SwiftUI

struct FloatingStatsBadge: View {
    @Environment(\.ds) private var ds

    static let baseWidth: CGFloat = 468
    static let baseHeight: CGFloat = 50

    var wpm: Int
    var accuracy: Int
    var chars: Int
    var timeSeconds: Int
    var timeValueColor: Color
    var cascadeTick: Int
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: Spacing.md) {
            StatItem(icon: "timer", label: "WPM", value: "\(wpm)", suffix: nil, cascadeTick: cascadeTick, cascadeIndex: 0)
            Divider().frame(height: Spacing.sm)
            StatItem(icon: "checkmark.circle", label: "Acc", value: "\(accuracy)", suffix: "%", cascadeTick: cascadeTick, cascadeIndex: 1)
            Divider().frame(height: Spacing.sm)
            StatItem(icon: "textformat", label: "chars", value: "\(chars)", suffix: nil, cascadeTick: cascadeTick, cascadeIndex: 2)
            Divider().frame(height: Spacing.sm)
            StatItem(
                icon: "clock",
                label: "time",
                value: "\(timeSeconds)",
                suffix: "s",
                valueColor: timeValueColor,
                cascadeTick: cascadeTick,
                cascadeIndex: 3
            )
        }
        .padding(.horizontal, Spacing.md + Spacing.xxxs)
        .padding(.vertical, Spacing.sm)
        .frame(width: Self.baseWidth, height: Self.baseHeight)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                    .fill(ds.surface)

                RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.03),
                                Color.black.opacity(0.10)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.softLight)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                .stroke(ds.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
        .shadow(color: ds.shadowColor, radius: 10, y: 4)
        .compositingGroup()
        .scaleEffect(scale, anchor: .center)
    }
}

struct StatItem: View {
    let icon: String
    let label: String
    let value: String
    let suffix: String?
    let valueColor: Color
    let cascadeTick: Int
    let cascadeIndex: Int

    init(
        icon: String,
        label: String,
        value: String,
        suffix: String?,
        valueColor: Color = .primary,
        cascadeTick: Int,
        cascadeIndex: Int
    ) {
        self.icon = icon
        self.label = label
        self.value = value
        self.suffix = suffix
        self.valueColor = valueColor
        self.cascadeTick = cascadeTick
        self.cascadeIndex = cascadeIndex
    }

    var body: some View {
        HStack(spacing: Spacing.sm / 2) {
            Image(systemName: icon)
                .font(Typo.badgeLabel)
                .foregroundColor(.secondary)
                .baselineOffset(0.5)

            FlipNumberText(value: value, foregroundColor: valueColor)
            if let suffix {
                Text(suffix)
                    .font(Typo.body)
                    .foregroundColor(valueColor)
                    .baselineOffset(0.6)
            }

            TypingCascadeLabel(label: label, cascadeTick: cascadeTick, cascadeIndex: cascadeIndex)
        }
    }
}

struct FlipNumberText: View {
    let value: String
    let foregroundColor: Color

    @State private var previousChars: [Character] = []
    @State private var currentChars: [Character] = []
    @State private var changeTick = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<max(currentChars.count, previousChars.count), id: \.self) { index in
                let oldChar = char(at: index, from: previousChars)
                let newChar = char(at: index, from: currentChars)
                FlipDigitCell(
                    oldChar: oldChar,
                    newChar: newChar,
                    foregroundColor: foregroundColor,
                    changeTick: changeTick
                )
            }
        }
        .onAppear {
            let chars = Array(value)
            previousChars = chars
            currentChars = chars
        }
        .onChange(of: value, initial: false) { _, newValue in
            let newChars = Array(newValue)
            guard newChars != currentChars else { return }
            previousChars = currentChars
            currentChars = newChars
            changeTick += 1
        }
    }

    private func char(at index: Int, from array: [Character]) -> Character {
        guard index < array.count else { return " " }
        return array[index]
    }
}

private struct FlipDigitCell: View {
    let oldChar: Character
    let newChar: Character
    let foregroundColor: Color
    let changeTick: Int

    @State private var progress: Double = 1

    private var shouldFlip: Bool {
        oldChar != newChar && oldChar.isNumber && newChar.isNumber
    }

    var body: some View {
        ZStack {
            Text(String(oldChar))
                .font(Typo.badgeValue)
                .foregroundColor(foregroundColor.opacity(shouldFlip ? (1 - progress) : 0))
                .rotation3DEffect(.degrees(90 * progress), axis: (x: 1, y: 0, z: 0), perspective: 0.6)

            Text(String(newChar))
                .font(Typo.badgeValue)
                .foregroundColor(foregroundColor)
                .rotation3DEffect(.degrees(-90 * (1 - progress)), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .opacity(shouldFlip ? progress : 1)
        }
        .frame(minWidth: Spacing.xs)
        .monospacedDigit()
        .onAppear {
            progress = 1
        }
        .onChange(of: changeTick, initial: false) { _, _ in
            guard shouldFlip else {
                progress = 1
                return
            }
            progress = 0
            withAnimation(.easeInOut(duration: 0.20)) {
                progress = 1
            }
        }
    }
}

private struct TypingCascadeLabel: View {
    let label: String
    let cascadeTick: Int
    let cascadeIndex: Int

    @State private var charStates: [CGFloat] = []
    @State private var cascadeTasks: [Task<Void, Never>] = []

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(label.enumerated()), id: \.offset) { idx, ch in
                Text(String(ch))
                    .font(Typo.badgeLabel)
                    .foregroundColor(.secondary)
                    .opacity(charStates.indices.contains(idx) ? charStates[idx] : 1)
                    .offset(y: charStates.indices.contains(idx) ? (1 - charStates[idx]) * -8 : 0)
            }
        }
        .onAppear {
            charStates = Array(repeating: 1, count: label.count)
        }
        .onChange(of: cascadeTick, initial: false) { _, _ in
            cancelCascadeTasks()
            if charStates.count != label.count {
                charStates = Array(repeating: 1, count: label.count)
            }
            for index in 0..<label.count {
                let delay = (Double(cascadeIndex) * 0.045) + (Double(index) * 0.018)
                let task = Task {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard charStates.indices.contains(index) else { return }
                        charStates[index] = 0
                        withAnimation(Motion.press) {
                            charStates[index] = 1
                        }
                    }
                }
                cascadeTasks.append(task)
            }
        }
        .onDisappear {
            cancelCascadeTasks()
        }
    }

    private func cancelCascadeTasks() {
        cascadeTasks.forEach { $0.cancel() }
        cascadeTasks.removeAll()
    }
}
