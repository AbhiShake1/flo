import AppCore
import AppKit
import Foundation

@MainActor
public final class FloatingBarWindowManager: NSObject, FloatingBarManaging {
    private enum Metrics {
        static let collapsedWidth: CGFloat = 37
        static let expandedErrorWidth: CGFloat = 320
        static let pillHeight: CGFloat = 9
        static let rightSectionWidth: CGFloat = 9
        static let horizontalPadding: CGFloat = 5
        static let dividerInset: CGFloat = 3
        static let panelBottomInset: CGFloat = 14
    }

    private enum WaveformMode {
        case idle
        case listening
        case processing
    }

    private var panel: NSPanel?
    private var container: NSView?
    private var dictationHitArea: NSButton?
    private var readButton: NSButton?
    private var waveformView: ActivityWaveformView?
    private var errorLabel: NSTextField?

    private var dividerLayer: CALayer?
    private var rightSectionLayer: CALayer?

    private var currentState: RecorderState = .idle
    private var actions: FloatingBarActions?
    private var hasSelectedText = false
    private var selectionMonitorTimer: Timer?
    private var latestAudioLevel: Float = 0

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
        waveformView?.setLevel(CGFloat(clamped))
    }

    public func hide() {
        selectionMonitorTimer?.invalidate()
        selectionMonitorTimer = nil
        waveformView?.stopAnimating()
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let frame = NSRect(x: 0, y: 0, width: Metrics.collapsedWidth, height: Metrics.pillHeight)
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
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.56).cgColor
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.56).cgColor
        container.layer?.borderWidth = 1
        container.layer?.cornerRadius = Metrics.pillHeight / 2
        container.layer?.masksToBounds = true

        let dictationHitArea = makeHitAreaButton(action: #selector(handleMicTap))
        let readButton = makeHitAreaButton(action: #selector(handleReadTap))

        let waveformView = ActivityWaveformView(frame: .zero)
        waveformView.wantsLayer = true
        waveformView.layer?.masksToBounds = true
        waveformView.isHidden = true

        let errorLabel = NSTextField(labelWithString: "")
        errorLabel.font = .systemFont(ofSize: 9, weight: .medium)
        errorLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        errorLabel.lineBreakMode = .byTruncatingTail
        errorLabel.alignment = .left
        errorLabel.isHidden = true

        let rightSectionLayer = CALayer()
        rightSectionLayer.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        if #available(macOS 10.13, *) {
            rightSectionLayer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        }

        let dividerLayer = CALayer()
        dividerLayer.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor

        container.layer?.addSublayer(rightSectionLayer)
        container.layer?.addSublayer(dividerLayer)
        container.addSubview(dictationHitArea)
        container.addSubview(readButton)
        container.addSubview(waveformView)
        container.addSubview(errorLabel)
        panel.contentView = container

        self.panel = panel
        self.container = container
        self.dictationHitArea = dictationHitArea
        self.readButton = readButton
        self.waveformView = waveformView
        self.errorLabel = errorLabel
        self.rightSectionLayer = rightSectionLayer
        self.dividerLayer = dividerLayer

        apply(state: .idle)
        return panel
    }

    private func makeHitAreaButton(action: Selector) -> NSButton {
        let button = NSButton(frame: .zero)
        button.setButtonType(.momentaryChange)
        button.isBordered = false
        button.title = ""
        button.target = self
        button.action = action
        button.focusRingType = .none
        if let cell = button.cell as? NSButtonCell {
            cell.highlightsBy = []
            cell.showsStateBy = []
        }
        return button
    }

    private func apply(state: RecorderState) {
        guard panel != nil else {
            return
        }

        let canUseActions = actions != nil
        let readEnabled = canUseActions && canTriggerRead(for: state)

        dictationHitArea?.isEnabled = canUseActions && !isBusy(state)
        readButton?.isEnabled = readEnabled
        dictationHitArea?.toolTip = actions?.dictationHint

        if state == .speaking {
            readButton?.toolTip = "Click to stop narration."
        } else if hasSelectedText {
            readButton?.toolTip = actions?.readSelectedHint
        } else {
            readButton?.toolTip = "Click to try narrating selected text."
        }

        let errorMessage: String?
        let waveformMode: WaveformMode

        switch state {
        case .idle:
            waveformMode = .idle
            errorMessage = nil
        case .listening:
            waveformMode = .listening
            errorMessage = nil
        case .transcribing, .injecting, .speaking:
            waveformMode = .processing
            errorMessage = nil
        case .error(let message):
            waveformMode = .idle
            errorMessage = message
        }

        readButton?.alphaValue = readAlpha(for: state)
        updateRightSectionAppearance(for: state)
        layoutPanel(errorMessage: errorMessage, animated: true)
        applyWaveform(mode: waveformMode)
    }

    private func applyWaveform(mode: WaveformMode) {
        guard let waveformView else {
            return
        }

        switch mode {
        case .idle:
            waveformView.stopAnimating()
            waveformView.isHidden = true
        case .listening:
            waveformView.mode = .listening
            waveformView.setLevel(CGFloat(latestAudioLevel))
            waveformView.isHidden = false
            waveformView.startAnimating()
        case .processing:
            waveformView.mode = .processing
            waveformView.setLevel(0.5)
            waveformView.isHidden = false
            waveformView.startAnimating()
        }
    }

    private func layoutPanel(errorMessage: String?, animated: Bool) {
        guard let panel,
              let container,
              let dictationHitArea,
              let readButton,
              let waveformView,
              let errorLabel
        else {
            return
        }

        let width = (errorMessage == nil) ? Metrics.collapsedWidth : Metrics.expandedErrorWidth
        let height = Metrics.pillHeight
        let rightSectionX = width - Metrics.rightSectionWidth

        panel.setContentSize(NSSize(width: width, height: height))
        container.frame = NSRect(x: 0, y: 0, width: width, height: height)
        container.layer?.cornerRadius = height / 2
        rightSectionLayer?.frame = NSRect(x: rightSectionX, y: 0, width: Metrics.rightSectionWidth, height: height)
        rightSectionLayer?.cornerRadius = height / 2

        dividerLayer?.frame = NSRect(
            x: rightSectionX,
            y: Metrics.dividerInset,
            width: 1,
            height: height - (Metrics.dividerInset * 2)
        )

        dictationHitArea.frame = NSRect(x: 0, y: 0, width: rightSectionX, height: height)
        readButton.frame = NSRect(x: rightSectionX, y: 0, width: Metrics.rightSectionWidth, height: height)

        if let errorMessage {
            waveformView.isHidden = true
            errorLabel.stringValue = errorMessage
            errorLabel.isHidden = false
            errorLabel.frame = NSRect(
                x: Metrics.horizontalPadding,
                y: 2,
                width: max(0, rightSectionX - (Metrics.horizontalPadding * 2)),
                height: height - 4
            )
        } else {
            errorLabel.isHidden = true
            errorLabel.stringValue = ""
            waveformView.frame = NSRect(
                x: Metrics.horizontalPadding,
                y: 2,
                width: max(0, rightSectionX - (Metrics.horizontalPadding * 2)),
                height: height - 4
            )
        }

        positionPanel(panel, targetWidth: width, targetHeight: height, animated: animated)
    }

    private func positionPanel(
        _ panel: NSPanel,
        targetWidth: CGFloat? = nil,
        targetHeight: CGFloat? = nil,
        animated: Bool = false
    ) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else {
            return
        }

        let width = targetWidth ?? panel.frame.width
        let height = targetHeight ?? panel.frame.height
        let visible = screen.visibleFrame
        let x = visible.midX - (width / 2)
        let y = visible.minY + Metrics.panelBottomInset
        let frame = NSRect(x: x, y: y, width: width, height: height)

        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(frame, display: false, animate: true)
        } else {
            panel.setFrame(frame, display: false)
        }
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

    private func readAlpha(for state: RecorderState) -> CGFloat {
        if state == .speaking {
            return 1
        }

        if !canTriggerRead(for: state) {
            return 0.42
        }

        return hasSelectedText ? 1 : 0.68
    }

    private func updateRightSectionAppearance(for state: RecorderState) {
        let alpha: CGFloat
        switch state {
        case .speaking:
            alpha = 0.14
        case .listening, .transcribing, .injecting:
            alpha = 0.04
        case .idle, .error:
            alpha = hasSelectedText ? 0.1 : 0.04
        }
        rightSectionLayer?.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
    }

    private func isBusy(_ state: RecorderState) -> Bool {
        switch state {
        case .transcribing, .injecting, .speaking:
            return true
        case .idle, .listening, .error:
            return false
        }
    }

    private func canTriggerRead(for state: RecorderState) -> Bool {
        switch state {
        case .idle, .error, .speaking:
            return true
        case .listening, .transcribing, .injecting:
            return false
        }
    }
}

