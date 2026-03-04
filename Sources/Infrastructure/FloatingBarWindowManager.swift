import AppCore
import AppKit
import Foundation

@MainActor
public final class FloatingBarWindowManager: NSObject, FloatingBarManaging {
    private enum Metrics {
        static let leftSectionWidth: CGFloat = 37
        static let leftSectionHeight: CGFloat = 9
        static let sectionGap: CGFloat = 2
        static let rightSectionWidth: CGFloat = 20
        static let rightSectionHeight: CGFloat = 9
        static let speakingRightSectionWidth: CGFloat = 60
        static let speakingRightSectionHeight: CGFloat = 18
        static let horizontalPadding: CGFloat = 5
        static let panelBottomInset: CGFloat = 14
        static let errorMinWidth: CGFloat = 300
        static let errorMaxWidth: CGFloat = 560
        static let errorMinHeight: CGFloat = 48
        static let errorHorizontalPadding: CGFloat = 12
        static let errorVerticalPadding: CGFloat = 10
        static let errorDismissSize: CGFloat = 20
        static let errorDismissTrailingPadding: CGFloat = 10
        static let errorTextSpacing: CGFloat = 10
        static let errorCornerRadius: CGFloat = 12
        static let errorAutoDismissDelay: TimeInterval = 2.8
        static let speakingStopButtonPadding: CGFloat = 2
        static let speakingStopIconMinSize: CGFloat = 7
        static let speakingStopIconMaxSize: CGFloat = 10
    }

    private enum WaveformMode {
        case idle
        case listening
        case processing
    }

    private enum HoverTarget {
        case dictation
        case read
    }

    private struct ErrorLayoutMetrics {
        let width: CGFloat
        let height: CGFloat
        let labelFrame: NSRect
        let dismissFrame: NSRect
    }

    private var panel: NSPanel?
    private var container: NSView?
    private var dictationHitArea: HoverTrackingButton?
    private var readButton: HoverTrackingButton?
    private var waveformView: ActivityWaveformView?
    private var errorLabel: NSTextField?
    private var dismissErrorButton: NSButton?

    private var leftSectionLayer: CALayer?
    private var rightSectionLayer: CALayer?
    private var readStopButtonLayer: CALayer?
    private var readStopIconLayer: CALayer?

