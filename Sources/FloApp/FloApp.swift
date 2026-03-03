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
                .containerBackground(.clear, for: .window)
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
    case history
    case voice

    var title: String {
        switch self {
        case .login:
            return "Login"
        case .permissions:
            return "Permissions"
        case .settings:
            return "Settings"
        case .history:
            return "History"
        case .voice:
            return "Voice"
        }
    }

    var subtitle: String {
        switch self {
        case .login:
            return "Account and API access"
        case .permissions:
            return "System permission management"
        case .settings:
            return "Shortcuts, dictation, and system controls"
        case .history:
            return "Session events and recent activity"
        case .voice:
            return "Immersive voice interaction"
        }
    }

    var icon: String {
        switch self {
        case .login:
            return "person.badge.key"
        case .permissions:
            return "checkmark.shield"
        case .settings:
            return "switch.2"
        case .history:
            return "clock.arrow.circlepath"
        case .voice:
            return "sparkles"
        }
    }
}

private enum FloTheme {
    static let accent = Color(red: 0.31, green: 0.56, blue: 0.94)
    static let accentSoft = Color(red: 0.43, green: 0.68, blue: 0.99)
    static let success = Color(red: 0.18, green: 0.74, blue: 0.48)
    static let warning = Color(red: 0.93, green: 0.70, blue: 0.30)
    static let danger = Color(red: 0.90, green: 0.37, blue: 0.38)
    static let backdropTint = Color.black.opacity(0.34)
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.66)
    static let sidebarFill = Color.black.opacity(0.24)
    static let workspaceFill = Color.black.opacity(0.16)
    static let sidebarSoftStroke = Color.white.opacity(0.08)
    static let sidebarRow = Color.white.opacity(0.03)
    static let sidebarRowHover = Color.white.opacity(0.08)
    static let sidebarRowActiveStart = Color.white.opacity(0.17)
    static let sidebarRowActiveEnd = Color.white.opacity(0.08)
}

private struct RootView: View {
    @ObservedObject var controller: FloController
    @State private var selectedStage: AppFlowStage = .login
    @State private var settingsSearchQuery = ""

    private var currentStage: AppFlowStage {
        if !controller.isAuthenticated {
            return .login
        }
        if !controller.missingPermissions.isEmpty {
            return .permissions
        }
        return .settings
    }

    private var availableStages: Set<AppFlowStage> {
        switch currentStage {
        case .login:
            return [.login]
        case .permissions:
            return [.login, .permissions]
        case .settings, .history, .voice:
            return Set(AppFlowStage.allCases)
        }
    }

    private var activeStage: AppFlowStage {
        availableStages.contains(selectedStage) ? selectedStage : currentStage
    }

    var body: some View {
        ZStack {
            AppBackdrop()

            HStack(spacing: 0) {
                SidebarSurface(
                    controller: controller,
                    currentStage: currentStage,
                    activeStage: activeStage,
                    availableStages: availableStages
                ) { stage in
                    selectedStage = stage
                }
                .frame(width: 304)
                .padding(.leading, 0)
                .padding(.trailing, 0)
                .padding(.vertical, 0)

                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 1)
                    .padding(.vertical, 16)

                WorkspaceSurface(
                    controller: controller,
                    activeStage: activeStage,
                    settingsSearchQuery: $settingsSearchQuery
                )
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
            }
        }
        .tint(FloTheme.accent)
        .frame(minWidth: 1_120, minHeight: 760)
        .onAppear {
            selectedStage = currentStage
        }
        .onChange(of: currentStage) { _, newStage in
            if !availableStages.contains(selectedStage) {
                selectedStage = newStage
            }
            if newStage != .settings {
                settingsSearchQuery = ""
            }
        }
    }
}

private struct AppBackdrop: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.07, blue: 0.11),
                    Color(red: 0.07, green: 0.08, blue: 0.12),
                    Color(red: 0.03, green: 0.04, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 24)

            RadialGradient(
                colors: [
                    Color(red: 0.17, green: 0.24, blue: 0.37).opacity(0.36),
                    .clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 620
            )
            .blendMode(.screen)
            .blur(radius: 48)

            RadialGradient(
                colors: [
                    Color(red: 0.15, green: 0.29, blue: 0.74).opacity(0.25),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 520
            )
            .blendMode(.screen)
            .blur(radius: 70)

            RadialGradient(
                colors: [
                    .clear,
                    Color.black.opacity(0.42)
                ],
                center: .center,
                startRadius: 180,
                endRadius: 820
            )

            BackdropGrain()
                .opacity(0.15)
        }
        .ignoresSafeArea()
    }
}

private struct BackdropGrain: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<1200 {
                let seed = Double(index) * 0.731
                let x = CGFloat(pseudoRandom(seed * 19.31)) * size.width
                let y = CGFloat(pseudoRandom(seed * 71.73)) * size.height
                let alpha = 0.018 + (pseudoRandom(seed * 2.9) * 0.04)
                let dotSize = CGFloat(0.5 + (pseudoRandom(seed * 11.6) * 0.9))
                let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha)))
            }
        }
    }
}

private struct SidebarSurface: View {
    @ObservedObject var controller: FloController
    let currentStage: AppFlowStage
    let activeStage: AppFlowStage
    let availableStages: Set<AppFlowStage>
    let onSelectStage: (AppFlowStage) -> Void
    @State private var hoveredStage: AppFlowStage?

    private var completionRatio: Double {
        guard !AppFlowStage.allCases.isEmpty else {
            return 0
        }
        return Double(availableStages.count) / Double(AppFlowStage.allCases.count)
    }

