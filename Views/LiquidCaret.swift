import SwiftUI

struct LiquidCaret: View {
    var style: CaretStyle
    var color: Color
    var fontSize: Double
    var isPace: Bool = false
    var isBlinking: Bool
    var isIdle: Bool = false
    var allowsContinuousAnimation: Bool = true

    @State private var caretOpacity: Double = 1.0
    @State private var idleScale: CGFloat = 1.0

    private var caretHeight: CGFloat {
        switch style {
        case .bar, .block:
            return CGFloat(max(14, fontSize * 0.98))
        case .underline:
            return CGFloat(max(10, fontSize * 0.72))
        }
    }

    private var caretWidth: CGFloat {
        CGFloat(max(10, fontSize * 0.58))
    }

    var body: some View {
        ZStack {
            if style == .underline {
                Rectangle()
                    .fill(color)
                    .frame(width: caretWidth, height: 3)
                    .offset(y: caretHeight + 1)
            } else if style == .block {
                Rectangle()
                    .fill(color.opacity(0.24))
                    .frame(width: caretWidth, height: caretHeight)
            } else { // Bar
                Rectangle()
                    .fill(color)
                    .frame(width: 2.5, height: caretHeight)
            }
        }
        .shadow(color: color.opacity(0.45), radius: 5, x: 0, y: 0)
        .shadow(color: color.opacity(0.18), radius: 10, x: 0, y: 0)
        .opacity(isPace ? 0.3 : caretOpacity)
        .scaleEffect(y: isIdle ? idleScale : 1.0, anchor: .bottom)
        .onAppear {
            updateAnimation()
        }
        .onChange(of: isBlinking) { _, _ in
            updateAnimation()
        }
        .onChange(of: isIdle) { _, _ in
            updateAnimation()
        }
        .onChange(of: style) { _, _ in
            updateAnimation()
        }
        .onChange(of: allowsContinuousAnimation) { _, _ in
            updateAnimation()
        }
    }

    private func updateAnimation() {
        guard allowsContinuousAnimation else {
            caretOpacity = 1
            idleScale = 1.0
            return
        }

        if isIdle {
            // Breathing pulse for idle state — slow and pronounced
            caretOpacity = 1
            idleScale = 1.0
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                caretOpacity = 0.35
                idleScale = 0.92
            }
        } else if isBlinking {
            idleScale = 1.0
            caretOpacity = 1
            withAnimation(.easeInOut(duration: 0.58).repeatForever(autoreverses: true)) {
                caretOpacity = 0.08
            }
        } else {
            caretOpacity = 1
            idleScale = 1.0
        }
    }
}
