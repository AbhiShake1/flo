# 04 Controller Action Ledger

Source baseline: `apps/macos/Sources/Features/FloController.swift` (69 `public func` actions, captured on 2026-03-05).

Status legend: `Not Started`, `In Progress`, `Parity`, `Exception`.

| ID | macOS public action | Windows equivalent | Evidence | Status |
|---|---|---|---|---|
| A01 | `providerDisplayName(for provider: AIProvider) -> String` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A02 | `providerLogoURL(for provider: AIProvider) -> URL?` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A03 | `providerModels(for provider: AIProvider, matching query: String = "") -> [ModelsDevModelEntry]` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A04 | `activeRewriteModel(for provider: AIProvider) -> String` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A05 | `rewriteModelOverride(for provider: AIProvider) -> String?` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A06 | `rewriteModelOverride(for provider: AIProvider, credentialIndex: Int) -> String?` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A07 | `activeRewriteModel(for provider: AIProvider, credentialIndex: Int) -> String` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A08 | `setRewriteModel(_ modelID: String, for provider: AIProvider)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A09 | `clearRewriteModelOverride(for provider: AIProvider)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A10 | `setRewriteModel(_ modelID: String, for provider: AIProvider, credentialIndex: Int)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A11 | `clearRewriteModelOverride(for provider: AIProvider, credentialIndex: Int)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A12 | `refreshModelsDevCatalog(forceRefresh: Bool = false) async` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A13 | `providerSupportsOAuth(_ provider: AIProvider) -> Bool` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A14 | `providerCredentialSourceLabel(for provider: AIProvider) -> String?` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A15 | `canRemoveSavedProviderCredential(for provider: AIProvider) -> Bool` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A16 | `configuredKeyCount(for provider: AIProvider) -> Int` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A17 | `providerCredentials(for provider: AIProvider) -> [String]` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A18 | `copyProviderCredential(at index: Int, for provider: AIProvider) -> Bool` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A19 | `addProviderCredential(_ credential: String, for provider: AIProvider)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A20 | `updateProviderCredential(_ credential: String, at index: Int, for provider: AIProvider)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A21 | `removeProviderCredential(at index: Int, for provider: AIProvider) async` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A22 | `reorderProviderCredentials(_ credentials: [String], for provider: AIProvider)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A23 | `providerSupportsFailoverOperation(_ provider: AIProvider) -> Bool` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A24 | `providerEnabledForFailover(_ provider: AIProvider) -> Bool` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A25 | `canMoveProviderUpInFailoverOrder(_ provider: AIProvider) -> Bool` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A26 | `canMoveProviderDownInFailoverOrder(_ provider: AIProvider) -> Bool` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A27 | `moveProviderUpInFailoverOrder(_ provider: AIProvider)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A28 | `moveProviderDownInFailoverOrder(_ provider: AIProvider)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A29 | `reorderProvidersInFailoverOrder(_ providers: [AIProvider])` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A30 | `addProviderToFailoverOrder(_ provider: AIProvider)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A31 | `removeProviderFromFailoverOrder(_ provider: AIProvider)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A32 | `setProviderEnabledInFailover(_ provider: AIProvider, enabled: Bool)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A33 | `setFailoverAllowCrossProviderFallback(_ enabled: Bool)` | `FloCommand::SetFailoverAllowCrossProviderFallback` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A34 | `setFailoverMaxAttempts(_ value: Int)` | `FloCommand::SetFailoverMaxAttempts` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A35 | `setFailoverFailureThreshold(_ value: Int)` | `FloCommand::SetFailoverFailureThreshold` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A36 | `setFailoverCooldownSeconds(_ value: Int)` | `FloCommand::SetFailoverCooldownSeconds` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A37 | `bootstrap() async` | `FloCommand::Bootstrap` + `ControllerEvent::AuthRestored` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A38 | `login() async` | `FloCommand::Login` + OAuth callback parser contract | `flo-provider/src/oauth.rs` tests | In Progress |
| A39 | `saveProviderCredential(_ credential: String)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A40 | `saveProviderCredential(_ credential: String, for provider: AIProvider)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A41 | `removeSavedProviderCredential() async` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A42 | `removeSavedProviderCredential(for provider: AIProvider) async` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A43 | `logout() async` | `FloCommand::Logout` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A44 | `refreshPermissions()` | `FloCommand::RefreshPermissions` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A45 | `requestMicrophoneAccess() async` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A46 | `requestPermission(_ permission: PermissionKind) async` | `FloCommand::RequestPermission` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A47 | `promptForRequiredPermissions() async` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A48 | `openSystemSettings(for permission: PermissionKind)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A49 | `updateShortcut(action: ShortcutAction, combo: KeyCombo)` | `FloCommand::UpdateShortcut` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A50 | `resetShortcutsToDefault()` | `FloCommand::ResetShortcutsToDefault` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A51 | `pasteLastTranscript()` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A52 | `updateVoice(_ voice: String)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A53 | `updateVoiceSpeed(_ speed: Double)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A54 | `setLiveDictationEnabled(_ enabled: Bool)` | `FloCommand::SetLiveDictationEnabled` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A55 | `setDictationRewriteEnabled(_ enabled: Bool)` | `FloCommand::SetDictationRewriteEnabled` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A56 | `setDictationBaseTone(_ tone: DictationBaseTone)` | `FloCommand::SetDictationBaseTone` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A57 | `setDictationWarmth(_ level: DictationStyleLevel)` | `FloCommand::SetDictationWarmth` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A58 | `setDictationEnthusiasm(_ level: DictationStyleLevel)` | `FloCommand::SetDictationEnthusiasm` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A59 | `setDictationHeadersAndLists(_ level: DictationStyleLevel)` | `FloCommand::SetDictationHeadersAndLists` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A60 | `setDictationEmoji(_ level: DictationStyleLevel)` | `FloCommand::SetDictationEmoji` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A61 | `setDictationCustomInstructions(_ text: String)` | `FloCommand::SetDictationCustomInstructions` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A62 | `setDictationLiveFinalizationMode(_ mode: DictationLiveFinalizationMode)` | `FloCommand::SetDictationLiveFinalizationMode` + `plan_live_finalization` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A63 | `applyDictationRewritePreset(_ preset: DictationRewritePreset)` | TBD (map in P1 freeze) | `apps/windows/docs/03-acceptance-tests.md` | Not Started |
| A64 | `completeHotkeyConfirmation()` | `FloCommand::CompleteHotkeyConfirmation` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A65 | `clearHistory()` | `FloCommand::ClearHistory` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A66 | `startDictationFromHotkey() async` | `FloCommand::StartDictationFromHotkey` + `ControllerEvent::CaptureStarted` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A67 | `stopDictationFromHotkey() async` | `FloCommand::StopDictationFromHotkey` + `ControllerEvent::CaptureStopped` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A68 | `readSelectedTextFromHotkey() async` | `FloCommand::ReadSelectedTextFromHotkey` + `ControllerEvent::SelectionRead` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A69 | `previewCurrentVoice() async` | `FloCommand::PreviewCurrentVoice` | `flo-core/src/controller.rs` reducer tests | In Progress |