    private var unlockedSummary: String {
        "\(availableStages.count) of \(AppFlowStage.allCases.count) sections available"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [FloTheme.accent, FloTheme.accentSoft],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 30, height: 30)
                        Image(systemName: "waveform.and.mic")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.95))
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("flo")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(FloTheme.textPrimary)
                        Text("Voice workspace")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FloTheme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 8) {
                Text("Navigation")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FloTheme.textSecondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 10)

                ForEach(AppFlowStage.allCases, id: \.self) { stage in
                    let enabled = availableStages.contains(stage)
                    Button {
                        onSelectStage(stage)
                    } label: {
                        SidebarStageRow(
                            stage: stage,
                            isActive: stage == activeStage,
                            isEnabled: enabled
                        )
                    }
                    .buttonStyle(
                        SidebarStageButtonStyle(
                            isActive: stage == activeStage,
                            isEnabled: enabled,
                            isHovered: hoveredStage == stage
                        )
                    )
                    .onHover { isHovering in
                        hoveredStage = isHovering ? stage : nil
                    }
                    .disabled(!enabled)
                    .accessibilityLabel(stage.title)
                    .accessibilityHint(enabled ? stage.subtitle : "Locked until \(currentStage.title) is complete")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Workflow")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FloTheme.textSecondary)
                    .textCase(.uppercase)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(recorderStateColor(controller.recorderState))
                            .frame(width: 8, height: 8)
                        Text(controller.recorderState.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FloTheme.textPrimary)
                        Spacer(minLength: 0)
                        Text(controller.isAuthenticated ? "Connected" : "Sign in")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(controller.isAuthenticated ? FloTheme.success : FloTheme.warning)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [FloTheme.accentSoft.opacity(0.95), FloTheme.accent.opacity(0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(geometry.size.width * completionRatio, 12))
                        }
                    }
                    .frame(height: 7)

                    Text(unlockedSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FloTheme.textSecondary)

                    Text("Required next: \(currentStage.title)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FloTheme.textSecondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(FloTheme.sidebarSoftStroke, lineWidth: 1)
            )

            Spacer(minLength: 0)

            if controller.isAuthenticated {
                Button("Logout") {
                    Task {
                        await controller.logout()
                    }
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct SidebarStageRow: View {
    let stage: AppFlowStage
    let isActive: Bool
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        isActive
                            ? FloTheme.accent.opacity(0.30)
                            : Color.white.opacity(isEnabled ? 0.07 : 0.03)
                    )
                    .frame(width: 28, height: 28)
                Image(systemName: stage.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isActive ? FloTheme.accentSoft : FloTheme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(stage.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FloTheme.textPrimary)
                Text(stage.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(FloTheme.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct WorkspaceSurface: View {
    @ObservedObject var controller: FloController
    let activeStage: AppFlowStage
    @Binding var settingsSearchQuery: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activeStage.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(FloTheme.textPrimary)
                    Text(activeStage.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(FloTheme.textSecondary)
                }
                Spacer()
                if activeStage == .settings {
                    ToolbarSearchField(text: $settingsSearchQuery)
                        .frame(width: 320)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()
                .overlay(Color.white.opacity(0.14))

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        switch activeStage {
                        case .login:
                            LoginStageView(controller: controller)
                        case .permissions:
                            PermissionStageView(controller: controller)
                        case .settings:
                            SettingsStageView(controller: controller, searchQuery: $settingsSearchQuery)
                        case .history:
                            HistoryStageView(controller: controller)
                        case .voice:
                            VoiceStudioStageView(controller: controller)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeInOut(duration: 0.2), value: activeStage)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ToolbarSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FloTheme.textSecondary)

            TextField("Search settings", text: $text)
                .textFieldStyle(.plain)
                .foregroundStyle(FloTheme.textPrimary)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(FloTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct SidebarStageButtonStyle: ButtonStyle {
    let isActive: Bool
    let isEnabled: Bool
    let isHovered: Bool
    @Environment(\.isEnabled) private var environmentEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(backgroundFill(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1)
            )
            .shadow(
                color: isActive ? FloTheme.accent.opacity(0.22) : Color.clear,
                radius: isActive ? 12 : 0,
                x: 0,
                y: isActive ? 8 : 0
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity((isEnabled && environmentEnabled) ? 1 : 0.52)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.16), value: isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func backgroundFill(isPressed: Bool) -> AnyShapeStyle {
        if isActive {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        FloTheme.sidebarRowActiveStart.opacity(isPressed ? 0.90 : 1),
                        FloTheme.sidebarRowActiveEnd.opacity(isPressed ? 0.90 : 1)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        if isPressed {
            return AnyShapeStyle(FloTheme.sidebarRowHover.opacity(0.86))
        }
        if isHovered {
            return AnyShapeStyle(FloTheme.sidebarRowHover)
        }
        return AnyShapeStyle(FloTheme.sidebarRow)
    }

    private var strokeColor: Color {
        if isActive {
            return FloTheme.accent.opacity(0.45)
        }
        if isHovered {
            return Color.white.opacity(0.18)
        }
        return FloTheme.sidebarSoftStroke
    }
}

private func recorderStateColor(_ state: RecorderState) -> Color {
    switch state {
    case .error:
        return FloTheme.danger
    case .listening, .transcribing, .injecting, .speaking:
        return FloTheme.accentSoft
    case .idle:
        return FloTheme.accent
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
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(FloTheme.textPrimary)

                Text(subtitle)
                    .foregroundStyle(FloTheme.textSecondary)
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
                                .foregroundStyle(FloTheme.textSecondary)
                        }

                        Text("Optional fallback: set FLO_GEMINI_API_KEY in .env.local.")
                            .font(.caption)
                            .foregroundStyle(FloTheme.textSecondary)
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
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(FloTheme.textPrimary)

                Text("flo needs microphone, accessibility, and input monitoring access to run global shortcuts and insert text safely.")
                    .foregroundStyle(FloTheme.textSecondary)
                    .font(.system(size: 14, weight: .medium))

                PermissionManagementPanel(controller: controller, showPrimaryPrompt: true)

                Text("If flo is not listed yet, launch the bundled `FloApp.app` once from Finder, then retry permission grant.")
                    .font(.caption)
                    .foregroundStyle(FloTheme.textSecondary)
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
    @Binding var searchQuery: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardContainer {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Workspace Settings")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(FloTheme.textPrimary)
                        Text("Tune shortcuts, voice output, permissions, and core system controls.")
                            .foregroundStyle(FloTheme.textSecondary)
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

            if showOnboardingCard {
                CardContainer {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Confirm Hotkey Setup")
                            .font(.headline)
                            .foregroundStyle(FloTheme.textPrimary)

                        Text("Review your hotkeys once, then mark setup as complete.")
                            .font(.subheadline)
                            .foregroundStyle(FloTheme.textSecondary)

                        Button("Confirm hotkeys") {
                            controller.completeHotkeyConfirmation()
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                        .accessibilityLabel("Confirm hotkeys")
                    }
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 360), spacing: 16, alignment: .top)],
                alignment: .leading,
                spacing: 16
            ) {
                if showPermissionsSection {
                    CardContainer {
                        PermissionManagementPanel(controller: controller, showPrimaryPrompt: false)
                    }
                }
                if showHotkeysSection {
                    CardContainer {
                        ShortcutConfigurationSection(controller: controller)
                    }
                }
                if showDictationSection {
                    CardContainer {
                        DictationStyleConfigurationSection(controller: controller)
                    }
                }
                if showSystemSection {
                    CardContainer {
                        UtilityActionsSection(controller: controller)
                    }
                }
            }

            if showEmptyState {
                CardContainer {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No settings match")
                            .font(.headline)
                            .foregroundStyle(FloTheme.textPrimary)
                        Text("Try a different search keyword or clear the filter.")
                            .font(.subheadline)
                            .foregroundStyle(FloTheme.textSecondary)
                        Button("Clear search") {
                            searchQuery = ""
                        }
                        .buttonStyle(SecondaryActionButtonStyle())
                    }
                }
            }

            if showVoiceRedirectSection {
                CardContainer {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(FloTheme.accentSoft)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Voice controls moved to Voice tab")
                                .font(.headline)
                                .foregroundStyle(FloTheme.textPrimary)
                            Text("Use the sidebar Voice tab to switch voices with arrow controls and immersive live orb feedback.")
                                .font(.subheadline)
                                .foregroundStyle(FloTheme.textSecondary)
                        }
                    }
                }
            }

            if showHistoryRedirectSection {
                CardContainer {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(FloTheme.accentSoft)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("History moved to History tab")
                                .font(.headline)
                                .foregroundStyle(FloTheme.textPrimary)
                            Text("Use the sidebar History tab for recent activity, latency details, and history clearing.")
                                .font(.subheadline)
                                .foregroundStyle(FloTheme.textSecondary)
                        }
                    }
                }
            }

        }
    }

    private var searchTerms: [String] {
        searchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ")
            .map(String.init)
    }

    private func matches(_ keywords: [String]) -> Bool {
        guard !searchTerms.isEmpty else {
            return true
        }
        let haystack = keywords.joined(separator: " ").lowercased()
        return searchTerms.allSatisfy { haystack.contains($0) }
    }

    private var showPermissionsSection: Bool {
        matches(["permissions", "microphone", "accessibility", "input monitoring", "grant"])
    }

    private var showHotkeysSection: Bool {
        matches(["shortcut", "hotkey", "dictation hold", "read selected", "custom key", "keyboard"])
    }

    private var showDictationSection: Bool {
        matches(["dictation", "rewrite", "tone", "warmth", "enthusiasm", "emoji", "instructions"])
    }

    private var showSystemSection: Bool {
        matches(["system", "live typing", "refresh", "updates"])
    }

    private var showVoiceRedirectSection: Bool {
        matches(["voice", "audio", "preview", "speaker", "orb"])
    }

    private var showHistoryRedirectSection: Bool {
        matches(["history", "activity", "latency", "request", "success", "failed"])
    }

    private var showOnboardingCard: Bool {
        !controller.onboardingHotkeyConfirmed && matches(["hotkey", "onboarding", "confirm", "setup"])
    }

    private var showEmptyState: Bool {
        !searchTerms.isEmpty &&
            !showPermissionsSection &&
            !showHotkeysSection &&
            !showDictationSection &&
            !showSystemSection &&
            !showVoiceRedirectSection &&
            !showHistoryRedirectSection &&
            !showOnboardingCard
    }
}