    private var currentState: RecorderState = .idle
    private var actions: FloatingBarActions?
    private var hasSelectedText = false
    private var selectionMonitorTimer: Timer?
    private var latestAudioLevel: Float = 0
    private var dictationTooltipText: String?
    private var readTooltipText: String?
    private var hoveredTarget: HoverTarget?
    private let hoverTooltip = FloatingHoverTooltip()
    private var activeErrorMessage: String?
    private var dismissedErrorMessage: String?
    private var errorAutoDismissWorkItem: DispatchWorkItem?

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
        refreshTooltipIfNeeded()
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
        clearErrorPresentationState()
        hoveredTarget = nil
        hoverTooltip.hide(animated: false)
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let initialWidth = Metrics.leftSectionWidth + Metrics.sectionGap + Metrics.rightSectionWidth
        let initialHeight = max(Metrics.leftSectionHeight, Metrics.rightSectionHeight)
        let frame = NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight)
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
        panel.canHide = false
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
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.layer?.borderColor = NSColor.clear.cgColor
        container.layer?.borderWidth = 0
        container.layer?.cornerRadius = 0
        container.layer?.masksToBounds = false

        let dictationHitArea = makeHitAreaButton(action: #selector(handleMicTap))
        let readButton = makeHitAreaButton(action: #selector(handleReadTap))
        let dismissErrorButton = makeDismissErrorButton(action: #selector(handleDismissErrorTap))
        readButton.wantsLayer = true
        readButton.layer?.backgroundColor = NSColor.clear.cgColor
        readButton.layer?.borderColor = NSColor.clear.cgColor
        readButton.layer?.borderWidth = 0

        let waveformView = ActivityWaveformView(frame: .zero)
        waveformView.wantsLayer = true
        waveformView.layer?.masksToBounds = true
        waveformView.isHidden = true

        let errorLabel = NSTextField(labelWithString: "")
        errorLabel.font = .systemFont(ofSize: 11, weight: .medium)
        errorLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        errorLabel.lineBreakMode = .byWordWrapping
        errorLabel.maximumNumberOfLines = 0
        errorLabel.alignment = .left
        errorLabel.isHidden = true

        let rightSectionLayer = CALayer()
        rightSectionLayer.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        if #available(macOS 10.13, *) {
            rightSectionLayer.maskedCorners = [
                .layerMinXMinYCorner,
                .layerMinXMaxYCorner,
                .layerMaxXMinYCorner,
                .layerMaxXMaxYCorner
            ]
        }

        let leftSectionLayer = CALayer()
        leftSectionLayer.backgroundColor = NSColor.black.withAlphaComponent(0.56).cgColor
        leftSectionLayer.borderColor = NSColor.white.withAlphaComponent(0.56).cgColor
        leftSectionLayer.borderWidth = 1

        let readStopButtonLayer = CALayer()
        readStopButtonLayer.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
        readStopButtonLayer.borderColor = NSColor.clear.cgColor
        readStopButtonLayer.borderWidth = 0
        readStopButtonLayer.isHidden = true
        readStopButtonLayer.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "frame": NSNull(),
            "hidden": NSNull(),
            "opacity": NSNull()
        ]

        let readStopIconLayer = CALayer()
        readStopIconLayer.backgroundColor = NSColor.white.withAlphaComponent(0.96).cgColor
        readStopIconLayer.cornerRadius = 1
        readStopIconLayer.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "frame": NSNull()
        ]
        readStopButtonLayer.addSublayer(readStopIconLayer)
        readButton.layer?.addSublayer(readStopButtonLayer)

        container.layer?.addSublayer(leftSectionLayer)
        container.layer?.addSublayer(rightSectionLayer)
        container.addSubview(dictationHitArea)
        container.addSubview(readButton)
        container.addSubview(waveformView)
        container.addSubview(errorLabel)
        container.addSubview(dismissErrorButton)
        panel.contentView = container

        self.panel = panel
        self.container = container
        self.dictationHitArea = dictationHitArea
        self.readButton = readButton
        self.waveformView = waveformView
        self.errorLabel = errorLabel
        self.dismissErrorButton = dismissErrorButton
        self.leftSectionLayer = leftSectionLayer
        self.rightSectionLayer = rightSectionLayer
        self.readStopButtonLayer = readStopButtonLayer
        self.readStopIconLayer = readStopIconLayer

        configureHoverHandlers()
        apply(state: .idle)
        return panel
    }

    private func makeHitAreaButton(action: Selector) -> HoverTrackingButton {
        let button = HoverTrackingButton(frame: .zero)
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

    private func makeDismissErrorButton(action: Selector) -> NSButton {
        let button = NSButton(frame: .zero)
        button.setButtonType(.momentaryChange)
        button.isBordered = false
        button.title = "✕"
        button.font = .systemFont(ofSize: 12, weight: .bold)
        button.contentTintColor = NSColor.white.withAlphaComponent(0.96)
        button.target = self
        button.action = action
        button.focusRingType = .none
        button.wantsLayer = true
        button.layer?.cornerRadius = Metrics.errorDismissSize / 2
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.36).cgColor
        button.layer?.borderWidth = 1
        button.isHidden = true
        return button
    }

    private func apply(state: RecorderState) {
        guard panel != nil else {
            return
        }

        let canUseActions = actions != nil
        dictationTooltipText = normalizedTooltipText(actions?.dictationHint)

        if state == .speaking {
            readTooltipText = "Click to stop narration."
        } else if hasSelectedText {
            readTooltipText = normalizedTooltipText(actions?.readSelectedHint)
        } else {
            readTooltipText = "Click to try narrating selected text."
        }

        let errorMessage: String?
        let waveformMode: WaveformMode

        switch state {
        case .idle:
            waveformMode = .idle
            errorMessage = nil
            clearErrorPresentationState()
        case .listening:
            waveformMode = .listening
            errorMessage = nil
            clearErrorPresentationState()
        case .transcribing, .injecting, .speaking:
            waveformMode = .processing
            errorMessage = nil
            clearErrorPresentationState()
        case .error(let message):
            waveformMode = .idle
            let normalizedError = normalizedTooltipText(message) ?? "Something went wrong."
            registerErrorMessage(normalizedError)
            errorMessage = shouldPresentErrorMessage(normalizedError) ? normalizedError : nil
        }

        let isPresentingError = errorMessage != nil
        if isPresentingError {
            hoveredTarget = nil
            hoverTooltip.hide(animated: true)
        }

        dictationHitArea?.isEnabled = canUseActions && !isBusy(state) && !isPresentingError
        readButton?.isEnabled = canUseActions && canTriggerRead(for: state) && !isPresentingError
        readButton?.alphaValue = isPresentingError ? 1 : readAlpha(for: state)

        updateRightSectionAppearance(for: state)
        layoutPanel(errorMessage: errorMessage, animated: true)
        applyWaveform(mode: waveformMode)
        refreshTooltipIfNeeded()
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
              let errorLabel,
              let dismissErrorButton
        else {
            return
        }

        let isSpeaking = currentState == .speaking
        let leftSectionWidth = Metrics.leftSectionWidth
        let leftSectionHeight = Metrics.leftSectionHeight
        let rightSectionWidth = isSpeaking ? Metrics.speakingRightSectionWidth : Metrics.rightSectionWidth
        let rightSectionHeight = isSpeaking ? Metrics.speakingRightSectionHeight : Metrics.rightSectionHeight
        let gap = Metrics.sectionGap
        let nonErrorWidth = leftSectionWidth + gap + rightSectionWidth
        let nonErrorHeight = max(leftSectionHeight, rightSectionHeight)
        let errorLayout = errorMessage.map { makeErrorLayout(for: $0, in: panel, label: errorLabel) }
        let width = errorLayout?.width ?? nonErrorWidth
        let height = errorLayout?.height ?? nonErrorHeight
        let isErrorExpanded = errorLayout != nil
        let leftSectionY = floor((height - leftSectionHeight) / 2)
        let rightSectionX = leftSectionWidth + gap
        let rightSectionY = floor((height - rightSectionHeight) / 2)

        panel.setContentSize(NSSize(width: width, height: height))
        container.frame = NSRect(x: 0, y: 0, width: width, height: height)
        container.layer?.cornerRadius = isErrorExpanded ? Metrics.errorCornerRadius : 0
        leftSectionLayer?.isHidden = isErrorExpanded
        updateContainerAppearance(isErrorExpanded: isErrorExpanded)

        dictationHitArea.isHidden = isErrorExpanded
        readButton.isHidden = isErrorExpanded
        dismissErrorButton.isHidden = !isErrorExpanded
        rightSectionLayer?.isHidden = isErrorExpanded

        if !isErrorExpanded {
            leftSectionLayer?.frame = NSRect(
                x: 0,
                y: leftSectionY,
                width: leftSectionWidth,
                height: leftSectionHeight
            )
            leftSectionLayer?.cornerRadius = leftSectionHeight / 2
            rightSectionLayer?.frame = NSRect(
                x: rightSectionX,
                y: rightSectionY,
                width: rightSectionWidth,
                height: rightSectionHeight
            )
            rightSectionLayer?.cornerRadius = rightSectionHeight / 2
            dictationHitArea.frame = NSRect(
                x: 0,
                y: leftSectionY,
                width: leftSectionWidth,
                height: leftSectionHeight
            )
            readButton.frame = NSRect(
                x: rightSectionX,
                y: rightSectionY,
                width: rightSectionWidth,
                height: rightSectionHeight
            )
            updateReadStopButtonAppearance(
                isSpeaking: isSpeaking,
                buttonBounds: readButton.bounds,
                height: rightSectionHeight
            )
        } else {
            updateReadStopButtonAppearance(isSpeaking: false, buttonBounds: .zero, height: height)
        }

        if let errorMessage, let errorLayout {
            waveformView.isHidden = true
            errorLabel.stringValue = errorMessage
            errorLabel.isHidden = false
            errorLabel.frame = errorLayout.labelFrame
            dismissErrorButton.frame = errorLayout.dismissFrame
        } else {
            dismissErrorButton.isHidden = true
            errorLabel.isHidden = true
            errorLabel.stringValue = ""
            waveformView.frame = NSRect(
                x: Metrics.horizontalPadding,
                y: leftSectionY + 2,
                width: max(0, leftSectionWidth - (Metrics.horizontalPadding * 2)),
                height: max(0, leftSectionHeight - 4)
            )
        }

        positionPanel(panel, targetWidth: width, targetHeight: height, animated: animated)
    }

    private func updateContainerAppearance(isErrorExpanded: Bool) {
        guard let layer = container?.layer else {
            return
        }

        if isErrorExpanded {
            layer.backgroundColor = NSColor.systemRed.withAlphaComponent(0.33).cgColor
            layer.borderColor = NSColor.systemRed.withAlphaComponent(0.88).cgColor
            layer.borderWidth = 1.2
            layer.masksToBounds = true
            return
        }

        layer.backgroundColor = NSColor.clear.cgColor
        layer.borderColor = NSColor.clear.cgColor
        layer.borderWidth = 0
        layer.masksToBounds = false
        leftSectionLayer?.backgroundColor = NSColor.black.withAlphaComponent(0.56).cgColor
        leftSectionLayer?.borderColor = NSColor.white.withAlphaComponent(0.56).cgColor
        leftSectionLayer?.borderWidth = 1
        rightSectionLayer?.borderColor = NSColor.white.withAlphaComponent(0.56).cgColor
        rightSectionLayer?.borderWidth = 1
    }

    private func makeErrorLayout(for message: String, in panel: NSPanel, label: NSTextField) -> ErrorLayoutMetrics {
        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let maxWidth = max(
            Metrics.errorMinWidth,
            min(
                Metrics.errorMaxWidth,
                (visibleFrame?.width ?? Metrics.errorMaxWidth) - (Metrics.horizontalPadding * 6)
            )
        )

        let font = label.font ?? .systemFont(ofSize: 11, weight: .medium)
        let fixedWidth = Metrics.errorHorizontalPadding + Metrics.errorTextSpacing + Metrics.errorDismissSize + Metrics.errorDismissTrailingPadding
        let singleLineWidth = ceil((message as NSString).size(withAttributes: [.font: font]).width)
        let width = min(maxWidth, max(Metrics.errorMinWidth, singleLineWidth + fixedWidth))
        let labelWidth = max(48, width - fixedWidth)

        let measuredTextHeight = ceil(
            (message as NSString).boundingRect(
                with: NSSize(width: labelWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            ).height
        )
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let labelHeight = max(lineHeight, measuredTextHeight)
        let height = max(Metrics.errorMinHeight, labelHeight + (Metrics.errorVerticalPadding * 2))

        let labelFrame = NSRect(
            x: Metrics.errorHorizontalPadding,
            y: Metrics.errorVerticalPadding,
            width: labelWidth,
            height: height - (Metrics.errorVerticalPadding * 2)
        )

        let dismissFrame = NSRect(
            x: width - Metrics.errorDismissTrailingPadding - Metrics.errorDismissSize,
            y: floor((height - Metrics.errorDismissSize) / 2),
            width: Metrics.errorDismissSize,
            height: Metrics.errorDismissSize
        )

        return ErrorLayoutMetrics(
            width: width,
            height: height,
            labelFrame: labelFrame,
            dismissFrame: dismissFrame
        )
    }

    private func updateReadStopButtonAppearance(isSpeaking: Bool, buttonBounds: NSRect, height: CGFloat) {
        guard let readButton, let readStopButtonLayer, let readStopIconLayer else {
            return
        }

        readButton.title = ""
        readButton.attributedTitle = NSAttributedString(string: "")
        readButton.layer?.backgroundColor = NSColor.clear.cgColor
        readButton.layer?.borderColor = NSColor.clear.cgColor
        readButton.layer?.borderWidth = 0
        readButton.layer?.cornerRadius = 0

        guard isSpeaking else {
            readStopButtonLayer.isHidden = true
            return
        }

        let padding = Metrics.speakingStopButtonPadding
        let stopButtonFrame = buttonBounds.insetBy(dx: padding, dy: padding)
        guard stopButtonFrame.width > 0, stopButtonFrame.height > 0 else {
            readStopButtonLayer.isHidden = true
            return
        }

        readStopButtonLayer.frame = stopButtonFrame
        readStopButtonLayer.cornerRadius = min(stopButtonFrame.width, stopButtonFrame.height) / 2
        readStopButtonLayer.isHidden = false

        let maxIconByBounds = max(0, min(stopButtonFrame.width, stopButtonFrame.height) - 2)
        let iconSize = min(
            maxIconByBounds,
            max(
                Metrics.speakingStopIconMinSize,
                min(Metrics.speakingStopIconMaxSize, (height * 0.5))
            )
        )
        let iconX = (stopButtonFrame.width - iconSize) / 2
        let iconY = (stopButtonFrame.height - iconSize) / 2
        readStopIconLayer.frame = NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize)
        readStopIconLayer.cornerRadius = max(0.8, iconSize * 0.2)
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
        hoveredTarget = nil
        hoverTooltip.hide(animated: true)
        actions?.toggleDictation()
    }

    @objc
    private func handleReadTap() {
        hoveredTarget = nil
        hoverTooltip.hide(animated: true)
        DispatchQueue.main.async { [weak self] in
            self?.actions?.triggerReadSelected()
        }
    }

    @objc
    private func handleDismissErrorTap() {
        guard let activeErrorMessage else {
            return
        }
        dismissedErrorMessage = activeErrorMessage
        cancelErrorAutoDismiss()
        apply(state: currentState)
    }

    private func configureHoverHandlers() {
        dictationHitArea?.onHoverChanged = { [weak self] isHovering in
            Task { @MainActor [weak self] in
                self?.handleHoverChange(for: .dictation, isHovering: isHovering)
            }
        }

        readButton?.onHoverChanged = { [weak self] isHovering in
            Task { @MainActor [weak self] in
                self?.handleHoverChange(for: .read, isHovering: isHovering)
            }
        }
    }

    private func handleHoverChange(for target: HoverTarget, isHovering: Bool) {
        if isHovering {
            hoveredTarget = target
            refreshTooltipIfNeeded()
            return
        }

        guard hoveredTarget == target else {
            return
        }

        hoveredTarget = nil
        hoverTooltip.hide(animated: true)
    }

    private func refreshTooltipIfNeeded() {
        guard let hoveredTarget else {
            hoverTooltip.hide(animated: true)
            return
        }

        let button: HoverTrackingButton?
        let tooltipText: String?

        switch hoveredTarget {
        case .dictation:
            button = dictationHitArea
            tooltipText = dictationTooltipText
        case .read:
            button = readButton
            tooltipText = readTooltipText
        }

        guard let button, button.isEnabled, let tooltipText else {
            self.hoveredTarget = nil
            hoverTooltip.hide(animated: true)
            return
        }

        hoverTooltip.show(text: tooltipText, anchoredTo: button)
    }

    private func normalizedTooltipText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func registerErrorMessage(_ message: String) {
        if activeErrorMessage != message {
            activeErrorMessage = message
            dismissedErrorMessage = nil
            scheduleErrorAutoDismiss(for: message)
            return
        }

        if dismissedErrorMessage == nil, errorAutoDismissWorkItem == nil {
            scheduleErrorAutoDismiss(for: message)
        }
    }

    private func shouldPresentErrorMessage(_ message: String) -> Bool {
        dismissedErrorMessage != message
    }

    private func clearErrorPresentationState() {
        activeErrorMessage = nil
        dismissedErrorMessage = nil
        cancelErrorAutoDismiss()
    }

    private func scheduleErrorAutoDismiss(for message: String) {
        cancelErrorAutoDismiss()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                guard case .error = self.currentState,
                      self.activeErrorMessage == message
                else {
                    self.errorAutoDismissWorkItem = nil
                    return
                }

                self.dismissedErrorMessage = message
                self.errorAutoDismissWorkItem = nil
                self.apply(state: self.currentState)
            }
        }

        errorAutoDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.errorAutoDismissDelay, execute: workItem)
    }

    private func cancelErrorAutoDismiss() {
        errorAutoDismissWorkItem?.cancel()
        errorAutoDismissWorkItem = nil
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
            alpha = 0.2
        case .listening, .transcribing, .injecting:
            alpha = 0.06
        case .idle, .error:
            alpha = hasSelectedText ? 0.12 : 0.06
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

private final class HoverTrackingButton: NSButton {
    var onHoverChanged: ((Bool) -> Void)?

    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea

        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        onHoverChanged?(true)
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        onHoverChanged?(false)
        super.mouseExited(with: event)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, isHovering {
            isHovering = false
            onHoverChanged?(false)
        }
        super.viewWillMove(toWindow: newWindow)
    }
}

