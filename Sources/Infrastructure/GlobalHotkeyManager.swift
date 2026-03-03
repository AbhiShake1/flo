import AppCore
import CoreGraphics
import Foundation

public final class GlobalHotkeyManager: HotkeyManaging {
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    private var handlers: HotkeyHandlers?
    private var bindings: [ShortcutAction: ShortcutBinding] = [:]
    private var dictationPressed = false
    private var lastReadTrigger = Date.distantPast

    public init() {}

    public func start(bindings: [ShortcutBinding], handlers: HotkeyHandlers) {
        stop()
        self.handlers = handlers
        self.bindings = Dictionary(uniqueKeysWithValues: bindings.map { ($0.action, $0) })
        installEventTap()
    }

    public func stop() {
        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            eventTapSource = nil
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }

        handlers = nil
        bindings = [:]
        dictationPressed = false
    }

    private enum EventPhase {
        case down
        case up
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
        return manager.handleTapEvent(type: type, event: event)
    }

    private func installEventTap() {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }

        eventTap = tap
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let phase: EventPhase = (type == .keyDown) ? .down : .up
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) == 1
        let shouldConsume = handle(
            keyCode: keyCode,
            flags: event.flags,
            phase: phase,
            isRepeat: isRepeat
        )

        if shouldConsume {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func handle(
        keyCode: UInt16,
        flags: CGEventFlags,
        phase: EventPhase,
        isRepeat: Bool
    ) -> Bool {
        guard let handlers else {
            return false
        }

        if let dictationBinding = bindings[.dictationHold],
           dictationBinding.enabled,
           matches(keyCode: keyCode, flags: flags, combo: dictationBinding.combo)
        {
            switch phase {
            case .down:
                if !dictationPressed {
                    dictationPressed = true
                    handlers.dictationStarted()
                }
            case .up:
                if dictationPressed {
                    dictationPressed = false
                    handlers.dictationStopped()
                }
            }
            return true
        }

        if phase == .down,
           !isRepeat,
           let readBinding = bindings[.readSelectedText],
           readBinding.enabled,
           matches(keyCode: keyCode, flags: flags, combo: readBinding.combo)
        {
            let now = Date()
            if now.timeIntervalSince(lastReadTrigger) > 0.25 {
                lastReadTrigger = now
                handlers.readSelectedTriggered()
            }
            return true
        }

        return false
    }

    private func matches(keyCode: UInt16, flags: CGEventFlags, combo: KeyCombo) -> Bool {
        guard keyCode == combo.keyCode else {
            return false
        }

        let masked = flags.intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        let expected = CGEventFlags(combo.modifiers)
        return masked == expected
    }
}

private extension CGEventFlags {
    init(_ modifiers: ShortcutModifiers) {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        self = flags
    }
}