private struct HistoryStageView: View {
    @ObservedObject var controller: FloController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardContainer {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Session History")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(FloTheme.textPrimary)
                        Text("Review recent dictation/read-aloud events, latency, and request identifiers.")
                            .foregroundStyle(FloTheme.textSecondary)
                    }

                    Spacer()

                    Button("Clear History") {
                        controller.clearHistory()
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .accessibilityLabel("Clear History")
                }
            }

            if let statusMessage = controller.statusMessage {
                InlineNotice(text: statusMessage, tone: .info)
            }

            CardContainer {
                HistorySection(entries: Array(controller.historyEntries.prefix(120)))
            }
        }
    }
}

private struct VoiceStudioStageView: View {
    @ObservedObject var controller: FloController

    private var voices: [String] {
        controller.supportedVoices
    }

    private var selectedVoiceIndex: Int {
        guard !voices.isEmpty else {
            return 0
        }
        return voices.firstIndex(of: controller.voicePreferences.voice) ?? 0
    }

    private var activityLevel: Double {
        min(1, max(Double(controller.latestAudioLevel), controller.isVoicePreviewInProgress ? 0.58 : 0.12))
    }

    private var currentVoiceName: String {
        guard !voices.isEmpty else {
            return "default"
        }
        return voices[selectedVoiceIndex]
    }

