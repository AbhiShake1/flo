# 04 Controller Action Ledger

Source baseline: `apps/macos/Sources/Features/FloController.swift` (69 `public func` actions, captured on 2026-03-05).

Status legend: `Not Started`, `In Progress`, `Parity`, `Exception`.

| ID | macOS public action | Windows equivalent | Evidence | Status |
|---|---|---|---|---|
| A01 | `providerDisplayName(for provider: AIProvider) -> String` | `FloController::provider_display_name` | `flo-core/src/controller.rs` query-helper tests | In Progress |
| A02 | `providerLogoURL(for provider: AIProvider) -> URL?` | `FloController::provider_logo_url` | `flo-core/src/controller.rs` query-helper tests | In Progress |
| A03 | `providerModels(for provider: AIProvider, matching query: String = "") -> [ModelsDevModelEntry]` | `FloController::provider_models` + `ControllerEvent::ModelsCatalogLoaded` | `flo-core/src/controller.rs` reducer/query tests | In Progress |
| A04 | `activeRewriteModel(for provider: AIProvider) -> String` | `FloController::active_rewrite_model` | `flo-core/src/controller.rs` query-helper tests | In Progress |
| A05 | `rewriteModelOverride(for provider: AIProvider) -> String?` | `FloController::rewrite_model_override` | `flo-core/src/controller.rs` query-helper tests | In Progress |
| A06 | `rewriteModelOverride(for provider: AIProvider, credentialIndex: Int) -> String?` | `FloController::rewrite_model_override_for_credential` | `flo-core/src/controller.rs` query-helper tests | In Progress |
| A07 | `activeRewriteModel(for provider: AIProvider, credentialIndex: Int) -> String` | `FloController::active_rewrite_model_for_credential` | `flo-core/src/controller.rs` query-helper tests | In Progress |
| A08 | `setRewriteModel(_ modelID: String, for provider: AIProvider)` | `FloCommand::SetRewriteModelForProvider` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A09 | `clearRewriteModelOverride(for provider: AIProvider)` | `FloCommand::ClearRewriteModelOverrideForProvider` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A10 | `setRewriteModel(_ modelID: String, for provider: AIProvider, credentialIndex: Int)` | `FloCommand::SetRewriteModelForProviderCredential` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A11 | `clearRewriteModelOverride(for provider: AIProvider, credentialIndex: Int)` | `FloCommand::ClearRewriteModelOverrideForProviderCredential` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A12 | `refreshModelsDevCatalog(forceRefresh: Bool = false) async` | `FloCommand::RefreshModelsDevCatalog` + `ControllerEvent::ModelsCatalogLoaded` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A13 | `providerSupportsOAuth(_ provider: AIProvider) -> Bool` | `FloController::provider_supports_oauth` | `flo-core/src/controller.rs` query-helper tests | In Progress |
| A14 | `providerCredentialSourceLabel(for provider: AIProvider) -> String?` | `FloController::provider_credential_source_label` | `flo-core/src/controller.rs` query-helper tests | In Progress |
| A15 | `canRemoveSavedProviderCredential(for provider: AIProvider) -> Bool` | `FloController::can_remove_saved_provider_credential` | `flo-core/src/controller.rs` query-helper tests | In Progress |
| A16 | `configuredKeyCount(for provider: AIProvider) -> Int` | `FloController::configured_key_count` | `flo-core/src/controller.rs` query-helper tests | In Progress |
| A17 | `providerCredentials(for provider: AIProvider) -> [String]` | `FloController::provider_credentials` | `flo-core/src/controller.rs` query-helper tests | In Progress |
| A18 | `copyProviderCredential(at index: Int, for provider: AIProvider) -> Bool` | `FloCommand::CopyProviderCredential` + `ControllerEffect::CopyToClipboard` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A19 | `addProviderCredential(_ credential: String, for provider: AIProvider)` | `FloCommand::AddProviderCredential` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A20 | `updateProviderCredential(_ credential: String, at index: Int, for provider: AIProvider)` | `FloCommand::UpdateProviderCredential` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A21 | `removeProviderCredential(at index: Int, for provider: AIProvider) async` | `FloCommand::RemoveProviderCredential` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A22 | `reorderProviderCredentials(_ credentials: [String], for provider: AIProvider)` | `FloCommand::ReorderProviderCredentials` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A23 | `providerSupportsFailoverOperation(_ provider: AIProvider) -> Bool` | `FloController::provider_supports_failover_operation` | `flo-core/src/controller.rs` query-helper tests | In Progress |
| A24 | `providerEnabledForFailover(_ provider: AIProvider) -> Bool` | `FloController::provider_enabled_for_failover` | `flo-core/src/controller.rs` query-helper tests | In Progress |
| A25 | `canMoveProviderUpInFailoverOrder(_ provider: AIProvider) -> Bool` | `FloController::can_move_provider_up_in_failover_order` | `flo-core/src/controller.rs` query-helper tests | In Progress |
| A26 | `canMoveProviderDownInFailoverOrder(_ provider: AIProvider) -> Bool` | `FloController::can_move_provider_down_in_failover_order` | `flo-core/src/controller.rs` query-helper tests | In Progress |
| A27 | `moveProviderUpInFailoverOrder(_ provider: AIProvider)` | `FloCommand::MoveProviderUpInFailoverOrder` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A28 | `moveProviderDownInFailoverOrder(_ provider: AIProvider)` | `FloCommand::MoveProviderDownInFailoverOrder` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A29 | `reorderProvidersInFailoverOrder(_ providers: [AIProvider])` | `FloCommand::ReorderProvidersInFailoverOrder` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A30 | `addProviderToFailoverOrder(_ provider: AIProvider)` | `FloCommand::AddProviderToFailoverOrder` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A31 | `removeProviderFromFailoverOrder(_ provider: AIProvider)` | `FloCommand::RemoveProviderFromFailoverOrder` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A32 | `setProviderEnabledInFailover(_ provider: AIProvider, enabled: Bool)` | `FloCommand::SetProviderEnabledInFailover` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A33 | `setFailoverAllowCrossProviderFallback(_ enabled: Bool)` | `FloCommand::SetFailoverAllowCrossProviderFallback` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A34 | `setFailoverMaxAttempts(_ value: Int)` | `FloCommand::SetFailoverMaxAttempts` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A35 | `setFailoverFailureThreshold(_ value: Int)` | `FloCommand::SetFailoverFailureThreshold` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A36 | `setFailoverCooldownSeconds(_ value: Int)` | `FloCommand::SetFailoverCooldownSeconds` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A37 | `bootstrap() async` | `FloCommand::Bootstrap` + `ControllerEvent::AuthRestored` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A38 | `login() async` | `FloCommand::Login` + OAuth callback parser contract | `flo-provider/src/oauth.rs` tests | In Progress |
| A39 | `saveProviderCredential(_ credential: String)` | `FloCommand::SaveProviderCredential` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A40 | `saveProviderCredential(_ credential: String, for provider: AIProvider)` | `FloCommand::SaveProviderCredentialForProvider` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A41 | `removeSavedProviderCredential() async` | `FloCommand::RemoveSavedProviderCredential` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A42 | `removeSavedProviderCredential(for provider: AIProvider) async` | `FloCommand::RemoveSavedProviderCredentialForProvider` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A43 | `logout() async` | `FloCommand::Logout` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A44 | `refreshPermissions()` | `FloCommand::RefreshPermissions` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A45 | `requestMicrophoneAccess() async` | `FloCommand::RequestMicrophoneAccess` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A46 | `requestPermission(_ permission: PermissionKind) async` | `FloCommand::RequestPermission` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A47 | `promptForRequiredPermissions() async` | `FloCommand::PromptForRequiredPermissions` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A48 | `openSystemSettings(for permission: PermissionKind)` | `FloCommand::OpenSystemSettings` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A49 | `updateShortcut(action: ShortcutAction, combo: KeyCombo)` | `FloCommand::UpdateShortcut` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A50 | `resetShortcutsToDefault()` | `FloCommand::ResetShortcutsToDefault` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A51 | `pasteLastTranscript()` | `FloCommand::PasteLastTranscript` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A52 | `updateVoice(_ voice: String)` | `FloCommand::UpdateVoice` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A53 | `updateVoiceSpeed(_ speed: Double)` | `FloCommand::UpdateVoiceSpeed` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A54 | `setLiveDictationEnabled(_ enabled: Bool)` | `FloCommand::SetLiveDictationEnabled` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A55 | `setDictationRewriteEnabled(_ enabled: Bool)` | `FloCommand::SetDictationRewriteEnabled` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A56 | `setDictationBaseTone(_ tone: DictationBaseTone)` | `FloCommand::SetDictationBaseTone` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A57 | `setDictationWarmth(_ level: DictationStyleLevel)` | `FloCommand::SetDictationWarmth` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A58 | `setDictationEnthusiasm(_ level: DictationStyleLevel)` | `FloCommand::SetDictationEnthusiasm` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A59 | `setDictationHeadersAndLists(_ level: DictationStyleLevel)` | `FloCommand::SetDictationHeadersAndLists` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A60 | `setDictationEmoji(_ level: DictationStyleLevel)` | `FloCommand::SetDictationEmoji` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A61 | `setDictationCustomInstructions(_ text: String)` | `FloCommand::SetDictationCustomInstructions` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A62 | `setDictationLiveFinalizationMode(_ mode: DictationLiveFinalizationMode)` | `FloCommand::SetDictationLiveFinalizationMode` + `plan_live_finalization` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A63 | `applyDictationRewritePreset(_ preset: DictationRewritePreset)` | `FloCommand::ApplyDictationRewritePreset` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A64 | `completeHotkeyConfirmation()` | `FloCommand::CompleteHotkeyConfirmation` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A65 | `clearHistory()` | `FloCommand::ClearHistory` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A66 | `startDictationFromHotkey() async` | `FloCommand::StartDictationFromHotkey` + `ControllerEvent::CaptureStarted` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A67 | `stopDictationFromHotkey() async` | `FloCommand::StopDictationFromHotkey` + `ControllerEvent::CaptureStopped` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A68 | `readSelectedTextFromHotkey() async` | `FloCommand::ReadSelectedTextFromHotkey` + `ControllerEvent::SelectionRead` | `flo-core/src/controller.rs` reducer tests | In Progress |
| A69 | `previewCurrentVoice() async` | `FloCommand::PreviewCurrentVoice` | `flo-core/src/controller.rs` reducer tests | In Progress |
