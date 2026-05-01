#if os(macOS)
import SwiftUI
import AppKit

enum WindowChromePhase: Equatable {
    case immersive
    case standard
}

struct WindowAccessor: NSViewRepresentable {
    var phase: WindowChromePhase
    private let immersiveCornerRadius: CGFloat = 26
    var minimumWindowSize = NSSize(width: 860, height: 620)

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = TrackingWindowView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.onWindowAvailable = { window in
            apply(phase: phase, to: window, coordinator: context.coordinator, animated: false)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            apply(phase: phase, to: window, coordinator: context.coordinator, animated: true)
        }
    }

    @MainActor
    private func apply(
        phase: WindowChromePhase,
        to window: NSWindow,
        coordinator: Coordinator,
        animated: Bool
    ) {
        let phaseChanged = coordinator.lastAppliedPhase != phase
        let minimumWindowSizeChanged = coordinator.lastAppliedMinimumWindowSize != minimumWindowSize

        window.minSize = minimumWindowSize
        window.contentMinSize = minimumWindowSize
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]

        switch phase {
        case .immersive:
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            setSuperviewBackgroundColor(.clear, for: window)
            applyCornerMask(to: window, radius: immersiveCornerRadius, masksToBounds: true, phase: phase)
            if phaseChanged {
                updateButtonVisibility(for: window, hidden: true, animated: animated)
            }

        case .standard:
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.isMovableByWindowBackground = true
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            setSuperviewBackgroundColor(.clear, for: window)
            applyCornerMask(to: window, radius: 0, masksToBounds: false, phase: phase)
            if phaseChanged {
                updateButtonVisibility(for: window, hidden: false, animated: animated)
            }
        }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = nil
        if #available(macOS 11.0, *) {
            window.titlebarSeparatorStyle = .none
        }

        clearWindowBackgroundHierarchy(for: window)
        DispatchQueue.main.async {
            window.titlebarAppearsTransparent = true
            clearWindowBackgroundHierarchy(for: window)
            setSuperviewBackgroundColor(.clear, for: window)
        }

        if phaseChanged || minimumWindowSizeChanged {
            updateWindowSize(for: window, animated: animated && !phaseChanged)
        }

        if animated && phaseChanged {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.65
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().alphaValue = 1
                window.invalidateShadow()
            }
        } else {
            window.alphaValue = 1
            window.invalidateShadow()
        }

        coordinator.lastAppliedPhase = phase
        coordinator.lastAppliedMinimumWindowSize = minimumWindowSize
    }

    private func setSuperviewBackgroundColor(_ color: NSColor, for window: NSWindow) {
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = color.cgColor
        if let superview = window.contentView?.superview {
            superview.wantsLayer = true
            superview.layer?.backgroundColor = color.cgColor
        }
    }

    private func applyCornerMask(to window: NSWindow, radius: CGFloat, masksToBounds: Bool, phase: WindowChromePhase) {
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = radius
        window.contentView?.layer?.cornerCurve = .continuous
        window.contentView?.layer?.masksToBounds = masksToBounds

        if let superview = window.contentView?.superview {
            superview.wantsLayer = true
            superview.layer?.cornerRadius = radius
            superview.layer?.cornerCurve = .continuous
            superview.layer?.masksToBounds = masksToBounds
            
            if phase == .immersive {
                let maskLayer = CALayer()
                maskLayer.backgroundColor = NSColor.black.cgColor
                maskLayer.frame = superview.bounds.insetBy(dx: 1, dy: 1)
                maskLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                maskLayer.cornerRadius = radius
                maskLayer.cornerCurve = .continuous
                superview.layer?.mask = maskLayer
            } else {
                superview.layer?.mask = nil
            }
        }
    }

    private func updateButtonVisibility(for window: NSWindow, hidden: Bool, animated: Bool) {
        let buttons = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ]

        positionTrafficLightButtons(for: window)

        for button in buttons {
            guard let button else { continue }
            button.isHidden = false
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.4
                    button.animator().alphaValue = hidden ? 0 : 1
                } completionHandler: {
                    button.isHidden = hidden
                }
            } else {
                button.alphaValue = hidden ? 0 : 1
                button.isHidden = hidden
            }
        }
    }

    private func positionTrafficLightButtons(for window: NSWindow) {
        let buttons = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ].compactMap { $0 }

        guard !buttons.isEmpty else { return }

        let leadingInset: CGFloat = 14
        let topInset: CGFloat = 10
        let horizontalSpacing: CGFloat = 8
        var nextX = leadingInset

        for button in buttons {
            var frame = button.frame
            frame.origin.x = nextX
            frame.origin.y = topInset
            button.setFrameOrigin(frame.origin)
            nextX += frame.width + horizontalSpacing
        }
    }

    private func clearWindowBackgroundHierarchy(for window: NSWindow) {
        var viewsToClear: [NSView] = []

        if let frameRoot = window.contentView?.superview {
            viewsToClear.append(frameRoot)
            collectAncestorChain(from: frameRoot, into: &viewsToClear)
            collectSubviewTree(from: frameRoot, into: &viewsToClear)
        }

        for view in viewsToClear {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.layer?.isOpaque = false

            let className = String(describing: type(of: view))
            if className == "NSTitlebarBackgroundView" {
                view.isHidden = true
                view.alphaValue = 0
            }
        }
    }

    private func updateWindowSize(for window: NSWindow, animated: Bool) {
        let targetFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumWindowSize))
        var nextFrame = window.frame
        
        if !animated, let screen = window.screen ?? NSScreen.main {
            let screenRect = screen.visibleFrame
            nextFrame.size = targetFrame.size
            nextFrame.origin.x = screenRect.minX + (screenRect.width - targetFrame.width) / 2
            nextFrame.origin.y = screenRect.minY + (screenRect.height - targetFrame.height) / 2
        } else {
            nextFrame.origin.y += nextFrame.height - targetFrame.height
            nextFrame.size = targetFrame.size
        }
        
        window.setFrame(nextFrame, display: true, animate: animated)
    }

    private func collectAncestorChain(from view: NSView, into views: inout [NSView]) {
        var current = view.superview
        while let unwrappedCurrent = current {
            views.append(unwrappedCurrent)
            current = unwrappedCurrent.superview
        }
    }

    private func collectSubviewTree(from view: NSView, into views: inout [NSView]) {
        for subview in view.subviews {
            views.append(subview)
            collectSubviewTree(from: subview, into: &views)
        }
    }

    final class Coordinator {
        var lastAppliedPhase: WindowChromePhase?
        var lastAppliedMinimumWindowSize: NSSize?
    }

    final class TrackingWindowView: NSView {
        var onWindowAvailable: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindowAvailable?(window)
            }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            if let window {
                onWindowAvailable?(window)
            }
        }
    }
}
#else
import SwiftUI

enum WindowChromePhase: Equatable {
    case immersive
    case standard
}

struct WindowAccessor: View {
    var phase: WindowChromePhase
    var minimumWindowSize = CGSize(width: 860, height: 620)

    var body: some View {
        Color.clear
    }
}
#endif