    private var orbPalette: VoiceOrbPalette {
        VoiceOrbPalette.forVoice(currentVoiceName)
    }

    private var canPreviewVoice: Bool {
        controller.isAuthenticated &&
            !controller.isVoicePreviewInProgress &&
            controller.recorderState == .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 22) {
                AtmosphericVoiceOrb(
                    activityLevel: activityLevel,
                    isActive: controller.isVoicePreviewInProgress || controller.recorderState == .listening,
                    palette: orbPalette
                )
                .frame(maxWidth: .infinity)

                HStack(spacing: 14) {
                    Button {
                        shiftVoice(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(OrbDirectionButtonStyle(accentColor: orbPalette.coreAccent))
                    .disabled(voices.count < 2 || !controller.isAuthenticated || controller.isVoicePreviewInProgress)
                    .accessibilityLabel("Previous voice")

                    VStack(spacing: 4) {
                        Text(voices.isEmpty ? "No voices available" : voices[selectedVoiceIndex].capitalized)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(FloTheme.textPrimary)
                        Text(voices.isEmpty ? "" : "Voice \(selectedVoiceIndex + 1) of \(voices.count)")
                            .font(.caption)
                            .foregroundStyle(FloTheme.textSecondary)
                    }
                    .frame(minWidth: 260)

                    Button {
                        shiftVoice(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(OrbDirectionButtonStyle(accentColor: orbPalette.coreAccent))
                    .disabled(voices.count < 2 || !controller.isAuthenticated || controller.isVoicePreviewInProgress)
                    .accessibilityLabel("Next voice")
                }

                GeometryReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(voices.enumerated()), id: \.offset) { index, voice in
                                Button(voice.capitalized) {
                                    applyVoice(at: index, previewAfterSelection: true)
                                }
                                .buttonStyle(
                                    VoiceChipButtonStyle(
                                        isSelected: index == selectedVoiceIndex,
                                        accentColor: orbPalette.coreAccent
                                    )
                                )
                                .disabled(!controller.isAuthenticated || controller.isVoicePreviewInProgress)
                            }
                        }
                        .padding(.horizontal, 2)
                        .frame(minWidth: proxy.size.width, alignment: .center)
                    }
                }
                .frame(maxWidth: 620)
                .frame(height: 34)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            SectionDivider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Interaction")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FloTheme.textSecondary)

                HStack(spacing: 10) {
                    Text("Speed \(String(format: "%.2f", controller.voicePreferences.speed))x")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FloTheme.textPrimary)
                        .frame(width: 138, alignment: .leading)
                    Slider(value: speedBinding, in: VoiceCatalog.speedRange, step: 0.05)
                        .disabled(!controller.isAuthenticated)
                        .accessibilityLabel("Voice speed")
                    Button(controller.isVoicePreviewInProgress ? "Speaking..." : "Speak sample") {
                        Task {
                            await controller.previewCurrentVoice()
                        }
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(!canPreviewVoice)
                }

                Text("Use left and right arrows to cycle voices. Each switch triggers spoken preview for immediate feedback.")
                    .font(.caption)
                    .foregroundStyle(FloTheme.textSecondary)
            }

            if let statusMessage = controller.statusMessage, !statusMessage.isEmpty {
                InlineNotice(text: statusMessage, tone: .info)
            }
        }
        .onAppear {
            guard !voices.isEmpty else {
                return
            }
            if !voices.contains(controller.voicePreferences.voice) {
                controller.updateVoice(voices[0])
            }
        }
    }

    private var speedBinding: Binding<Double> {
        Binding(
            get: { controller.voicePreferences.speed },
            set: { controller.updateVoiceSpeed($0) }
        )
    }

    private func shiftVoice(by step: Int) {
        guard !voices.isEmpty else {
            return
        }
        var next = selectedVoiceIndex + step
        if next < 0 {
            next = voices.count - 1
        } else if next >= voices.count {
            next = 0
        }
        applyVoice(at: next, previewAfterSelection: true)
    }

    private func applyVoice(at index: Int, previewAfterSelection: Bool) {
        guard voices.indices.contains(index) else {
            return
        }
        let voice = voices[index]
        if controller.voicePreferences.voice != voice {
            controller.updateVoice(voice)
        }
        guard previewAfterSelection else {
            return
        }
        Task {
            await controller.previewCurrentVoice()
        }
    }
}

private struct VoiceOrbPalette {
    let coreCenter: Color
    let coreSecondary: Color
    let coreAccent: Color
    let edgeTone: Color
    let haloTone: Color
    let rippleTone: Color
    let mistPrimary: Color
    let mistSecondary: Color

