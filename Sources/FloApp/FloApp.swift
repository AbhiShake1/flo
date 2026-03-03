import AppCore
import AppKit
import Features
import SwiftUI

@main
struct FloDesktopApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller: FloController

    @MainActor
    init() {
        _controller = StateObject(wrappedValue: FloController(environment: .live()))
    }

    var body: some Scene {
        WindowGroup("flo") {
            RootView(controller: controller)
                .task {
                    await controller.bootstrap()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        controller.refreshPermissions()
                    }
                }
        }

        MenuBarExtra("flo", systemImage: "waveform") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recorder: \(controller.recorderState.label)")
                if let statusMessage = controller.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Button("Refresh Permissions") {
                    controller.refreshPermissions()
                }

                if let updateURL = controller.manualUpdateURL {
                    Button("Check for Updates") {
                        NSWorkspace.shared.open(updateURL)
                    }
                }

                if controller.isAuthenticated {
                    Button("Logout") {
                        Task {
                            await controller.logout()
                        }
                    }
                } else {
                    if controller.authProviderDisplayName == "Gemini" {
                        Text("Open flo window to save Gemini API key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Login with OpenAI") {
                            Task {
                                await controller.login()
                            }
                        }
                        .disabled(!controller.canAttemptLogin)
                    }
                }
            }
            .padding()
            .frame(width: 320)
        }
    }
}

private enum AppFlowStage: Int, CaseIterable {
    case login
    case permissions
    case settings

    var title: String {
        switch self {
        case .login:
            return "Login"
        case .permissions:
            return "Permissions"
        case .settings:
            return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .login:
            return "person.crop.circle.badge.checkmark"
        case .permissions:
            return "lock.shield"
        case .settings:
            return "slider.horizontal.3"
        }
    }
}

private enum FloTheme {
    static let accent = Color(red: 0.20, green: 0.64, blue: 0.92)
    static let accentSoft = Color(red: 0.31, green: 0.85, blue: 0.78)
    static let success = Color(red: 0.18, green: 0.74, blue: 0.48)
    static let warning = Color(red: 0.95, green: 0.67, blue: 0.25)
    static let danger = Color(red: 0.91, green: 0.35, blue: 0.35)
    static let backgroundTop = Color(red: 0.04, green: 0.07, blue: 0.12)
    static let backgroundBottom = Color(red: 0.02, green: 0.03, blue: 0.06)
}

private struct RootView: View {
    @ObservedObject var controller: FloController

    private var currentStage: AppFlowStage {
        if !controller.isAuthenticated {
            return .login
        }
        if !controller.missingPermissions.isEmpty {
            return .permissions
        }
        return .settings
    }

    var body: some View {
        ZStack {
            AppBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    HeroPanel(controller: controller)
                    FlowProgress(currentStage: currentStage)

                    Group {
                        switch currentStage {
                        case .login:
                            LoginStageView(controller: controller)
                        case .permissions:
                            PermissionStageView(controller: controller)
                        case .settings:
                            SettingsStageView(controller: controller)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeInOut(duration: 0.25), value: currentStage)
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 28)
                .frame(maxWidth: 1_050)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(FloTheme.accent)
        .frame(minWidth: 940, minHeight: 720)
    }
}

private struct AppBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [FloTheme.backgroundTop, FloTheme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(FloTheme.accent.opacity(0.22))
                .frame(width: 420, height: 420)
                .blur(radius: 130)
                .offset(x: -330, y: -220)

            Circle()
                .fill(FloTheme.accentSoft.opacity(0.2))
                .frame(width: 360, height: 360)
                .blur(radius: 120)
                .offset(x: 340, y: -180)
        }
        .ignoresSafeArea()
    }
}

private struct HeroPanel: View {
    @ObservedObject var controller: FloController

    var body: some View {
        CardContainer {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("flo")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Voice control for dictation and read-aloud, powered by \(controller.authProviderDisplayName).")
                        .foregroundStyle(Color.white.opacity(0.78))
                        .font(.system(size: 15, weight: .medium))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    StatusChip(
                        text: controller.recorderState.label,
                        color: recorderStateColor
                    )

                    if controller.isAuthenticated {
                        StatusChip(text: "Connected", color: FloTheme.success)
                    } else {
                        StatusChip(text: "Sign in required", color: FloTheme.warning)
                    }
                }
            }
        }
    }

    private var recorderStateColor: Color {
        switch controller.recorderState {
        case .error:
            return FloTheme.danger
        case .listening, .transcribing, .injecting, .speaking:
            return FloTheme.accentSoft
        case .idle:
            return FloTheme.accent
        }
    }
}

