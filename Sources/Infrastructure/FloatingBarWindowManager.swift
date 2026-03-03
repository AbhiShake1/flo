import AppCore
import AppKit
import Foundation
import QuartzCore

@MainActor
public final class FloatingBarWindowManager: NSObject, FloatingBarManaging {
    private enum Metrics {
        static let pillHeight: CGFloat = 42
        static let buttonSize: CGFloat = 26
        static let horizontalPadding: CGFloat = 8
        static let buttonGap: CGFloat = 6
    }

    private enum Symbols {
        static let primary = "waveform"
        static let read = "speaker.wave.2.fill"
    }

    private enum AnimationKeys {
        static let micRipple = "flo.mic.ripple"
    }

    private var panel: NSPanel?
    private var container: NSView?
    private var micButton: NSButton?
    private var readButton: NSButton?
    private var activityIndicator: NSProgressIndicator?

    private var currentState: RecorderState = .idle
    private var actions: FloatingBarActions?
    private var hasSelectedText = false
    private var selectionMonitorTimer: Timer?
    private var latestAudioLevel: Float = 0
    private var listeningRippleLayer: CAShapeLayer?

    public override init() {
        super.init()
    }

    public func setActions(_ actions: FloatingBarActions?) {
        self.actions = actions
        apply(state: currentState)
    }

    public func show(state: RecorderState) {
        let panel = ensurePanel()
        currentState = state
        startSelectionMonitoringIfNeeded()
        apply(state: state)
        positionPanel(panel)
        panel.orderFrontRegardless()
    }