    static func forVoice(_ voiceName: String) -> VoiceOrbPalette {
        let normalized = voiceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.contains("brit") || normalized.contains("uk") || normalized.contains("england") {
            return palette(
                center: Color(red: 0.96, green: 0.97, blue: 1.0),
                secondary: Color(red: 0.78, green: 0.86, blue: 1.0),
                accent: Color(red: 0.37, green: 0.57, blue: 0.99),
                edge: Color(red: 0.66, green: 0.54, blue: 0.95),
                halo: Color(red: 0.52, green: 0.65, blue: 1.0),
                ripple: Color(red: 0.70, green: 0.82, blue: 1.0),
                mistA: Color(red: 0.72, green: 0.86, blue: 1.0),
                mistB: Color(red: 0.63, green: 0.56, blue: 0.95)
            )
        }
        if normalized.contains("austr") || normalized.contains("au") {
            return palette(
                center: Color(red: 0.98, green: 0.97, blue: 0.93),
                secondary: Color(red: 0.82, green: 0.90, blue: 1.0),
                accent: Color(red: 0.27, green: 0.64, blue: 0.98),
                edge: Color(red: 0.94, green: 0.64, blue: 0.33),
                halo: Color(red: 0.51, green: 0.76, blue: 1.0),
                ripple: Color(red: 0.66, green: 0.84, blue: 1.0),
                mistA: Color(red: 0.74, green: 0.89, blue: 1.0),
                mistB: Color(red: 0.95, green: 0.67, blue: 0.39)
            )
        }
        if normalized.contains("india") || normalized.contains("hindi") || normalized.contains("nepal") {
            return palette(
                center: Color(red: 1.0, green: 0.97, blue: 0.93),
                secondary: Color(red: 0.81, green: 0.91, blue: 1.0),
                accent: Color(red: 0.98, green: 0.58, blue: 0.24),
                edge: Color(red: 0.26, green: 0.63, blue: 0.97),
                halo: Color(red: 0.68, green: 0.77, blue: 1.0),
                ripple: Color(red: 0.99, green: 0.72, blue: 0.34),
                mistA: Color(red: 1.0, green: 0.76, blue: 0.43),
                mistB: Color(red: 0.36, green: 0.67, blue: 0.99)
            )
        }

        switch normalized {
        case "alloy":
            return palette(
                center: Color(red: 0.95, green: 0.98, blue: 1.0),
                secondary: Color(red: 0.81, green: 0.90, blue: 0.98),
                accent: Color(red: 0.37, green: 0.66, blue: 0.96),
                edge: Color(red: 0.57, green: 0.62, blue: 0.90),
                halo: Color(red: 0.44, green: 0.72, blue: 1.0),
                ripple: Color(red: 0.66, green: 0.86, blue: 1.0),
                mistA: Color(red: 0.73, green: 0.89, blue: 1.0),
                mistB: Color(red: 0.63, green: 0.73, blue: 0.96)
            )
        case "ash":
            return palette(
                center: Color(red: 0.95, green: 0.95, blue: 1.0),
                secondary: Color(red: 0.79, green: 0.82, blue: 0.95),
                accent: Color(red: 0.45, green: 0.56, blue: 0.88),
                edge: Color(red: 0.63, green: 0.48, blue: 0.84),
                halo: Color(red: 0.49, green: 0.60, blue: 0.96),
                ripple: Color(red: 0.70, green: 0.74, blue: 0.98),
                mistA: Color(red: 0.68, green: 0.78, blue: 0.96),
                mistB: Color(red: 0.63, green: 0.53, blue: 0.89)
            )
        case "ballad":
            return palette(
                center: Color(red: 1.0, green: 0.95, blue: 0.98),
                secondary: Color(red: 0.90, green: 0.82, blue: 0.97),
                accent: Color(red: 0.65, green: 0.53, blue: 0.95),
                edge: Color(red: 0.91, green: 0.52, blue: 0.77),
                halo: Color(red: 0.76, green: 0.62, blue: 0.98),
                ripple: Color(red: 0.95, green: 0.69, blue: 0.88),
                mistA: Color(red: 0.92, green: 0.74, blue: 0.98),
                mistB: Color(red: 0.88, green: 0.58, blue: 0.82)
            )
        case "coral":
            return palette(
                center: Color(red: 0.99, green: 0.96, blue: 0.93),
                secondary: Color(red: 0.88, green: 0.92, blue: 0.99),
                accent: Color(red: 0.97, green: 0.53, blue: 0.42),
                edge: Color(red: 0.33, green: 0.72, blue: 0.94),
                halo: Color(red: 0.83, green: 0.66, blue: 0.98),
                ripple: Color(red: 0.98, green: 0.67, blue: 0.50),
                mistA: Color(red: 0.99, green: 0.73, blue: 0.58),
                mistB: Color(red: 0.42, green: 0.78, blue: 0.98)
            )
        case "echo":
            return palette(
                center: Color(red: 0.93, green: 0.99, blue: 0.99),
                secondary: Color(red: 0.74, green: 0.94, blue: 0.98),
                accent: Color(red: 0.24, green: 0.76, blue: 0.87),
                edge: Color(red: 0.36, green: 0.58, blue: 0.95),
                halo: Color(red: 0.44, green: 0.83, blue: 0.93),
                ripple: Color(red: 0.62, green: 0.95, blue: 0.98),
                mistA: Color(red: 0.62, green: 0.94, blue: 0.97),
                mistB: Color(red: 0.43, green: 0.66, blue: 0.96)
            )
        case "fable":
            return palette(
                center: Color(red: 0.95, green: 0.95, blue: 1.0),
                secondary: Color(red: 0.76, green: 0.84, blue: 0.99),
                accent: Color(red: 0.32, green: 0.50, blue: 0.96),
                edge: Color(red: 0.70, green: 0.47, blue: 0.93),
                halo: Color(red: 0.46, green: 0.64, blue: 1.0),
                ripple: Color(red: 0.66, green: 0.79, blue: 1.0),
                mistA: Color(red: 0.66, green: 0.82, blue: 1.0),
                mistB: Color(red: 0.70, green: 0.53, blue: 0.96)
            )
        case "onyx":
            return palette(
                center: Color(red: 0.92, green: 0.96, blue: 1.0),
                secondary: Color(red: 0.66, green: 0.79, blue: 0.98),
                accent: Color(red: 0.20, green: 0.43, blue: 0.95),
                edge: Color(red: 0.44, green: 0.56, blue: 0.93),
                halo: Color(red: 0.29, green: 0.56, blue: 0.97),
                ripple: Color(red: 0.51, green: 0.72, blue: 0.99),
                mistA: Color(red: 0.49, green: 0.73, blue: 0.98),
                mistB: Color(red: 0.44, green: 0.58, blue: 0.92)
            )
        case "nova":
            return palette(
                center: Color(red: 0.93, green: 1.0, blue: 1.0),
                secondary: Color(red: 0.71, green: 0.96, blue: 1.0),
                accent: Color(red: 0.21, green: 0.76, blue: 1.0),
                edge: Color(red: 0.41, green: 0.56, blue: 0.98),
                halo: Color(red: 0.26, green: 0.86, blue: 0.99),
                ripple: Color(red: 0.61, green: 0.96, blue: 1.0),
                mistA: Color(red: 0.58, green: 0.95, blue: 1.0),
                mistB: Color(red: 0.49, green: 0.67, blue: 0.98)
            )
        case "sage":
            return palette(
                center: Color(red: 0.94, green: 1.0, blue: 0.97),
                secondary: Color(red: 0.76, green: 0.96, blue: 0.88),
                accent: Color(red: 0.35, green: 0.78, blue: 0.67),
                edge: Color(red: 0.35, green: 0.63, blue: 0.93),
                halo: Color(red: 0.48, green: 0.85, blue: 0.77),
                ripple: Color(red: 0.69, green: 0.97, blue: 0.84),
                mistA: Color(red: 0.66, green: 0.95, blue: 0.82),
                mistB: Color(red: 0.47, green: 0.70, blue: 0.95)
            )
        case "shimmer":
            return palette(
                center: Color(red: 0.99, green: 0.96, blue: 1.0),
                secondary: Color(red: 0.86, green: 0.81, blue: 0.99),
                accent: Color(red: 0.63, green: 0.59, blue: 0.98),
                edge: Color(red: 0.90, green: 0.55, blue: 0.95),
                halo: Color(red: 0.75, green: 0.65, blue: 1.0),
                ripple: Color(red: 0.91, green: 0.74, blue: 0.99),
                mistA: Color(red: 0.88, green: 0.74, blue: 1.0),
                mistB: Color(red: 0.88, green: 0.62, blue: 0.97)
            )
        case "kore":
            return palette(
                center: Color(red: 0.94, green: 0.98, blue: 1.0),
                secondary: Color(red: 0.74, green: 0.88, blue: 0.99),
                accent: Color(red: 0.33, green: 0.61, blue: 0.98),
                edge: Color(red: 0.45, green: 0.66, blue: 0.96),
                halo: Color(red: 0.41, green: 0.74, blue: 1.0),
                ripple: Color(red: 0.65, green: 0.87, blue: 0.99),
                mistA: Color(red: 0.67, green: 0.87, blue: 1.0),
                mistB: Color(red: 0.57, green: 0.72, blue: 0.98)
            )
        case "puck":
            return palette(
                center: Color(red: 0.95, green: 1.0, blue: 0.96),
                secondary: Color(red: 0.74, green: 0.98, blue: 0.89),
                accent: Color(red: 0.31, green: 0.83, blue: 0.62),
                edge: Color(red: 0.32, green: 0.66, blue: 0.93),
                halo: Color(red: 0.46, green: 0.90, blue: 0.76),
                ripple: Color(red: 0.67, green: 0.99, blue: 0.87),
                mistA: Color(red: 0.64, green: 0.98, blue: 0.84),
                mistB: Color(red: 0.43, green: 0.73, blue: 0.95)
            )
        case "aoede":
            return palette(
                center: Color(red: 0.98, green: 0.95, blue: 1.0),
                secondary: Color(red: 0.82, green: 0.78, blue: 0.99),
                accent: Color(red: 0.58, green: 0.52, blue: 0.97),
                edge: Color(red: 0.76, green: 0.49, blue: 0.96),
                halo: Color(red: 0.67, green: 0.60, blue: 1.0),
                ripple: Color(red: 0.84, green: 0.72, blue: 0.99),
                mistA: Color(red: 0.81, green: 0.71, blue: 1.0),
                mistB: Color(red: 0.78, green: 0.58, blue: 0.97)
            )
        case "leda":
            return palette(
                center: Color(red: 1.0, green: 0.96, blue: 0.92),
                secondary: Color(red: 0.99, green: 0.85, blue: 0.74),
                accent: Color(red: 0.98, green: 0.60, blue: 0.41),
                edge: Color(red: 0.82, green: 0.53, blue: 0.92),
                halo: Color(red: 0.98, green: 0.71, blue: 0.53),
                ripple: Color(red: 1.0, green: 0.80, blue: 0.63),
                mistA: Color(red: 1.0, green: 0.82, blue: 0.66),
                mistB: Color(red: 0.86, green: 0.60, blue: 0.94)
            )
        case "orus":
            return palette(
                center: Color(red: 1.0, green: 0.97, blue: 0.89),
                secondary: Color(red: 0.99, green: 0.86, blue: 0.59),
                accent: Color(red: 0.98, green: 0.66, blue: 0.25),
                edge: Color(red: 0.47, green: 0.57, blue: 0.94),
                halo: Color(red: 0.99, green: 0.76, blue: 0.38),
                ripple: Color(red: 1.0, green: 0.85, blue: 0.53),
                mistA: Color(red: 1.0, green: 0.83, blue: 0.52),
                mistB: Color(red: 0.57, green: 0.66, blue: 0.96)
            )
        case "zephyr":
            return palette(
                center: Color(red: 0.94, green: 0.99, blue: 1.0),
                secondary: Color(red: 0.72, green: 0.90, blue: 0.99),
                accent: Color(red: 0.28, green: 0.70, blue: 0.96),
                edge: Color(red: 0.44, green: 0.58, blue: 0.96),
                halo: Color(red: 0.46, green: 0.80, blue: 1.0),
                ripple: Color(red: 0.66, green: 0.92, blue: 0.99),
                mistA: Color(red: 0.64, green: 0.90, blue: 1.0),
                mistB: Color(red: 0.53, green: 0.68, blue: 0.97)
            )
        default:
            return generatedPalette(seedText: normalized)
        }
    }