private struct FlowProgress: View {
    let currentStage: AppFlowStage

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppFlowStage.allCases, id: \.self) { stage in
                let isCurrent = stage == currentStage
                let isCompleted = stage.rawValue < currentStage.rawValue

                HStack(spacing: 8) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : stage.icon)
                        .font(.system(size: 13, weight: .semibold))
                    Text(stage.title)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(isCurrent || isCompleted ? .white : Color.white.opacity(0.65))
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            isCurrent
                                ? FloTheme.accent.opacity(0.38)
                                : isCompleted
                                    ? FloTheme.success.opacity(0.28)
                                    : Color.white.opacity(0.08)
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(isCurrent ? 0.25 : 0.12), lineWidth: 1)
                )
            }
        }
    }
}

private struct LoginStageView: View {
    @ObservedObject var controller: FloController
    @State private var providerCredentialDraft = ""

    private var usesGeminiProvider: Bool {
        controller.authProviderDisplayName == "Gemini"
    }

    private var isAuthenticating: Bool {
        if case .authenticating = controller.authState {
            return true
        }
        return false
    }

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text(usesGeminiProvider ? "Configure Gemini API Key" : "Login with OpenAI")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .foregroundStyle(Color.white.opacity(0.8))
                    .font(.system(size: 14, weight: .medium))

                if let blocker = controller.oauthBlockerMessage {
                    InlineNotice(text: blocker, tone: .error)
                        .accessibilityLabel("OAuth blocker")
                }

                switch controller.authState {
                case .authenticating:
                    InlineNotice(text: "Opening browser and waiting for OAuth callback...", tone: .info)
                case .authError(let message):
                    InlineNotice(text: message, tone: .error)
                case .loggedOut, .loggedIn:
                    EmptyView()
                }

                if usesGeminiProvider {
                    VStack(alignment: .leading, spacing: 10) {
                        SecureField("Gemini API key", text: $providerCredentialDraft)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Gemini API key")

                        HStack(spacing: 8) {
                            Button("Save API Key") {
                                controller.saveProviderCredential(providerCredentialDraft)
                                providerCredentialDraft = ""
                            }
                            .buttonStyle(PrimaryActionButtonStyle())
                            .disabled(providerCredentialDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            if controller.canRemoveSavedProviderCredential {
                                Button("Remove Saved Key") {
                                    Task {
                                        await controller.removeSavedProviderCredential()
                                    }
                                }
                                .buttonStyle(SecondaryActionButtonStyle())
                            }
                        }

                        if let sourceLabel = controller.providerCredentialSourceLabel {
                            Text(sourceLabel)
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.65))
                        }

                        Text("Optional fallback: set FLO_GEMINI_API_KEY in .env.local.")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.62))
                    }
                } else {
                    Button {
                        Task {
                            await controller.login()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if isAuthenticating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "link.badge.plus")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            Text("Login with OpenAI")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(!controller.canAttemptLogin || isAuthenticating)
                    .accessibilityLabel("Login with OpenAI")
                }
            }
        }
    }

    private var subtitle: String {
        if usesGeminiProvider {
            return "Gemini mode uses API key authentication (no ChatGPT OAuth). Save your key in-app or use .env.local."
        }
        return "Sign in to continue. After login, flo will guide you through required permissions before opening settings."
    }
}

private struct PermissionStageView: View {
    @ObservedObject var controller: FloController
    @State private var hasAutoPrompted = false

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text("Grant Required Permissions")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("flo needs microphone, accessibility, and input monitoring access to run global shortcuts and insert text safely.")
                    .foregroundStyle(Color.white.opacity(0.8))
                    .font(.system(size: 14, weight: .medium))

                PermissionManagementPanel(controller: controller, showPrimaryPrompt: true)

                Text("If flo is not listed yet, launch the bundled `FloApp.app` once from Finder, then retry permission grant.")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.62))
            }
        }
        .onAppear {
            guard !hasAutoPrompted else {
                return
            }
            hasAutoPrompted = true
            Task {
                await controller.promptForRequiredPermissions()
            }
        }
    }
}