    public func update(state: RecorderState) {
        let panel = ensurePanel()
        currentState = state
        apply(state: state)
        positionPanel(panel)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    public func updateAudioLevel(_ level: Float) {
        let clamped = min(max(level, 0), 1)
        latestAudioLevel = clamped
        guard currentState == .listening else {
            return
        }
        applyListeningVisuals(level: clamped)
    }

    public func hide() {
        selectionMonitorTimer?.invalidate()
        selectionMonitorTimer = nil
        stopListeningAnimation(resetVisuals: true)
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let frame = NSRect(x: 0, y: 0, width: 44, height: Metrics.pillHeight)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false

        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        container.layer?.cornerRadius = Metrics.pillHeight / 2
        container.layer?.masksToBounds = true

        let micButton = makeCircularButton(symbol: Symbols.primary, action: #selector(handleMicTap))
        let readButton = makeCircularButton(symbol: Symbols.read, action: #selector(handleReadTap))
        let activityIndicator = NSProgressIndicator(frame: .zero)
        activityIndicator.style = .spinning
        activityIndicator.controlSize = .small
        activityIndicator.isDisplayedWhenStopped = false

        container.addSubview(micButton)
        container.addSubview(readButton)
        container.addSubview(activityIndicator)
        panel.contentView = container

        self.panel = panel
        self.container = container
        self.micButton = micButton
        self.readButton = readButton
        self.activityIndicator = activityIndicator

        apply(state: .idle)
        return panel
    }

    private func makeCircularButton(symbol: String, action: Selector) -> NSButton {
        let button = NSButton(frame: .zero)
        button.setButtonType(.momentaryChange)
        button.isBordered = false
        button.target = self
        button.action = action
        button.imagePosition = .imageOnly
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        button.contentTintColor = .white
        button.focusRingType = .none
        if let cell = button.cell as? NSButtonCell {
            cell.highlightsBy = []
            cell.showsStateBy = []
        }
        button.wantsLayer = true
        button.layer?.masksToBounds = false
        button.layer?.shadowOffset = .zero
        button.layer?.shadowOpacity = 0
        button.layer?.shadowRadius = 0
        return button
    }

    private func apply(state: RecorderState) {
        guard panel != nil else {
            return
        }

        let canUseActions = actions != nil
        let showRead = shouldShowReadButton(for: state) && canUseActions
        let canCancelRead = state == .speaking
        let readEnabled = canUseActions && showRead && (canCancelRead || !isBusy(state))

        micButton?.isEnabled = canUseActions && !isBusy(state)
        readButton?.isEnabled = readEnabled
        readButton?.isHidden = !showRead

        switch state {
        case .idle:
            stopListeningAnimation(resetVisuals: true)
            micButton?.image = primaryIcon(tint: .white)
            readButton?.image = readIcon(symbol: Symbols.read, tint: .white)
            activityIndicator?.stopAnimation(nil)
        case .listening:
            micButton?.image = primaryIcon(tint: .systemRed)
            startListeningAnimationIfNeeded()
            applyListeningVisuals(level: latestAudioLevel)
            activityIndicator?.stopAnimation(nil)
        case .transcribing, .injecting, .speaking:
            stopListeningAnimation(resetVisuals: true)
            micButton?.image = primaryIcon(tint: .white)
            if case .speaking = state {
                readButton?.image = readIcon(symbol: "xmark.circle.fill", tint: .systemOrange)
            }
            activityIndicator?.startAnimation(nil)
        case .error:
            stopListeningAnimation(resetVisuals: true)
            micButton?.image = primaryIcon(tint: .systemOrange)
            readButton?.image = readIcon(symbol: Symbols.read, tint: .white)
            activityIndicator?.stopAnimation(nil)
        }

        layoutPanel(showReadButton: showRead)
    }

    private func layoutPanel(showReadButton: Bool) {
        guard let panel, let container, let micButton, let readButton, let activityIndicator else {
            return
        }

        let buttonCount: CGFloat = showReadButton ? 2 : 1
        let width =
            Metrics.horizontalPadding * 2 +
            (Metrics.buttonSize * buttonCount) +
            (showReadButton ? Metrics.buttonGap : 0)
        let height = Metrics.pillHeight
        let y = (height - Metrics.buttonSize) / 2

        panel.setContentSize(NSSize(width: width, height: height))
        panel.setFrame(
            NSRect(origin: panel.frame.origin, size: NSSize(width: width, height: height)),
            display: false
        )
        container.frame = NSRect(x: 0, y: 0, width: width, height: height)
        container.layer?.cornerRadius = height / 2

        micButton.frame = NSRect(
            x: Metrics.horizontalPadding,
            y: y,
            width: Metrics.buttonSize,
            height: Metrics.buttonSize
        )

        readButton.frame = NSRect(
            x: Metrics.horizontalPadding + Metrics.buttonSize + Metrics.buttonGap,
            y: y,
            width: Metrics.buttonSize,
            height: Metrics.buttonSize
        )

        let spinnerSize: CGFloat = 13
        activityIndicator.frame = NSRect(
            x: micButton.frame.midX - (spinnerSize / 2),
            y: micButton.frame.midY - (spinnerSize / 2),
            width: spinnerSize,
            height: spinnerSize
        )

        layoutListeningRippleLayer()
        positionPanel(panel)
    }

    private func shouldShowReadButton(for state: RecorderState) -> Bool {
        switch state {
        case .idle, .error:
            return hasSelectedText
        case .speaking:
            return true
        case .listening, .transcribing, .injecting:
            return false
        }
    }

    private func isBusy(_ state: RecorderState) -> Bool {
        switch state {
        case .transcribing, .injecting, .speaking:
            return true
        case .idle, .listening, .error:
            return false
        }
    }

    private func positionPanel(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            return
        }

        let visible = screen.visibleFrame
        let x = visible.midX - (panel.frame.width / 2)
        let y = visible.minY + 18
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    @objc
    private func handleMicTap() {
        actions?.toggleDictation()
    }

    @objc
    private func handleReadTap() {
        DispatchQueue.main.async { [weak self] in
            self?.actions?.triggerReadSelected()
        }
    }

    private func startSelectionMonitoringIfNeeded() {
        if selectionMonitorTimer != nil {
            return
        }

        refreshSelectionAvailability()
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshSelectionAvailability()
            }
        }
        selectionMonitorTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshSelectionAvailability() {
        let selected = SelectionProbe.shouldShowReadButton()
        guard selected != hasSelectedText else {
            return
        }
        hasSelectedText = selected
        apply(state: currentState)
    }

    private func primaryIcon(tint: NSColor) -> NSImage? {
        micButton?.contentTintColor = tint
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        return NSImage(systemSymbolName: Symbols.primary, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    private func readIcon(symbol: String, tint: NSColor) -> NSImage? {
        readButton?.contentTintColor = tint
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    private func startListeningAnimationIfNeeded() {
        guard let rippleLayer = ensureListeningRippleLayer() else {
            return
        }

        guard rippleLayer.animation(forKey: AnimationKeys.micRipple) == nil else {
            return
        }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return
        }

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 1.58

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.7
        opacity.toValue = 0.0

        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration = 0.82
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.repeatCount = .infinity
        group.isRemovedOnCompletion = false
        rippleLayer.add(group, forKey: AnimationKeys.micRipple)
    }

    private func stopListeningAnimation(resetVisuals: Bool) {
        listeningRippleLayer?.removeAnimation(forKey: AnimationKeys.micRipple)
        guard resetVisuals else {
            return
        }
        latestAudioLevel = 0
        applyListeningVisuals(level: 0)
    }

    private func applyListeningVisuals(level: Float) {
        guard let buttonLayer = micButton?.layer else {
            return
        }

        let normalized = CGFloat(min(max(level, 0), 1))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        buttonLayer.shadowColor = NSColor.systemRed.cgColor
        buttonLayer.shadowOpacity = Float(0.18 + (normalized * 0.42))
        buttonLayer.shadowRadius = 2.5 + (normalized * 6.5)
        buttonLayer.shadowOffset = .zero
        if let rippleLayer = listeningRippleLayer {
            let alpha = 0.32 + (normalized * 0.5)
            rippleLayer.strokeColor = NSColor.systemRed.withAlphaComponent(alpha).cgColor
            rippleLayer.lineWidth = 1.2 + (normalized * 0.9)
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                rippleLayer.opacity = Float(0.2 + (normalized * 0.45))
            }
        }
        CATransaction.commit()
    }

    private func ensureListeningRippleLayer() -> CAShapeLayer? {
        guard let buttonLayer = micButton?.layer else {
            return nil
        }

        if let listeningRippleLayer {
            return listeningRippleLayer
        }

        let ripple = CAShapeLayer()
        ripple.fillColor = NSColor.clear.cgColor
        ripple.strokeColor = NSColor.systemRed.withAlphaComponent(0.5).cgColor
        ripple.lineWidth = 1.5
        ripple.opacity = 0
        ripple.zPosition = -1
        buttonLayer.addSublayer(ripple)
        listeningRippleLayer = ripple
        layoutListeningRippleLayer()
        return ripple
    }

    private func layoutListeningRippleLayer() {
        guard let ripple = listeningRippleLayer,
              let micButton
        else {
            return
        }

        let bounds = micButton.bounds
        ripple.frame = bounds
        let inset: CGFloat = 3
        ripple.path = CGPath(ellipseIn: bounds.insetBy(dx: inset, dy: inset), transform: nil)
    }
}

@MainActor
public final class NoopFloatingBarManager: FloatingBarManaging {
    public init() {}

    public func setActions(_ actions: FloatingBarActions?) {}
    public func show(state: RecorderState) {}
    public func update(state: RecorderState) {}
    public func updateAudioLevel(_ level: Float) {}
    public func hide() {}
}