    private static func generatedPalette(seedText: String) -> VoiceOrbPalette {
        let base = stableSeed(for: seedText)
        let secondary = stableSeed(for: "\(seedText)-secondary")
        let baseHue = wrapHue(base)
        let accentHue = wrapHue(baseHue + 0.11 + (secondary * 0.21))
        let edgeHue = wrapHue(accentHue + 0.17)
        let haloHue = wrapHue(baseHue + 0.31)

        return palette(
            center: Color(hue: wrapHue(baseHue + 0.02), saturation: 0.13, brightness: 0.99, opacity: 1),
            secondary: Color(hue: wrapHue(baseHue + 0.03), saturation: 0.39, brightness: 0.96, opacity: 1),
            accent: Color(hue: accentHue, saturation: 0.75, brightness: 0.93, opacity: 1),
            edge: Color(hue: edgeHue, saturation: 0.66, brightness: 0.86, opacity: 1),
            halo: Color(hue: haloHue, saturation: 0.73, brightness: 0.90, opacity: 1),
            ripple: Color(hue: wrapHue(accentHue + 0.05), saturation: 0.80, brightness: 0.95, opacity: 1),
            mistA: Color(hue: wrapHue(baseHue + 0.09), saturation: 0.56, brightness: 0.98, opacity: 1),
            mistB: Color(hue: wrapHue(baseHue + 0.27), saturation: 0.61, brightness: 0.93, opacity: 1)
        )
    }