private struct SettingsStageView: View {
    @ObservedObject var controller: FloController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardContainer {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Settings")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Tune shortcuts, voice output, permissions, and history.")
                            .foregroundStyle(Color.white.opacity(0.8))
                    }

                    Spacer()

                    Button("Logout") {
                        Task {
                            await controller.logout()
                        }
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .accessibilityLabel("Logout")
                }
            }

            if let statusMessage = controller.statusMessage {
                InlineNotice(text: statusMessage, tone: .info)
            }

            if !controller.onboardingHotkeyConfirmed {
                CardContainer {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Confirm Hotkey Setup")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("Review your hotkeys once, then mark setup as complete.")
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.75))

                        Button("Confirm hotkeys") {
                            controller.completeHotkeyConfirmation()
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        .accessibilityLabel("Confirm hotkeys")
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        CardContainer {
                            PermissionManagementPanel(controller: controller, showPrimaryPrompt: false)
                        }
                        CardContainer {
                            VoiceConfigurationSection(controller: controller)
                        }
                        CardContainer {
                            DictationStyleConfigurationSection(controller: controller)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    VStack(spacing: 16) {
                        CardContainer {
                            ShortcutConfigurationSection(controller: controller)
                        }
                        CardContainer {
                            UtilityActionsSection(controller: controller)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }

                VStack(spacing: 16) {
                    CardContainer {
                        PermissionManagementPanel(controller: controller, showPrimaryPrompt: false)
                    }
                    CardContainer {
                        ShortcutConfigurationSection(controller: controller)
                    }
                    CardContainer {
                        VoiceConfigurationSection(controller: controller)
                    }
                    CardContainer {
                        DictationStyleConfigurationSection(controller: controller)
                    }
                    CardContainer {
                        UtilityActionsSection(controller: controller)
                    }
                }
            }

            CardContainer {
                HistorySection(entries: Array(controller.historyEntries.prefix(30)))
            }
        }
    }
}

private struct PermissionManagementPanel: View {
    @ObservedObject var controller: FloController
    let showPrimaryPrompt: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Permissions")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                StatusChip(
                    text: "\(controller.missingPermissions.count) pending",
                    color: controller.missingPermissions.isEmpty ? FloTheme.success : FloTheme.warning
                )
            }

            ForEach(PermissionKind.allCases, id: \.self) { permission in
                PermissionControlRow(
                    title: permissionTitle(permission),
                    subtitle: permissionSubtitle(permission),
                    state: permissionState(permission),
                    action: {
                        Task {
                            await controller.requestPermission(permission)
                        }
                    }
                )
            }

            HStack(spacing: 8) {
                if showPrimaryPrompt {
                    Button("Prompt Required Permissions") {
                        Task {
                            await controller.promptForRequiredPermissions()
                        }
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(controller.missingPermissions.isEmpty)
                }

                Button("Refresh Status") {
                    controller.refreshPermissions()
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }
        }
    }

    private func permissionTitle(_ permission: PermissionKind) -> String {
        switch permission {
        case .microphone:
            return "Microphone"
        case .accessibility:
            return "Accessibility"
        case .inputMonitoring:
            return "Input Monitoring"
        }
    }

    private func permissionSubtitle(_ permission: PermissionKind) -> String {
        switch permission {
        case .microphone:
            return "Capture dictation audio"
        case .accessibility:
            return "Insert transcript text"
        case .inputMonitoring:
            return "Listen for global shortcuts"
        }
    }

    private func permissionState(_ permission: PermissionKind) -> PermissionState {
        switch permission {
        case .microphone:
            return controller.permissionStatus.microphone
        case .accessibility:
            return controller.permissionStatus.accessibility
        case .inputMonitoring:
            return controller.permissionStatus.inputMonitoring
        }
    }
}

private struct PermissionControlRow: View {
    let title: String
    let subtitle: String
    let state: PermissionState
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.62))
            }

            Spacer()

            StatusChip(text: stateText, color: stateColor)

            if state != .granted {
                Button("Grant") {
                    action()
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .accessibilityLabel("Grant \(title) permission")
            }
        }
        .padding(.vertical, 6)
    }

    private var stateText: String {
        switch state {
        case .granted:
            return "Granted"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Determined"
        }
    }

    private var stateColor: Color {
        switch state {
        case .granted:
            return FloTheme.success
        case .denied:
            return FloTheme.danger
        case .notDetermined:
            return FloTheme.warning
        }
    }
}