private final class ActivityWaveformView: NSView {
    enum Mode {
        case listening
        case processing
    }

    var mode: Mode = .listening {
        didSet {
            needsDisplay = true
        }
    }

    private var currentLevel: CGFloat = 0
    private var phase: CGFloat = 0
    private var animationTimer: Timer?

    func setLevel(_ level: CGFloat) {
        currentLevel = min(max(level, 0), 1)
        needsDisplay = true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopAnimating()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func startAnimating() {
        if animationTimer != nil {
            return
        }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            needsDisplay = true
            return
        }

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        phase = 0
        needsDisplay = true
    }

    private func tick() {
        phase += 0.34
        if phase > (.pi * 2) {
            phase -= (.pi * 2)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        guard rect.width > 12, rect.height > 6 else {
            return
        }

        let baselineY = rect.midY
        let baseline = NSBezierPath()
        baseline.move(to: NSPoint(x: rect.minX, y: baselineY))
        baseline.line(to: NSPoint(x: rect.maxX, y: baselineY))
        baseline.lineWidth = 1
        baseline.setLineDash([2, 2], count: 2, phase: 0)
        NSColor.white.withAlphaComponent(0.48).setStroke()
        baseline.stroke()

        let barCount = max(10, Int(rect.width / 4.5))
        let step = rect.width / CGFloat(barCount)
        let barWidth = max(1.2, min(2.1, step * 0.48))

        let activityBase: CGFloat
        switch mode {
        case .listening:
            activityBase = 0.2 + (currentLevel * 0.8)
        case .processing:
            activityBase = 0.5
        }

        for index in 0..<barCount {
            let t = CGFloat(index) / CGFloat(max(barCount - 1, 1))
            let distanceFromCenter = abs((t * 2) - 1)
            let envelope = max(0, 1 - (distanceFromCenter * 1.25))
            let wave = abs(sin(phase + (CGFloat(index) * 0.61)))
            let pulse = abs(sin((phase * 0.72) + (CGFloat(index) * 0.23)))
            let dynamic: CGFloat = mode == .processing ? pulse : wave
            let amplitude = (1.2 + (rect.height * 0.72 * activityBase * dynamic)) * max(0.18, envelope)
            let barHeight = max(1.8, min(rect.height - 1.5, amplitude))

            let x = rect.minX + (step * CGFloat(index)) + ((step - barWidth) / 2)
            let y = baselineY - (barHeight / 2)
            let barRect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)

            let brightness = 0.72 + (0.28 * dynamic)
            NSColor.white.withAlphaComponent(brightness).setFill()
            path.fill()
        }
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