    private static func palette(
        center: Color,
        secondary: Color,
        accent: Color,
        edge: Color,
        halo: Color,
        ripple: Color,
        mistA: Color,
        mistB: Color
    ) -> VoiceOrbPalette {
        VoiceOrbPalette(
            coreCenter: center,
            coreSecondary: secondary,
            coreAccent: accent,
            edgeTone: edge,
            haloTone: halo,
            rippleTone: ripple,
            mistPrimary: mistA,
            mistSecondary: mistB
        )
    }

    private static func stableSeed(for text: String) -> Double {
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return Double(hash % 10_000) / 10_000.0
    }

    private static func wrapHue(_ value: Double) -> Double {
        let wrapped = value.truncatingRemainder(dividingBy: 1)
        return wrapped < 0 ? wrapped + 1 : wrapped
    }
}

private struct AtmosphericVoiceOrb: View {
    let activityLevel: Double
    let isActive: Bool
    let palette: VoiceOrbPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let clampedActivity = min(max(activityLevel, 0), 1)
            let breathingScale = reduceMotion ? 1 : 1 + (0.02 * sin(phase * 0.7))

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                palette.haloTone.opacity(0.55),
                                palette.coreAccent.opacity(0.24),
                                .clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 190
                        )
                    )
                    .blur(radius: 28)
                    .scaleEffect(1.16 + (0.03 * clampedActivity))

                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: palette.coreCenter.opacity(0.93), location: 0),
                                .init(color: palette.coreSecondary.opacity(0.88), location: 0.30),
                                .init(color: palette.coreAccent.opacity(0.91), location: 0.58),
                                .init(color: palette.edgeTone.opacity(0.85), location: 0.80),
                                .init(color: palette.haloTone.opacity(0.66), location: 1)
                            ],
                            center: UnitPoint(
                                x: CGFloat(0.46 + (0.08 * sin(phase * 0.22))),
                                y: CGFloat(0.34 + (0.06 * cos(phase * 0.19)))
                            ),
                            startRadius: 12,
                            endRadius: 170
                        )
                    )
                    .overlay(
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        palette.coreCenter.opacity(0.25),
                                        palette.coreSecondary.opacity(0.12),
                                        .clear
                                    ],
                                    center: .topLeading,
                                    startRadius: 4,
                                    endRadius: 120
                                )
                            )
                            .blur(radius: 9)
                    )
                    .overlay(
                        OrbWaveInterference(
                            phase: phase,
                            activityLevel: clampedActivity,
                            palette: palette
                        )
                            .clipShape(Circle())
                    )
                    .overlay(
                        OrbNoiseTexture(phase: phase)
                            .clipShape(Circle())
                            .opacity(0.14)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(palette.edgeTone.opacity(0.26), lineWidth: 1)
                    )
                    .shadow(color: palette.haloTone.opacity(0.34), radius: 30)

                OrbParticleMist(phase: phase, activityLevel: clampedActivity, palette: palette)
            }
            .frame(width: 360, height: 360)
            .compositingGroup()
            .scaleEffect(isActive ? breathingScale : 1)
            .animation(.easeInOut(duration: 0.45), value: isActive)
        }
    }
}