private struct UtilityActionsSection: View {
    @ObservedObject var controller: FloController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System")
                .font(.headline)
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                Button("Refresh Permissions") {
                    controller.refreshPermissions()
                }
                .buttonStyle(SecondaryActionButtonStyle())

                Button("Clear History") {
                    controller.clearHistory()
                }
                .buttonStyle(SecondaryActionButtonStyle())

                if let updateURL = controller.manualUpdateURL {
                    Button("Check for Updates") {
                        NSWorkspace.shared.open(updateURL)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }
            }

            Toggle(isOn: liveDictationBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live typing while speaking")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Incrementally types partial transcript during dictation.")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.68))
                }
            }
            .toggleStyle(.switch)

            if controller.recorderState == .listening && !controller.liveTranscriptPreview.isEmpty {
                Text(controller.liveTranscriptPreview)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(2)
            }

            Text("Hotkeys active: \(controller.hotkeysEnabled ? "Yes" : "No")")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.68))
        }
    }

    private var liveDictationBinding: Binding<Bool> {
        Binding(
            get: { controller.liveDictationEnabled },
            set: { controller.setLiveDictationEnabled($0) }
        )
    }
}

private struct HistorySection: View {
    let entries: [HistoryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Activity")
                .font(.headline)
                .foregroundStyle(.white)

            if entries.isEmpty {
                Text("No history yet.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.68))
            } else {
                ForEach(entries, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.kind == .dictation ? "Dictation" : "Read Aloud")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            Text(entry.timestamp, style: .time)
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.6))
                        }

                        Text(entry.inputText)
                            .lineLimit(2)
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.82))

                        if let latencyMs = entry.latencyMs {
                            Text("Latency: \(latencyMs) ms")
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.64))
                        }

                        if let requestID = entry.requestID {
                            Text("Request: \(requestID)")
                                .font(.caption2)
                                .foregroundStyle(Color.white.opacity(0.6))
                        }

                        if let errorMessage = entry.errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(FloTheme.danger)
                        } else {
                            Text(entry.success ? "Success" : "Failed")
                                .font(.caption)
                                .foregroundStyle(entry.success ? FloTheme.success : FloTheme.warning)
                        }
                    }
                    .padding(.vertical, 4)

                    if entry.id != entries.last?.id {
                        Divider()
                            .overlay(Color.white.opacity(0.12))
                    }
                }
            }
        }
    }
}

private struct ShortcutConfigurationSection: View {
    @ObservedObject var controller: FloController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hotkeys")
                .font(.headline)
                .foregroundStyle(.white)

            ShortcutPickerRow(
                title: "Dictation Hold",
                action: .dictationHold,
                controller: controller
            )

            ShortcutPickerRow(
                title: "Read Selected Text",
                action: .readSelectedText,
                controller: controller
            )

            Text("Custom shortcut: use key labels like `A`, `SPACE`, `TAB`, `ESC`.")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.65))

            CustomShortcutEditor(
                title: "Custom Dictation",
                action: .dictationHold,
                controller: controller
            )

            CustomShortcutEditor(
                title: "Custom Read-Aloud",
                action: .readSelectedText,
                controller: controller
            )

            Button("Reset to defaults") {
                controller.resetShortcutsToDefault()
            }
            .buttonStyle(SecondaryActionButtonStyle())
        }
    }
}

private struct ShortcutPickerRow: View {
    let title: String
    let action: ShortcutAction
    @ObservedObject var controller: FloController

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.white)
            Spacer()
            Picker(title, selection: binding) {
                ForEach(ShortcutPresetCatalog.all, id: \.id) { preset in
                    Text(preset.combo.humanReadable)
                        .tag(preset.id)
                }
            }
            .labelsHidden()
            .frame(width: 220)
            .accessibilityLabel("\(title) picker")
        }
    }

    private var binding: Binding<String> {
        Binding(
            get: {
                controller.shortcutBindings.first(where: { $0.action == action })?.combo.humanReadable
                    ?? ShortcutPresetCatalog.defaults(for: action).humanReadable
            },
            set: { selectedID in
                guard let preset = ShortcutPresetCatalog.all.first(where: { $0.id == selectedID }) else {
                    return
                }
                controller.updateShortcut(action: action, combo: preset.combo)
            }
        )
    }
}

