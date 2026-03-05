import AppCore
import AVFoundation
import ApplicationServices
import AppKit
import Foundation
import IOKit.hid

@MainActor
public final class MacPermissionsService: PermissionsService {
    public init() {}

    public func refreshStatus() -> PermissionStatus {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let microphone: PermissionState
        switch micStatus {
        case .authorized:
            microphone = .granted
        case .notDetermined:
            microphone = .notDetermined
        default:
            microphone = .denied
        }

        let accessibility: PermissionState = AXIsProcessTrusted() ? .granted : .denied
        let inputMonitoring: PermissionState = hasInputMonitoringPermission() ? .granted : .denied

        return PermissionStatus(
            microphone: microphone,
            accessibility: accessibility,
            inputMonitoring: inputMonitoring
        )
    }

    public func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func openSystemSettings(for permission: PermissionKind) {
        let targetURL: URL?
        switch permission {
        case .microphone:
            requestMicrophoneAccessPrompt()
            targetURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            requestAccessibilityPrompt()
            targetURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .inputMonitoring:
            requestInputMonitoringPrompt()
            targetURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        }

        if let targetURL {
            NSWorkspace.shared.open(targetURL)
        }
    }

    private func hasInputMonitoringPermission() -> Bool {
        if #available(macOS 10.15, *) {
            let hidAccess = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
            if hidAccess == kIOHIDAccessTypeGranted {
                return true
            }
            // Fallback check for environments where HID check can be unknown.
            return CGPreflightListenEventAccess()
        }

        let mask = (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, _, event, _ in
            Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: nil
        ) else {
            return false
        }

        CFMachPortInvalidate(tap)
        return true
    }

    private func requestMicrophoneAccessPrompt() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    private func requestAccessibilityPrompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func requestInputMonitoringPrompt() {
        if #available(macOS 10.15, *) {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            _ = CGRequestListenEventAccess()
        }
    }
}