private struct OrbWaveInterference: View {
    let phase: Double
    let activityLevel: Double
    let palette: VoiceOrbPalette

    var body: some View {
        Canvas { context, size in
            let steps = 260
            let radius = Double((min(size.width, size.height) / 2) - 4)
            var path = Path()

            for step in 0...steps {
                let progress = Double(step) / Double(steps)
                let angle = progress * .pi * 2
                let primary = sin((angle * 5.3) + (phase * 1.5))
                let secondary = cos((angle * 10.1) - (phase * 1.8))
                let ripple = sin((angle * 21.8) + (phase * 2.6))
                let displacement = (primary * (2.4 + (activityLevel * 5.2))) +
                    (secondary * (1.2 + (activityLevel * 2.7))) +
                    (ripple * (0.5 + (activityLevel * 1.8)))

                let x = Double(size.width / 2) + (cos(angle) * (radius + displacement))
                let y = Double(size.height / 2) + (sin(angle) * (radius + displacement))
                let point = CGPoint(x: CGFloat(x), y: CGFloat(y))

                if step == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()

            var glowContext = context
            glowContext.addFilter(.blur(radius: 2.2))
            glowContext.stroke(path, with: .color(palette.rippleTone.opacity(0.36)), lineWidth: 3)
            context.stroke(path, with: .color(palette.coreCenter.opacity(0.34)), lineWidth: 1.15)
        }
    }
}

private struct OrbNoiseTexture: View {
    let phase: Double

    var body: some View {
        Canvas { context, size in
            for index in 0..<420 {
                let seed = Double(index) * 0.913
                let x = CGFloat(pseudoRandom(seed * 13.13)) * size.width
                let y = CGFloat(pseudoRandom(seed * 41.71)) * size.height
                let sizeValue = CGFloat(0.7 + (pseudoRandom(seed * 7.17) * 1.2))
                let alpha = 0.012 + (pseudoRandom(seed + (phase * 0.01)) * 0.035)
                let rect = CGRect(x: x, y: y, width: sizeValue, height: sizeValue)
                context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(alpha)))
            }
        }
    }
}

private struct OrbParticleMist: View {
    let phase: Double
    let activityLevel: Double
    let palette: VoiceOrbPalette

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let baseRadius = Double(diameter * 0.56)
            ZStack {
                ForEach(0..<24, id: \.self) { index in
                    let seed = Double(index) * 0.77
                    let angularVelocity = 0.05 + (Double(index % 5) * 0.006)
                    let angle = (phase * angularVelocity) + (seed * 3.2)
                    let drift = sin((phase * 0.9) + (seed * 4.4)) * (8 + (activityLevel * 14))
                    let radius = baseRadius + drift
                    let x = CGFloat(Double(proxy.size.width / 2) + (cos(angle) * radius))
                    let y = CGFloat(Double(proxy.size.height / 2) + (sin(angle) * radius))
                    let particleSize = CGFloat(1.8 + (pseudoRandom(seed * 2.6) * 3.2))
                    let opacity = 0.14 + (pseudoRandom(seed * 9.3) * 0.24)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    palette.mistPrimary.opacity(opacity),
                                    palette.mistSecondary.opacity(opacity * 0.55)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: particleSize, height: particleSize)
                        .position(x: x, y: y)
                        .blur(radius: 0.8)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct OrbDirectionButtonStyle: ButtonStyle {
    let accentColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(FloTheme.textPrimary)
            .background(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(configuration.isPressed ? 0.22 : 0.14),
                                Color.white.opacity(configuration.isPressed ? 0.12 : 0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Circle()
                    .strokeBorder(accentColor.opacity(0.32), lineWidth: 1)
            )
    }
}

private struct VoiceChipButtonStyle: ButtonStyle {
    let isSelected: Bool
    let accentColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isSelected ? FloTheme.textPrimary : FloTheme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? accentColor.opacity(configuration.isPressed ? 0.24 : 0.32) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? accentColor.opacity(0.52) : Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

private struct SectionDivider: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.16), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }
}

private func pseudoRandom(_ value: Double) -> Double {
    let raw = sin(value * 12.9898) * 43758.5453
    return raw - floor(raw)
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
        VStack(alignment: .leading, spacing: 12) {
            content
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            SectionDivider()
        }
    }
}

private struct StatusChip: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(FloTheme.textPrimary)
            .padding(.vertical, 4)
            .padding(.horizontal, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(color.opacity(0.40), lineWidth: 1)
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
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(FloTheme.textPrimary)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill((tone == .error ? FloTheme.danger : FloTheme.accent).opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder((tone == .error ? FloTheme.danger : FloTheme.accent).opacity(0.34), lineWidth: 1)
        )
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.72))
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                FloTheme.accent.opacity(configuration.isPressed ? 0.9 : 1),
                                FloTheme.accentSoft.opacity(configuration.isPressed ? 0.9 : 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.52)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct SecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.white.opacity(isEnabled ? 0.94 : 0.64))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.55)
    }
}