private struct CustomShortcutEditor: View {
    let title: String
    let action: ShortcutAction
    @ObservedObject var controller: FloController

    @State private var keyInput = ""
    @State private var useCommand = false
    @State private var useOption = true
    @State private var useShift = false
    @State private var useControl = false
    @State private var localMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)

            HStack(spacing: 8) {
                TextField("Key", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .accessibilityLabel("\(title) key input")

                Toggle("Cmd", isOn: $useCommand)
                    .toggleStyle(.checkbox)
                Toggle("Opt", isOn: $useOption)
                    .toggleStyle(.checkbox)
                Toggle("Shift", isOn: $useShift)
                    .toggleStyle(.checkbox)
                Toggle("Ctrl", isOn: $useControl)
                    .toggleStyle(.checkbox)

                Button("Apply") {
                    applyCustomShortcut()
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .accessibilityLabel("Apply \(title)")
            }

            if let localMessage {
                Text(localMessage)
                    .font(.caption)
                    .foregroundStyle(FloTheme.danger)
            }
        }
    }

    private func applyCustomShortcut() {
        var modifiers: ShortcutModifiers = []
        if useCommand { modifiers.insert(.command) }
        if useOption { modifiers.insert(.option) }
        if useShift { modifiers.insert(.shift) }
        if useControl { modifiers.insert(.control) }

        guard let combo = KeyCodeMapper.combo(for: keyInput, modifiers: modifiers) else {
            localMessage = "Unsupported key label."
            return
        }

        localMessage = nil
        controller.updateShortcut(action: action, combo: combo)
        controller.completeHotkeyConfirmation()
    }
}

private struct VoiceConfigurationSection: View {
    @ObservedObject var controller: FloController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Voice")
                .font(.headline)
                .foregroundStyle(.white)

            HStack {
                Text("Voice preset")
                    .foregroundStyle(.white)
                Spacer()
                Picker("Voice", selection: voiceBinding) {
                    ForEach(controller.supportedVoices, id: \.self) { voice in
                        Text(voice.capitalized)
                            .tag(voice)
                    }
                }
                .frame(width: 220)
                .labelsHidden()
                .accessibilityLabel("Voice preset")

                Button(controller.isVoicePreviewInProgress ? "Playing..." : "Preview voice") {
                    Task {
                        await controller.previewCurrentVoice()
                    }
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .disabled(!canPreviewVoice)
                .accessibilityLabel("Preview selected voice")
            }

            HStack {
                Text("Speed: \(String(format: "%.2f", controller.voicePreferences.speed))x")
                    .foregroundStyle(.white)
                Slider(
                    value: speedBinding,
                    in: VoiceCatalog.speedRange,
                    step: 0.05
                )
                .accessibilityLabel("Voice speed")
            }

            Text("Preview uses the selected voice preset and speed.")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.66))
        }
    }

    private var voiceBinding: Binding<String> {
        Binding(
            get: { controller.voicePreferences.voice },
            set: { newVoice in
                guard controller.voicePreferences.voice != newVoice else {
                    return
                }
                controller.updateVoice(newVoice)
                Task {
                    await controller.previewCurrentVoice()
                }
            }
        )
    }

    private var speedBinding: Binding<Double> {
        Binding(
            get: { controller.voicePreferences.speed },
            set: { controller.updateVoiceSpeed($0) }
        )
    }

    private var canPreviewVoice: Bool {
        controller.isAuthenticated &&
            !controller.isVoicePreviewInProgress &&
            controller.recorderState == .idle
    }
}

private struct DictationStyleConfigurationSection: View {
    @ObservedObject var controller: FloController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dictation Rewrite")
                .font(.headline)
                .foregroundStyle(.white)