@MainActor
private final class FloatingHoverTooltip {
    private enum Metrics {
        static let minWidth: CGFloat = 150
        static let preferredMaxWidth: CGFloat = 340
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 6
        static let screenInset: CGFloat = 8
        static let anchorOffset: CGFloat = 6
        static let cornerRadius: CGFloat = 8
        static let showDuration: TimeInterval = 0.14
    }

    private let panel: NSPanel
    private let bubbleView: NSView
    private let bubbleGradientLayer = CAGradientLayer()
    private let sheenLayer = CAGradientLayer()
    private let label = NSTextField(labelWithString: "")

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.minWidth, height: 28),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.canHide = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        let bubbleView = NSView(frame: panel.contentView?.bounds ?? .zero)
        bubbleView.autoresizingMask = [.width, .height]
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = Metrics.cornerRadius
        bubbleView.layer?.masksToBounds = true
        bubbleView.layer?.borderWidth = 1
        bubbleView.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor

        bubbleGradientLayer.colors = [
            NSColor(calibratedRed: 0.23, green: 0.25, blue: 0.3, alpha: 0.95).cgColor,
            NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.17, alpha: 0.96).cgColor
        ]
        bubbleGradientLayer.startPoint = CGPoint(x: 0.1, y: 1)
        bubbleGradientLayer.endPoint = CGPoint(x: 0.9, y: 0)

        sheenLayer.colors = [
            NSColor.white.withAlphaComponent(0.16).cgColor,
            NSColor.clear.cgColor
        ]
        sheenLayer.startPoint = CGPoint(x: 0.5, y: 1)
        sheenLayer.endPoint = CGPoint(x: 0.5, y: 0)
        sheenLayer.locations = [0, 0.7]

        bubbleView.layer?.insertSublayer(bubbleGradientLayer, at: 0)
        bubbleView.layer?.insertSublayer(sheenLayer, at: 1)

        let content = NSView(frame: panel.contentView?.bounds ?? .zero)
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.masksToBounds = false
        content.layer?.shadowColor = NSColor.black.cgColor
        content.layer?.shadowOpacity = 0.34
        content.layer?.shadowRadius = 9
        content.layer?.shadowOffset = CGSize(width: 0, height: -2)
        content.addSubview(bubbleView)

        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.96)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.cell?.usesSingleLineMode = false
        label.cell?.wraps = true
        label.cell?.truncatesLastVisibleLine = false
        bubbleView.addSubview(label)
        panel.contentView = content

        self.panel = panel
        self.bubbleView = bubbleView
    }

    func show(text: String, anchoredTo anchorView: NSView) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hide(animated: true)
            return
        }

        label.stringValue = trimmed

        let visibleFrame = anchorView.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let maxAllowedWidth = max(
            Metrics.minWidth,
            min(
                Metrics.preferredMaxWidth,
                (visibleFrame?.width ?? Metrics.preferredMaxWidth) - (Metrics.screenInset * 2)
            )
        )

        let font = label.font ?? .systemFont(ofSize: 11, weight: .semibold)
        let singleLineWidth = ceil((trimmed as NSString).size(withAttributes: [.font: font]).width)
        let width = min(
            maxAllowedWidth,
            max(Metrics.minWidth, singleLineWidth + (Metrics.horizontalPadding * 2))
        )
        let textWidth = width - (Metrics.horizontalPadding * 2)

        let measuredLabelHeight = ceil(
            (trimmed as NSString).boundingRect(
                with: NSSize(width: max(1, textWidth), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]
            ).height
        )
        let labelHeight = max(ceil(label.intrinsicContentSize.height), measuredLabelHeight)
        let height = ceil(labelHeight + (Metrics.verticalPadding * 2))

        panel.setContentSize(NSSize(width: width, height: height))
        bubbleView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        bubbleGradientLayer.frame = bubbleView.bounds
        sheenLayer.frame = bubbleView.bounds
        label.frame = NSRect(
            x: Metrics.horizontalPadding,
            y: Metrics.verticalPadding,
            width: width - (Metrics.horizontalPadding * 2),
            height: height - (Metrics.verticalPadding * 2)
        )

        positionPanel(anchoredTo: anchorView, width: width, height: height)

        if panel.isVisible {
            panel.orderFrontRegardless()
            panel.alphaValue = 1
            return
        }

        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        panel.orderFrontRegardless()

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Metrics.showDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide(animated _: Bool) {
        guard panel.isVisible else {
            return
        }

        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    private func positionPanel(anchoredTo anchorView: NSView, width: CGFloat, height: CGFloat) {
        guard let window = anchorView.window else {
            return
        }

        let anchorRectInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorRectInScreen = window.convertToScreen(anchorRectInWindow)

        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchorRectInScreen
        let minX = visibleFrame.minX + Metrics.screenInset
        let maxX = visibleFrame.maxX - width - Metrics.screenInset

        let rawX = anchorRectInScreen.midX - (width / 2)
        let x = min(max(rawX, minX), maxX)
        let y = anchorRectInScreen.maxY + Metrics.anchorOffset

        let frame = NSRect(x: x, y: y, width: width, height: height)
        panel.setFrame(frame, display: true)
    }
}