            Toggle(isOn: rewriteEnabledBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rewrite rough speech")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Converts natural speech into polished, formatted text.")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.68))
                }
            }
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 6) {
                Text("One-click presets")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DictationRewritePreset.allCases, id: \.self) { preset in
                            Button(preset.displayName) {
                                controller.applyDictationRewritePreset(preset)
                            }
                            .buttonStyle(SecondaryActionButtonStyle())
                            .accessibilityLabel("Apply \(preset.displayName) preset")
                        }
                    }
                }
            }

            HStack {
                Text("Live finalization")
                    .foregroundStyle(.white)
                Spacer()
                Picker("Live finalization mode", selection: liveFinalizationBinding) {
                    ForEach(DictationLiveFinalizationMode.allCases, id: \.self) { mode in
                        Text(mode.displayName)
                            .tag(mode)
                    }
                }
                .frame(width: 220)
                .labelsHidden()
            }

            HStack {
                Text("Base tone")
                    .foregroundStyle(.white)
                Spacer()
                Picker("Base tone", selection: baseToneBinding) {
                    ForEach(DictationBaseTone.allCases, id: \.self) { tone in
                        Text(tone.displayName)
                            .tag(tone)
                    }
                }
                .frame(width: 220)
                .labelsHidden()
            }

            DictationLevelPickerRow(
                title: "Warmth",
                selection: warmthBinding
            )
            DictationLevelPickerRow(
                title: "Enthusiasm",
                selection: enthusiasmBinding
            )
            DictationLevelPickerRow(
                title: "Headers & lists",
                selection: headersBinding
            )
            DictationLevelPickerRow(
                title: "Emoji",
                selection: emojiBinding
            )

            TextField(
                "Custom instructions (optional)",
                text: customInstructionsBinding,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...5)
            .accessibilityLabel("Dictation custom instructions")

            Text("Example: be pragmatic, concise, and use bullet points for actions.")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.66))

            Text("Append: keep live draft and add only missing tail. Replace: overwrite live draft with final rewritten output.")
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.58))
        }
    }

    private var rewriteEnabledBinding: Binding<Bool> {
        Binding(
            get: { controller.dictationRewritePreferences.rewriteEnabled },
            set: { controller.setDictationRewriteEnabled($0) }
        )
    }

    private var baseToneBinding: Binding<DictationBaseTone> {
        Binding(
            get: { controller.dictationRewritePreferences.baseTone },
            set: { controller.setDictationBaseTone($0) }
        )
    }

    private var liveFinalizationBinding: Binding<DictationLiveFinalizationMode> {
        Binding(
            get: { controller.dictationRewritePreferences.liveFinalizationMode },
            set: { controller.setDictationLiveFinalizationMode($0) }
        )
    }

    private var warmthBinding: Binding<DictationStyleLevel> {
        Binding(
            get: { controller.dictationRewritePreferences.warmth },
            set: { controller.setDictationWarmth($0) }
        )
    }

    private var enthusiasmBinding: Binding<DictationStyleLevel> {
        Binding(
            get: { controller.dictationRewritePreferences.enthusiasm },
            set: { controller.setDictationEnthusiasm($0) }
        )
    }

    private var headersBinding: Binding<DictationStyleLevel> {
        Binding(
            get: { controller.dictationRewritePreferences.headersAndLists },
            set: { controller.setDictationHeadersAndLists($0) }
        )
    }

    private var emojiBinding: Binding<DictationStyleLevel> {
        Binding(
            get: { controller.dictationRewritePreferences.emoji },
            set: { controller.setDictationEmoji($0) }
        )
    }

    private var customInstructionsBinding: Binding<String> {
        Binding(
            get: { controller.dictationRewritePreferences.customInstructions },
            set: { controller.setDictationCustomInstructions($0) }
        )
    }
}

private struct DictationLevelPickerRow: View {
    let title: String
    let selection: Binding<DictationStyleLevel>

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.white)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(DictationStyleLevel.allCases, id: \.self) { level in
                    Text(level.displayName)
                        .tag(level)
                }
            }
            .frame(width: 220)
            .labelsHidden()
        }
    }
}

private struct CardContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.27), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.22), radius: 26, x: 0, y: 14)
    }
}

private struct StatusChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.26))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(color.opacity(0.52), lineWidth: 1)
            )
    }
}

private enum NoticeTone {
    case info
    case error
}

private struct InlineNotice: View {
    let text: String
    let tone: NoticeTone

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tone == .error ? "exclamationmark.circle.fill" : "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.subheadline)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill((tone == .error ? FloTheme.danger : FloTheme.accent).opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder((tone == .error ? FloTheme.danger : FloTheme.accent).opacity(0.5), lineWidth: 1)
        )
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.7))
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [FloTheme.accent, FloTheme.accentSoft],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.55)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct SecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.white.opacity(isEnabled ? 0.96 : 0.65))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.19 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.55)
    }
}