private final class ActivityWaveformView: NSView {
    private enum Metrics {
        static let silenceFloor: CGFloat = 0.05
        static let minimumVisibleLevel: CGFloat = 0.02
    }

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
        let clamped = min(max(level, 0), 1)
        let gated = max(0, (clamped - Metrics.silenceFloor) / (1 - Metrics.silenceFloor))
        let smoothing: CGFloat = gated > currentLevel ? 0.42 : 0.18
        currentLevel = currentLevel + ((gated - currentLevel) * smoothing)
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
        let phaseStep: CGFloat = mode == .processing ? 0.34 : 0.12
        phase += phaseStep
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

        if mode == .listening && currentLevel <= Metrics.minimumVisibleLevel {
            return
        }

        for index in 0..<barCount {
            let t = CGFloat(index) / CGFloat(max(barCount - 1, 1))
            let distanceFromCenter = abs((t * 2) - 1)
            let envelope = max(0.08, 1 - (distanceFromCenter * 1.2))
            let barHeight: CGFloat
            let brightness: CGFloat

            switch mode {
            case .listening:
                let level = pow(currentLevel, 0.8)
                let contour = 0.85 + (0.15 * abs(sin((CGFloat(index) * 0.35) + phase)))
                let amplitude = (rect.height - 1.6) * level * envelope * contour
                barHeight = max(1.2, min(rect.height - 1.4, amplitude))
                brightness = 0.78 + (0.22 * min(1, level + (envelope * 0.2)))
            case .processing:
                let pulse = abs(sin((phase * 0.72) + (CGFloat(index) * 0.23)))
                let amplitude = (1.2 + (rect.height * 0.72 * 0.5 * pulse)) * envelope
                barHeight = max(1.8, min(rect.height - 1.5, amplitude))
                brightness = 0.72 + (0.28 * pulse)
            }

            let x = rect.minX + (step * CGFloat(index)) + ((step - barWidth) / 2)
            let y = baselineY - (barHeight / 2)
            let barRect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
            let path = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)

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
