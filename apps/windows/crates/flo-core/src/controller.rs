use std::collections::HashMap;

use flo_domain::{
    AuthState, DictationBaseTone, DictationLiveFinalizationMode, DictationRewritePreferences,
    DictationRewritePreset, DictationStyleLevel, FloatingBarState, PermissionKind,
    PermissionStatus, PlatformErrorCode, ProviderRoutingOverrides, RecorderState,
    SelectionReadMethod, ShortcutBinding, TextInjectionFailureReason, UserSession,
    VoicePreferences,
};

use crate::capabilities::PlatformCapabilities;

#[derive(Debug, Clone)]
pub struct ControllerState {
    pub auth_state: AuthState,
    pub recorder_state: RecorderState,
    pub permission_status: PermissionStatus,
    pub shortcut_bindings: Vec<ShortcutBinding>,
    pub live_dictation_enabled: bool,
    pub live_transcript_preview: String,
    pub dictation_rewrite_preferences: DictationRewritePreferences,
    pub voice_preferences: VoicePreferences,
    pub active_provider: String,
    pub provider_credentials: HashMap<String, Vec<String>>,
    pub models_catalog: HashMap<String, Vec<String>>,
    pub uses_saved_provider_credential: bool,
    pub provider_routing_overrides: ProviderRoutingOverrides,
    pub status_message: Option<String>,
    pub last_selection_read_method: Option<SelectionReadMethod>,
    pub last_dictation_transcript: Option<String>,
    pub is_voice_preview_in_progress: bool,
}

impl Default for ControllerState {
    fn default() -> Self {
        Self {
            auth_state: AuthState::LoggedOut,
            recorder_state: RecorderState::Idle,
            permission_status: PermissionStatus::default(),
            shortcut_bindings: Vec::new(),
            live_dictation_enabled: false,
            live_transcript_preview: String::new(),
            dictation_rewrite_preferences: DictationRewritePreferences::default(),
            voice_preferences: VoicePreferences::default(),
            active_provider: "openai".to_string(),
            provider_credentials: HashMap::new(),
            models_catalog: HashMap::new(),
            uses_saved_provider_credential: false,
            provider_routing_overrides: ProviderRoutingOverrides::default(),
            status_message: None,
            last_selection_read_method: None,
            last_dictation_transcript: None,
            is_voice_preview_in_progress: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum FloCommand {
    Bootstrap,
    Login,
    Logout,
    RefreshPermissions,
    RequestMicrophoneAccess,
    RequestPermission(PermissionKind),
    PromptForRequiredPermissions,
    OpenSystemSettings(PermissionKind),
    RefreshModelsDevCatalog,
    SetRewriteModelForProvider {
        provider: String,
        model_id: String,
    },
    ClearRewriteModelOverrideForProvider(String),
    SetRewriteModelForProviderCredential {
        provider: String,
        credential_index: usize,
        model_id: String,
    },
    ClearRewriteModelOverrideForProviderCredential {
        provider: String,
        credential_index: usize,
    },
    UpdateShortcut(ShortcutBinding),
    ResetShortcutsToDefault,
    SetLiveDictationEnabled(bool),
    SetDictationRewriteEnabled(bool),
    SetDictationBaseTone(DictationBaseTone),
    SetDictationWarmth(DictationStyleLevel),
    SetDictationEnthusiasm(DictationStyleLevel),
    SetDictationHeadersAndLists(DictationStyleLevel),
    SetDictationEmoji(DictationStyleLevel),
    SetDictationCustomInstructions(String),
    SetDictationLiveFinalizationMode(DictationLiveFinalizationMode),
    ApplyDictationRewritePreset(DictationRewritePreset),
    SaveProviderCredential(String),
    SaveProviderCredentialForProvider {
        provider: String,
        credential: String,
    },
    AddProviderCredential {
        provider: String,
        credential: String,
    },
    UpdateProviderCredential {
        provider: String,
        index: usize,
        credential: String,
    },
    RemoveProviderCredential {
        provider: String,
        index: usize,
    },
    ReorderProviderCredentials {
        provider: String,
        credentials: Vec<String>,
    },
    RemoveSavedProviderCredential,
    RemoveSavedProviderCredentialForProvider(String),
    CopyProviderCredential {
        provider: String,
        index: usize,
    },
    PasteLastTranscript,
    UpdateVoice(String),
    UpdateVoiceSpeed(f32),
    ClearHistory,
    StartDictationFromHotkey,
    StopDictationFromHotkey,
    ReadSelectedTextFromHotkey,
    PreviewCurrentVoice,
    CompleteHotkeyConfirmation,
    ReorderProvidersInFailoverOrder(Vec<String>),
    AddProviderToFailoverOrder(String),
    RemoveProviderFromFailoverOrder(String),
    MoveProviderUpInFailoverOrder(String),
    MoveProviderDownInFailoverOrder(String),
    SetProviderEnabledInFailover {
        provider: String,
        enabled: bool,
    },
    SetFailoverAllowCrossProviderFallback(bool),
    SetFailoverMaxAttempts(u32),
    SetFailoverFailureThreshold(u32),
    SetFailoverCooldownSeconds(u32),
}

#[derive(Debug, Clone, PartialEq)]
pub enum LiveFinalizationPlan {
    InjectDelta(String),
    ReplaceWithFinal(String),
    CopyFinalToClipboard(String),
    Noop,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ControllerEffect {
    RestoreSession,
    StartOAuth,
    Logout,
    RefreshPermissions,
    RequestMicrophoneAccess,
    RequestPermission(PermissionKind),
    OpenSystemSettings(PermissionKind),
    FetchModelsCatalog,
    PersistShortcuts,
    PersistRewritePreferences,
    PersistVoicePreferences,
    PersistProviderCredentials {
        provider: String,
        credentials: Vec<String>,
    },
    ClearProviderCredentials {
        provider: String,
    },
    CopyToClipboard(String),
    PersistRoutingOverrides,
    ClearHistory,
    ShowFloatingBar(FloatingBarState),
    UpdateFloatingBar(FloatingBarState),
    HideFloatingBar,
    StartSpeechCapture,
    StopSpeechCapture,
    FinalizeDictation(LiveFinalizationPlan),
    InjectText {
        text: String,
        fallback_to_clipboard: bool,
    },
    ReadSelected {
        prefer_uia: bool,
        fallback_to_clipboard: bool,
    },
    PromptForElevation,
    StartTts,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ControllerEvent {
    AuthRestored(Option<UserSession>),
    ProviderCredentialsLoaded {
        provider: String,
        credentials: Vec<String>,
    },
    ModelsCatalogLoaded {
        provider: String,
        models: Vec<String>,
    },
    CaptureStarted,
    CaptureStopped {
        transcript: String,
    },
    TranscriptPartial(String),
    SelectionRead {
        text: String,
        method: SelectionReadMethod,
    },
    InjectionCompleted,
    InjectionFailed(TextInjectionFailureReason),
    ElevatedRelaunchRequested,
    PermissionStatusUpdated(PermissionStatus),
    Error(PlatformErrorCode),
    TtsCompleted,
    TtsCanceled,
    VoicePreviewCompleted,
    VoicePreviewCanceled,
}

#[derive(Debug, Default)]
pub struct FloController {
    pub state: ControllerState,
}

impl FloController {
    pub fn new() -> Self {
        Self {
            state: ControllerState::default(),
        }
    }

    pub fn dispatch(
        &mut self,
        command: FloCommand,
        capabilities: &PlatformCapabilities,
    ) -> Vec<ControllerEffect> {
        match command {
            FloCommand::Bootstrap => {
                self.state.auth_state = AuthState::Authenticating;
                vec![
                    ControllerEffect::RestoreSession,
                    ControllerEffect::RefreshPermissions,
                ]
            }
            FloCommand::Login => {
                if self.state.uses_saved_provider_credential {
                    self.state.status_message = Some("Login disabled in API key mode.".to_string());
                    return Vec::new();
                }
                self.state.auth_state = AuthState::Authenticating;
                vec![ControllerEffect::StartOAuth]
            }
            FloCommand::Logout => {
                if self.state.uses_saved_provider_credential {
                    if self
                        .provider_credentials_for(&self.state.active_provider)
                        .is_empty()
                    {
                        self.state.status_message = Some(
                            "Remove the saved API key from Provider Workbench to fully log out."
                                .to_string(),
                        );
                        return Vec::new();
                    }

                    return self
                        .remove_saved_provider_credential_for(self.state.active_provider.clone());
                }
                self.state.auth_state = AuthState::LoggedOut;
                self.state.recorder_state = RecorderState::Idle;
                self.state.live_transcript_preview.clear();
                self.state.last_dictation_transcript = None;
                vec![ControllerEffect::Logout, ControllerEffect::HideFloatingBar]
            }
            FloCommand::RefreshPermissions => vec![ControllerEffect::RefreshPermissions],
            FloCommand::RequestMicrophoneAccess => {
                vec![
                    ControllerEffect::RequestMicrophoneAccess,
                    ControllerEffect::RefreshPermissions,
                ]
            }
            FloCommand::RequestPermission(permission) => {
                vec![ControllerEffect::RequestPermission(permission)]
            }
            FloCommand::PromptForRequiredPermissions => {
                let missing = self.missing_permissions();
                if missing.is_empty() {
                    self.state.status_message =
                        Some("All required permissions are already granted.".to_string());
                    return Vec::new();
                }

                let mut effects = Vec::new();
                for permission in missing {
                    match permission {
                        PermissionKind::Microphone => {
                            effects.push(ControllerEffect::RequestMicrophoneAccess);
                        }
                        PermissionKind::Accessibility | PermissionKind::InputMonitoring => {
                            effects.push(ControllerEffect::OpenSystemSettings(permission));
                        }
                    }
                }
                effects.push(ControllerEffect::RefreshPermissions);
                self.state.status_message = Some(
                    "Finish granting permissions in System Settings, then refresh.".to_string(),
                );
                effects
            }
            FloCommand::OpenSystemSettings(permission) => {
                self.state.status_message = Some(match permission {
                    PermissionKind::Microphone => {
                        "Grant microphone, then return here and press Refresh Permissions."
                            .to_string()
                    }
                    PermissionKind::Accessibility | PermissionKind::InputMonitoring => {
                        "After enabling this permission, quit and reopen FloApp, then press Refresh Permissions."
                            .to_string()
                    }
                });
                vec![ControllerEffect::OpenSystemSettings(permission)]
            }
            FloCommand::RefreshModelsDevCatalog => vec![ControllerEffect::FetchModelsCatalog],
            FloCommand::SetRewriteModelForProvider { provider, model_id } => {
                let provider = normalize_provider_id(&provider);
                let model_id = model_id.trim().to_string();
                if provider.is_empty() || model_id.is_empty() {
                    return Vec::new();
                }

                let mut overrides = self
                    .state
                    .provider_routing_overrides
                    .rewrite_models_by_provider
                    .clone()
                    .unwrap_or_default();
                overrides.insert(provider.clone(), model_id.clone());
                self.state
                    .provider_routing_overrides
                    .rewrite_models_by_provider = Some(overrides);
                self.state.status_message = Some(format!(
                    "{} rewrite model set to {}.",
                    provider_display_name(&provider),
                    model_id
                ));
                vec![ControllerEffect::PersistRoutingOverrides]
            }
            FloCommand::ClearRewriteModelOverrideForProvider(provider) => {
                let provider = normalize_provider_id(&provider);
                if provider.is_empty() {
                    return Vec::new();
                }
                let mut overrides = self
                    .state
                    .provider_routing_overrides
                    .rewrite_models_by_provider
                    .clone()
                    .unwrap_or_default();
                overrides.remove(&provider);
                self.state
                    .provider_routing_overrides
                    .rewrite_models_by_provider = if overrides.is_empty() {
                    None
                } else {
                    Some(overrides)
                };
                self.state.status_message = Some(format!(
                    "{} rewrite model override cleared.",
                    provider_display_name(&provider)
                ));
                vec![ControllerEffect::PersistRoutingOverrides]
            }
            FloCommand::SetRewriteModelForProviderCredential {
                provider,
                credential_index,
                model_id,
            } => {
                let provider = normalize_provider_id(&provider);
                let model_id = model_id.trim().to_string();
                if provider.is_empty() || model_id.is_empty() {
                    return Vec::new();
                }
                let mut provider_map = self
                    .state
                    .provider_routing_overrides
                    .rewrite_models_by_provider_credential_index
                    .clone()
                    .unwrap_or_default();
                let mut index_map = provider_map.get(&provider).cloned().unwrap_or_default();
                index_map.insert(credential_index.to_string(), model_id.clone());
                provider_map.insert(provider.clone(), index_map);
                self.state
                    .provider_routing_overrides
                    .rewrite_models_by_provider_credential_index = Some(provider_map);
                self.state.status_message = Some(format!(
                    "{} key {} model set to {}.",
                    provider_display_name(&provider),
                    credential_index + 1,
                    model_id
                ));
                vec![ControllerEffect::PersistRoutingOverrides]
            }
            FloCommand::ClearRewriteModelOverrideForProviderCredential {
                provider,
                credential_index,
            } => {
                let provider = normalize_provider_id(&provider);
                if provider.is_empty() {
                    return Vec::new();
                }
                let mut provider_map = self
                    .state
                    .provider_routing_overrides
                    .rewrite_models_by_provider_credential_index
                    .clone()
                    .unwrap_or_default();
                if let Some(index_map) = provider_map.get_mut(&provider) {
                    index_map.remove(&credential_index.to_string());
                    if index_map.is_empty() {
                        provider_map.remove(&provider);
                    }
                }
                self.state
                    .provider_routing_overrides
                    .rewrite_models_by_provider_credential_index = if provider_map.is_empty() {
                    None
                } else {
                    Some(provider_map)
                };
                self.state.status_message = Some(format!(
                    "{} key {} model override cleared.",
                    provider_display_name(&provider),
                    credential_index + 1
                ));
                vec![ControllerEffect::PersistRoutingOverrides]
            }
            FloCommand::UpdateShortcut(binding) => {
                if let Some(existing) = self
                    .state
                    .shortcut_bindings
                    .iter_mut()
                    .find(|it| it.action == binding.action)
                {
                    *existing = binding;
                } else {
                    self.state.shortcut_bindings.push(binding);
                }
                vec![ControllerEffect::PersistShortcuts]
            }
            FloCommand::ResetShortcutsToDefault => {
                self.state.shortcut_bindings.clear();
                self.state.status_message = Some("Shortcuts reset to defaults.".to_string());
                vec![ControllerEffect::PersistShortcuts]
            }
            FloCommand::SetLiveDictationEnabled(enabled) => {
                self.state.live_dictation_enabled = enabled;
                self.state.dictation_rewrite_preferences.live_typing_enabled = enabled;
                vec![ControllerEffect::PersistRewritePreferences]
            }
            FloCommand::SetDictationRewriteEnabled(enabled) => {
                self.state.dictation_rewrite_preferences.rewrite_enabled = enabled;
                vec![ControllerEffect::PersistRewritePreferences]
            }
            FloCommand::SetDictationBaseTone(value) => {
                self.state.dictation_rewrite_preferences.base_tone = value;
                vec![ControllerEffect::PersistRewritePreferences]
            }
            FloCommand::SetDictationWarmth(value) => {
                self.state.dictation_rewrite_preferences.warmth = value;
                vec![ControllerEffect::PersistRewritePreferences]
            }
            FloCommand::SetDictationEnthusiasm(value) => {
                self.state.dictation_rewrite_preferences.enthusiasm = value;
                vec![ControllerEffect::PersistRewritePreferences]
            }
            FloCommand::SetDictationHeadersAndLists(value) => {
                self.state.dictation_rewrite_preferences.headers_and_lists = value;
                vec![ControllerEffect::PersistRewritePreferences]
            }
            FloCommand::SetDictationEmoji(value) => {
                self.state.dictation_rewrite_preferences.emoji = value;
                vec![ControllerEffect::PersistRewritePreferences]
            }
            FloCommand::SetDictationCustomInstructions(value) => {
                self.state.dictation_rewrite_preferences.custom_instructions = value;
                vec![ControllerEffect::PersistRewritePreferences]
            }
            FloCommand::SetDictationLiveFinalizationMode(mode) => {
                self.state
                    .dictation_rewrite_preferences
                    .live_finalization_mode = mode;
                vec![ControllerEffect::PersistRewritePreferences]
            }
            FloCommand::ApplyDictationRewritePreset(preset) => {
                apply_rewrite_preset(&mut self.state.dictation_rewrite_preferences, preset);
                self.state.status_message = Some(format!(
                    "Applied {} rewrite preset.",
                    rewrite_preset_display_name(preset)
                ));
                vec![ControllerEffect::PersistRewritePreferences]
            }
            FloCommand::SaveProviderCredential(credential) => {
                self.save_provider_credential_for(self.state.active_provider.clone(), credential)
            }
            FloCommand::SaveProviderCredentialForProvider {
                provider,
                credential,
            } => self.save_provider_credential_for(provider, credential),
            FloCommand::AddProviderCredential {
                provider,
                credential,
            } => self.add_provider_credential(provider, credential),
            FloCommand::UpdateProviderCredential {
                provider,
                index,
                credential,
            } => self.update_provider_credential(provider, index, credential),
            FloCommand::RemoveProviderCredential { provider, index } => {
                self.remove_provider_credential(provider, index)
            }
            FloCommand::ReorderProviderCredentials {
                provider,
                credentials,
            } => self.reorder_provider_credentials(provider, credentials),
            FloCommand::RemoveSavedProviderCredential => {
                self.remove_saved_provider_credential_for(self.state.active_provider.clone())
            }
            FloCommand::RemoveSavedProviderCredentialForProvider(provider) => {
                self.remove_saved_provider_credential_for(provider)
            }
            FloCommand::CopyProviderCredential { provider, index } => {
                let provider = normalize_provider_id(&provider);
                let credentials = self.provider_credentials_for(&provider);
                if let Some(credential) = credentials.get(index) {
                    self.state.status_message = Some(format!(
                        "{} API key copied to clipboard.",
                        provider_display_name(&provider)
                    ));
                    vec![ControllerEffect::CopyToClipboard(credential.clone())]
                } else {
                    self.state.status_message = Some("Could not copy API key.".to_string());
                    Vec::new()
                }
            }
            FloCommand::PasteLastTranscript => {
                if let Some(transcript) = self.state.last_dictation_transcript.clone() {
                    vec![ControllerEffect::InjectText {
                        text: transcript,
                        fallback_to_clipboard: true,
                    }]
                } else {
                    self.state.status_message = Some("No transcript available yet.".to_string());
                    Vec::new()
                }
            }
            FloCommand::UpdateVoice(voice) => {
                self.state.voice_preferences.voice = voice;
                vec![ControllerEffect::PersistVoicePreferences]
            }
            FloCommand::UpdateVoiceSpeed(speed) => {
                self.state.voice_preferences.speed = speed.clamp(0.25, 4.0);
                vec![ControllerEffect::PersistVoicePreferences]
            }
            FloCommand::ClearHistory => vec![ControllerEffect::ClearHistory],
            FloCommand::StartDictationFromHotkey => {
                if !capabilities.injection_supported {
                    self.state.recorder_state = RecorderState::Error(
                        "Injection is not supported in this context.".to_string(),
                    );
                    self.state.status_message = Some(canonical_error_message(
                        PlatformErrorCode::InjectionFailed,
                        None,
                    ));
                    return Vec::new();
                }

                self.state.recorder_state = RecorderState::Listening;
                self.state.live_transcript_preview.clear();
                vec![
                    ControllerEffect::ShowFloatingBar(FloatingBarState::Listening),
                    ControllerEffect::StartSpeechCapture,
                ]
            }
            FloCommand::StopDictationFromHotkey => {
                self.state.recorder_state = RecorderState::Transcribing;
                vec![
                    ControllerEffect::UpdateFloatingBar(FloatingBarState::Transcribing),
                    ControllerEffect::StopSpeechCapture,
                ]
            }
            FloCommand::ReadSelectedTextFromHotkey => {
                if capabilities.target_requires_elevation && !capabilities.elevated_mode {
                    if capabilities.can_prompt_for_elevation {
                        self.state.status_message = Some(canonical_error_message(
                            PlatformErrorCode::ElevationRequired,
                            None,
                        ));
                        return vec![ControllerEffect::PromptForElevation];
                    }
                    self.state.recorder_state = RecorderState::Error(
                        "Read selected blocked by privilege boundary.".to_string(),
                    );
                    return Vec::new();
                }

                self.state.recorder_state = RecorderState::Speaking;
                vec![
                    ControllerEffect::ReadSelected {
                        prefer_uia: capabilities.uia_available,
                        fallback_to_clipboard: capabilities.clipboard_fallback_available,
                    },
                    ControllerEffect::StartTts,
                    ControllerEffect::UpdateFloatingBar(FloatingBarState::Speaking),
                ]
            }
            FloCommand::PreviewCurrentVoice => {
                if self.state.is_voice_preview_in_progress
                    || self.state.recorder_state != RecorderState::Idle
                {
                    self.state.status_message = Some(canonical_error_message(
                        PlatformErrorCode::VoicePreviewBusy,
                        None,
                    ));
                    return Vec::new();
                }

                self.state.is_voice_preview_in_progress = true;
                self.state.recorder_state = RecorderState::Speaking;
                self.state.status_message = Some("Playing voice preview...".to_string());
                vec![
                    ControllerEffect::ShowFloatingBar(FloatingBarState::Speaking),
                    ControllerEffect::StartTts,
                ]
            }
            FloCommand::CompleteHotkeyConfirmation => {
                self.state.status_message = Some("Hotkey onboarding confirmed.".to_string());
                Vec::new()
            }
            FloCommand::ReorderProvidersInFailoverOrder(order) => {
                self.state.provider_routing_overrides.provider_order =
                    normalize_provider_order(order);
                vec![ControllerEffect::PersistRoutingOverrides]
            }
            FloCommand::AddProviderToFailoverOrder(provider) => {
                let normalized = normalize_provider_id(&provider);
                if normalized.is_empty() {
                    return Vec::new();
                }
                let mut order = normalize_provider_order(
                    self.state.provider_routing_overrides.provider_order.clone(),
                );
                if !order.contains(&normalized) {
                    order.push(normalized);
                }
                self.state.provider_routing_overrides.provider_order = order;
                vec![ControllerEffect::PersistRoutingOverrides]
            }
            FloCommand::RemoveProviderFromFailoverOrder(provider) => {
                let normalized = normalize_provider_id(&provider);
                let mut order = normalize_provider_order(
                    self.state.provider_routing_overrides.provider_order.clone(),
                );
                order.retain(|candidate| candidate != &normalized);
                self.state.provider_routing_overrides.provider_order = order;
                vec![ControllerEffect::PersistRoutingOverrides]
            }
            FloCommand::MoveProviderUpInFailoverOrder(provider) => {
                let normalized = normalize_provider_id(&provider);
                let mut order = normalize_provider_order(
                    self.state.provider_routing_overrides.provider_order.clone(),
                );
                if let Some(index) = order.iter().position(|candidate| candidate == &normalized) {
                    if index > 0 {
                        order.swap(index, index - 1);
                    }
                }
                self.state.provider_routing_overrides.provider_order = order;
                vec![ControllerEffect::PersistRoutingOverrides]
            }
            FloCommand::MoveProviderDownInFailoverOrder(provider) => {
                let normalized = normalize_provider_id(&provider);
                let mut order = normalize_provider_order(
                    self.state.provider_routing_overrides.provider_order.clone(),
                );
                if let Some(index) = order.iter().position(|candidate| candidate == &normalized) {
                    if index + 1 < order.len() {
                        order.swap(index, index + 1);
                    }
                }
                self.state.provider_routing_overrides.provider_order = order;
                vec![ControllerEffect::PersistRoutingOverrides]
            }
            FloCommand::SetProviderEnabledInFailover { provider, enabled } => {
                let normalized = normalize_provider_id(&provider);
                if normalized.is_empty() {
                    return Vec::new();
                }

                let mut allowed = self
                    .state
                    .provider_routing_overrides
                    .allowed_providers
                    .clone()
                    .unwrap_or_else(|| {
                        normalize_provider_order(
                            self.state.provider_routing_overrides.provider_order.clone(),
                        )
                    });
                allowed = normalize_provider_order(allowed);

                if enabled {
                    if !allowed.contains(&normalized) {
                        allowed.push(normalized);
                    }
                } else {
                    allowed.retain(|candidate| candidate != &normalized);
                }

                self.state.provider_routing_overrides.allowed_providers = if allowed.is_empty() {
                    None
                } else {
                    Some(allowed)
                };

                vec![ControllerEffect::PersistRoutingOverrides]
            }
            FloCommand::SetFailoverAllowCrossProviderFallback(enabled) => {
                self.state
                    .provider_routing_overrides
                    .allow_cross_provider_fallback = Some(enabled);
                vec![ControllerEffect::PersistRoutingOverrides]
            }
            FloCommand::SetFailoverMaxAttempts(value) => {
                self.state.provider_routing_overrides.max_attempts = Some(value.max(1));
                vec![ControllerEffect::PersistRoutingOverrides]
            }
            FloCommand::SetFailoverFailureThreshold(value) => {
                self.state.provider_routing_overrides.failure_threshold = Some(value.max(1));
                vec![ControllerEffect::PersistRoutingOverrides]
            }
            FloCommand::SetFailoverCooldownSeconds(value) => {
                self.state.provider_routing_overrides.cooldown_seconds = Some(value);
                vec![ControllerEffect::PersistRoutingOverrides]
            }
        }
    }

    pub fn provider_supports_oauth(&self, provider: &str) -> bool {
        normalize_provider_id(provider) == "openai"
    }

    pub fn provider_display_name(&self, provider: &str) -> String {
        provider_display_name(provider)
    }

    pub fn provider_logo_url(&self, provider: &str) -> Option<String> {
        let provider = normalize_provider_id(provider);
        if provider.is_empty() {
            return None;
        }
        Some(format!("https://models.dev/logos/{provider}.svg"))
    }

    pub fn provider_models(&self, provider: &str, query: &str) -> Vec<String> {
        let provider = normalize_provider_id(provider);
        if provider.is_empty() {
            return Vec::new();
        }
        let mut models = self
            .state
            .models_catalog
            .get(&provider)
            .cloned()
            .unwrap_or_default();

        let active = self.active_rewrite_model(&provider);
        if !active.is_empty() && !models.contains(&active) {
            models.insert(0, active);
        }

        let query = query.trim().to_ascii_lowercase();
        if query.is_empty() {
            return models;
        }

        models
            .into_iter()
            .filter(|model| model.to_ascii_lowercase().contains(&query))
            .collect()
    }

    pub fn active_rewrite_model(&self, provider: &str) -> String {
        self.rewrite_model_override(provider).unwrap_or_default()
    }

    pub fn rewrite_model_override(&self, provider: &str) -> Option<String> {
        let provider = normalize_provider_id(provider);
        self.state
            .provider_routing_overrides
            .rewrite_models_by_provider
            .as_ref()
            .and_then(|overrides| overrides.get(&provider))
            .cloned()
    }

    pub fn rewrite_model_override_for_credential(
        &self,
        provider: &str,
        credential_index: usize,
    ) -> Option<String> {
        let provider = normalize_provider_id(provider);
        self.state
            .provider_routing_overrides
            .rewrite_models_by_provider_credential_index
            .as_ref()
            .and_then(|provider_map| provider_map.get(&provider))
            .and_then(|index_map| index_map.get(&credential_index.to_string()))
            .cloned()
    }

    pub fn active_rewrite_model_for_credential(
        &self,
        provider: &str,
        credential_index: usize,
    ) -> String {
        self.rewrite_model_override_for_credential(provider, credential_index)
            .or_else(|| self.rewrite_model_override(provider))
            .unwrap_or_default()
    }

    pub fn provider_credential_source_label(&self, provider: &str) -> Option<String> {
        let key_count = self.provider_credentials_for(provider).len();
        if key_count == 0 {
            None
        } else if key_count == 1 {
            Some("Saved API key".to_string())
        } else {
            Some(format!("Saved API keys ({key_count})"))
        }
    }

    pub fn can_remove_saved_provider_credential(&self, provider: &str) -> bool {
        !self.provider_credentials_for(provider).is_empty()
    }

    pub fn configured_key_count(&self, provider: &str) -> usize {
        self.provider_credentials_for(provider).len()
    }

    pub fn provider_credentials(&self, provider: &str) -> Vec<String> {
        self.provider_credentials_for(provider)
    }

    pub fn provider_supports_failover_operation(&self, provider: &str) -> bool {
        !normalize_provider_id(provider).is_empty()
    }

    pub fn provider_enabled_for_failover(&self, provider: &str) -> bool {
        let provider = normalize_provider_id(provider);
        if provider.is_empty() {
            return false;
        }

        if let Some(allowed) = self
            .state
            .provider_routing_overrides
            .allowed_providers
            .as_ref()
        {
            return allowed
                .iter()
                .any(|candidate| normalize_provider_id(candidate) == provider);
        }

        self.state
            .provider_routing_overrides
            .provider_order
            .iter()
            .any(|candidate| normalize_provider_id(candidate) == provider)
    }

    pub fn can_move_provider_up_in_failover_order(&self, provider: &str) -> bool {
        let provider = normalize_provider_id(provider);
        let order =
            normalize_provider_order(self.state.provider_routing_overrides.provider_order.clone());
        order
            .iter()
            .position(|candidate| candidate == &provider)
            .is_some_and(|index| index > 0)
    }

    pub fn can_move_provider_down_in_failover_order(&self, provider: &str) -> bool {
        let provider = normalize_provider_id(provider);
        let order =
            normalize_provider_order(self.state.provider_routing_overrides.provider_order.clone());
        order
            .iter()
            .position(|candidate| candidate == &provider)
            .is_some_and(|index| index + 1 < order.len())
    }

    fn missing_permissions(&self) -> Vec<PermissionKind> {
        let mut missing = Vec::new();
        if self.state.permission_status.microphone != flo_domain::PermissionState::Granted {
            missing.push(PermissionKind::Microphone);
        }
        if self.state.permission_status.accessibility != flo_domain::PermissionState::Granted {
            missing.push(PermissionKind::Accessibility);
        }
        if self.state.permission_status.input_monitoring != flo_domain::PermissionState::Granted {
            missing.push(PermissionKind::InputMonitoring);
        }
        missing
    }

    fn provider_credentials_for(&self, provider: &str) -> Vec<String> {
        let provider = normalize_provider_id(provider);
        self.state
            .provider_credentials
            .get(&provider)
            .cloned()
            .unwrap_or_default()
    }

    fn has_any_saved_provider_credential(&self) -> bool {
        self.state
            .provider_credentials
            .values()
            .any(|credentials| !credentials.is_empty())
    }

    fn save_provider_credential_for(
        &mut self,
        provider: String,
        credential_input: String,
    ) -> Vec<ControllerEffect> {
        let provider = normalize_provider_id(&provider);
        if provider.is_empty() {
            self.state.status_message = Some("Invalid provider.".to_string());
            return Vec::new();
        }

        let normalized = parse_credential_input(&credential_input);
        if normalized.is_empty() {
            self.state.status_message = Some("API key is empty.".to_string());
            return Vec::new();
        }

        self.persist_provider_credentials(provider, normalized, None)
    }

    fn add_provider_credential(
        &mut self,
        provider: String,
        credential_input: String,
    ) -> Vec<ControllerEffect> {
        let provider = normalize_provider_id(&provider);
        if provider.is_empty() {
            self.state.status_message = Some("Invalid provider.".to_string());
            return Vec::new();
        }
        let additions = parse_credential_input(&credential_input);
        if additions.is_empty() {
            self.state.status_message = Some("API key is empty.".to_string());
            return Vec::new();
        }

        let existing = self.provider_credentials_for(&provider);
        let merged = normalize_credential_pool([existing, additions].concat());
        let provider_display = provider_display_name(&provider);
        self.persist_provider_credentials(
            provider,
            merged.clone(),
            Some(format!(
                "{provider_display} API key added. Saved keys: {}.",
                merged.len()
            )),
        )
    }

    fn update_provider_credential(
        &mut self,
        provider: String,
        index: usize,
        credential_input: String,
    ) -> Vec<ControllerEffect> {
        let provider = normalize_provider_id(&provider);
        if provider.is_empty() {
            self.state.status_message = Some("Invalid provider.".to_string());
            return Vec::new();
        }
        let replacements = parse_credential_input(&credential_input);
        let Some(replacement) = replacements.first().cloned() else {
            self.state.status_message = Some("API key is empty.".to_string());
            return Vec::new();
        };

        let mut existing = self.provider_credentials_for(&provider);
        if !existing.get(index).is_some() {
            self.state.status_message = Some("Could not update API key.".to_string());
            return Vec::new();
        }
        existing[index] = replacement;
        let provider_display = provider_display_name(&provider);
        self.persist_provider_credentials(
            provider,
            existing,
            Some(format!("{provider_display} API key updated.")),
        )
    }

    fn remove_provider_credential(
        &mut self,
        provider: String,
        index: usize,
    ) -> Vec<ControllerEffect> {
        let provider = normalize_provider_id(&provider);
        if provider.is_empty() {
            self.state.status_message = Some("Invalid provider.".to_string());
            return Vec::new();
        }

        let mut existing = self.provider_credentials_for(&provider);
        if !existing.get(index).is_some() {
            self.state.status_message = Some("Could not remove API key.".to_string());
            return Vec::new();
        }
        existing.remove(index);
        let provider_display = provider_display_name(&provider);
        if existing.is_empty() {
            return self.remove_saved_provider_credential_for(provider);
        }
        self.persist_provider_credentials(
            provider,
            existing.clone(),
            Some(format!(
                "{provider_display} API key removed. Saved keys: {}.",
                existing.len()
            )),
        )
    }

    fn reorder_provider_credentials(
        &mut self,
        provider: String,
        credentials: Vec<String>,
    ) -> Vec<ControllerEffect> {
        let provider = normalize_provider_id(&provider);
        if provider.is_empty() {
            self.state.status_message = Some("Invalid provider.".to_string());
            return Vec::new();
        }
        let existing = self.provider_credentials_for(&provider);
        if existing.len() <= 1 {
            return Vec::new();
        }

        let allowed = existing
            .iter()
            .map(|credential| credential.trim().to_string())
            .collect::<Vec<_>>();
        let mut seen = Vec::new();
        let mut reordered = Vec::new();
        for credential in credentials {
            let normalized = credential.trim().to_string();
            if normalized.is_empty() || !allowed.contains(&normalized) || seen.contains(&normalized)
            {
                continue;
            }
            seen.push(normalized.clone());
            reordered.push(normalized);
        }
        for credential in existing {
            if !seen.contains(&credential) {
                seen.push(credential.clone());
                reordered.push(credential);
            }
        }

        if reordered == self.provider_credentials_for(&provider) {
            return Vec::new();
        }
        let provider_display = provider_display_name(&provider);
        self.persist_provider_credentials(
            provider,
            reordered,
            Some(format!("Updated {provider_display} API key order.")),
        )
    }

    fn remove_saved_provider_credential_for(&mut self, provider: String) -> Vec<ControllerEffect> {
        let provider = normalize_provider_id(&provider);
        if provider.is_empty() {
            self.state.status_message = Some("Invalid provider.".to_string());
            return Vec::new();
        }

        self.state.provider_credentials.remove(&provider);
        self.state.uses_saved_provider_credential = self.has_any_saved_provider_credential();
        if !self.state.uses_saved_provider_credential {
            self.state.auth_state = AuthState::LoggedOut;
            self.state.status_message =
                Some("Login required to use dictation and read-aloud.".to_string());
        } else if let Some(first_token) = self
            .state
            .provider_credentials
            .values()
            .find_map(|credentials| credentials.first().cloned())
        {
            self.state.auth_state = AuthState::LoggedIn(local_credential_session(&first_token));
        }

        let provider_display = provider_display_name(&provider);
        if self.state.uses_saved_provider_credential {
            self.state
                .status_message
                .replace(format!("Removed saved {provider_display} API key."));
        }
        vec![ControllerEffect::ClearProviderCredentials { provider }]
    }

    fn persist_provider_credentials(
        &mut self,
        provider: String,
        credentials: Vec<String>,
        success_message: Option<String>,
    ) -> Vec<ControllerEffect> {
        let provider = normalize_provider_id(&provider);
        let credentials = normalize_credential_pool(credentials);
        if credentials.is_empty() {
            self.state.status_message = Some("API key is empty.".to_string());
            return Vec::new();
        }

        self.state
            .provider_credentials
            .insert(provider.clone(), credentials.clone());
        self.state.uses_saved_provider_credential = true;
        self.state.active_provider = provider.clone();
        self.state.auth_state = AuthState::LoggedIn(local_credential_session(&credentials[0]));
        self.ensure_provider_in_failover_rotation(&provider);

        let provider_display = provider_display_name(&provider);
        self.state.status_message = Some(success_message.unwrap_or_else(|| {
            default_saved_credentials_status_message(&provider_display, credentials.len())
        }));

        vec![ControllerEffect::PersistProviderCredentials {
            provider,
            credentials,
        }]
    }

    fn ensure_provider_in_failover_rotation(&mut self, provider: &str) {
        let normalized = normalize_provider_id(provider);
        if normalized.is_empty() {
            return;
        }

        let mut order =
            normalize_provider_order(self.state.provider_routing_overrides.provider_order.clone());
        if !order.contains(&normalized) {
            order.push(normalized);
        }
        self.state.provider_routing_overrides.provider_order = order;
    }

    pub fn apply_event(&mut self, event: ControllerEvent) -> Vec<ControllerEffect> {
        match event {
            ControllerEvent::AuthRestored(Some(session)) => {
                self.state.auth_state = AuthState::LoggedIn(session);
                self.state.status_message = None;
                Vec::new()
            }
            ControllerEvent::AuthRestored(None) => {
                self.state.auth_state = AuthState::LoggedOut;
                self.state.status_message = Some(canonical_error_message(
                    PlatformErrorCode::Unauthorized,
                    None,
                ));
                Vec::new()
            }
            ControllerEvent::ProviderCredentialsLoaded {
                provider,
                credentials,
            } => {
                let provider = normalize_provider_id(&provider);
                let normalized = normalize_credential_pool(credentials);
                if provider.is_empty() {
                    return Vec::new();
                }

                if normalized.is_empty() {
                    self.state.provider_credentials.remove(&provider);
                } else {
                    self.state
                        .provider_credentials
                        .insert(provider.clone(), normalized.clone());
                    self.state.active_provider = provider.clone();
                }

                self.state.uses_saved_provider_credential =
                    self.has_any_saved_provider_credential();
                if self.state.uses_saved_provider_credential {
                    if let Some(token) = normalized.first() {
                        self.state.auth_state =
                            AuthState::LoggedIn(local_credential_session(token));
                    }
                    self.state.status_message =
                        Some("Using API key mode with provider failover.".to_string());
                }
                Vec::new()
            }
            ControllerEvent::ModelsCatalogLoaded { provider, models } => {
                let provider = normalize_provider_id(&provider);
                if provider.is_empty() {
                    return Vec::new();
                }
                self.state
                    .models_catalog
                    .insert(provider, normalize_model_catalog(models));
                Vec::new()
            }
            ControllerEvent::CaptureStarted => {
                self.state.recorder_state = RecorderState::Listening;
                vec![ControllerEffect::ShowFloatingBar(
                    FloatingBarState::Listening,
                )]
            }
            ControllerEvent::TranscriptPartial(partial) => {
                let normalized = normalize_transcript(&partial);
                if normalized.is_empty() || !self.state.live_dictation_enabled {
                    return Vec::new();
                }

                self.state.live_transcript_preview = normalized;
                Vec::new()
            }
            ControllerEvent::CaptureStopped { transcript } => {
                let normalized = normalize_transcript(&transcript);
                if normalized.is_empty() {
                    self.state.recorder_state = RecorderState::Error(canonical_error_message(
                        PlatformErrorCode::EmptyAudioCapture,
                        None,
                    ));
                    self.state.status_message = Some(canonical_error_message(
                        PlatformErrorCode::EmptyAudioCapture,
                        None,
                    ));
                    return vec![ControllerEffect::UpdateFloatingBar(FloatingBarState::Error)];
                }

                let plan = if self.state.live_dictation_enabled {
                    plan_live_finalization(
                        &self.state.live_transcript_preview,
                        &normalized,
                        self.state
                            .dictation_rewrite_preferences
                            .live_finalization_mode,
                    )
                } else {
                    LiveFinalizationPlan::InjectDelta(normalized.clone())
                };

                self.state.live_transcript_preview = normalized;
                self.state.last_dictation_transcript =
                    Some(self.state.live_transcript_preview.clone());
                match plan {
                    LiveFinalizationPlan::Noop => {
                        self.state.recorder_state = RecorderState::Idle;
                        vec![ControllerEffect::HideFloatingBar]
                    }
                    _ => {
                        self.state.recorder_state = RecorderState::Injecting;
                        vec![
                            ControllerEffect::UpdateFloatingBar(FloatingBarState::Injecting),
                            ControllerEffect::FinalizeDictation(plan),
                        ]
                    }
                }
            }
            ControllerEvent::SelectionRead { method, .. } => {
                self.state.last_selection_read_method = Some(method);
                self.state.recorder_state = RecorderState::Speaking;
                self.state.status_message = None;
                vec![ControllerEffect::UpdateFloatingBar(
                    FloatingBarState::Speaking,
                )]
            }
            ControllerEvent::InjectionCompleted => {
                self.state.recorder_state = RecorderState::Idle;
                vec![ControllerEffect::HideFloatingBar]
            }
            ControllerEvent::InjectionFailed(reason) => {
                let code = match reason {
                    TextInjectionFailureReason::SecureField => {
                        PlatformErrorCode::InjectionSecureInput
                    }
                    TextInjectionFailureReason::IntegrityMismatch { .. } => {
                        PlatformErrorCode::ElevationRequired
                    }
                    TextInjectionFailureReason::GenericFailure => {
                        PlatformErrorCode::InjectionFailed
                    }
                };
                self.state.recorder_state =
                    RecorderState::Error(canonical_error_message(code, None));
                self.state.status_message = Some(canonical_error_message(code, None));

                if code == PlatformErrorCode::ElevationRequired {
                    return vec![
                        ControllerEffect::UpdateFloatingBar(FloatingBarState::Error),
                        ControllerEffect::PromptForElevation,
                    ];
                }

                vec![ControllerEffect::UpdateFloatingBar(FloatingBarState::Error)]
            }
            ControllerEvent::ElevatedRelaunchRequested => {
                self.state.status_message = Some(canonical_error_message(
                    PlatformErrorCode::ElevationRequired,
                    None,
                ));
                Vec::new()
            }
            ControllerEvent::PermissionStatusUpdated(status) => {
                self.state.permission_status = status;
                Vec::new()
            }
            ControllerEvent::Error(code) => {
                self.state.status_message = Some(canonical_error_message(code, None));
                Vec::new()
            }
            ControllerEvent::TtsCompleted => {
                self.state.recorder_state = RecorderState::Idle;
                if self.state.is_voice_preview_in_progress {
                    self.state.is_voice_preview_in_progress = false;
                    self.state
                        .status_message
                        .replace("Voice preview completed.".to_string());
                } else {
                    self.state.status_message.replace(canonical_error_message(
                        PlatformErrorCode::ReadAloudCompleted,
                        None,
                    ));
                }
                vec![ControllerEffect::HideFloatingBar]
            }
            ControllerEvent::TtsCanceled => {
                self.state.recorder_state = RecorderState::Idle;
                if self.state.is_voice_preview_in_progress {
                    self.state.is_voice_preview_in_progress = false;
                    self.state
                        .status_message
                        .replace("Voice preview canceled.".to_string());
                } else {
                    self.state.status_message.replace(canonical_error_message(
                        PlatformErrorCode::ReadAloudCanceled,
                        None,
                    ));
                }
                vec![ControllerEffect::HideFloatingBar]
            }
            ControllerEvent::VoicePreviewCompleted => {
                self.state.is_voice_preview_in_progress = false;
                self.state.recorder_state = RecorderState::Idle;
                self.state
                    .status_message
                    .replace("Voice preview completed.".to_string());
                vec![ControllerEffect::HideFloatingBar]
            }
            ControllerEvent::VoicePreviewCanceled => {
                self.state.is_voice_preview_in_progress = false;
                self.state.recorder_state = RecorderState::Idle;
                self.state
                    .status_message
                    .replace("Voice preview canceled.".to_string());
                vec![ControllerEffect::HideFloatingBar]
            }
        }
    }
}

pub fn plan_live_finalization(
    live_injected_transcript: &str,
    finalized_text: &str,
    mode: DictationLiveFinalizationMode,
) -> LiveFinalizationPlan {
    let normalized_final = normalize_transcript(finalized_text);
    if normalized_final.is_empty() {
        return LiveFinalizationPlan::Noop;
    }

    match mode {
        DictationLiveFinalizationMode::AppendOnly => {
            if live_injected_transcript.is_empty() {
                return LiveFinalizationPlan::InjectDelta(normalized_final);
            }

            if let Some(delta) = normalized_final.strip_prefix(live_injected_transcript) {
                if delta.is_empty() {
                    LiveFinalizationPlan::Noop
                } else {
                    LiveFinalizationPlan::InjectDelta(delta.to_string())
                }
            } else {
                LiveFinalizationPlan::CopyFinalToClipboard(normalized_final)
            }
        }
        DictationLiveFinalizationMode::ReplaceWithFinal => {
            if normalize_transcript(live_injected_transcript) == normalized_final {
                LiveFinalizationPlan::Noop
            } else {
                LiveFinalizationPlan::ReplaceWithFinal(normalized_final)
            }
        }
    }
}

fn apply_rewrite_preset(
    preferences: &mut DictationRewritePreferences,
    preset: DictationRewritePreset,
) {
    let (base_tone, warmth, enthusiasm, headers_and_lists, emoji) = match preset {
        DictationRewritePreset::Default => (
            DictationBaseTone::Default,
            DictationStyleLevel::Default,
            DictationStyleLevel::Default,
            DictationStyleLevel::Default,
            DictationStyleLevel::Less,
        ),
        DictationRewritePreset::Professional => (
            DictationBaseTone::Professional,
            DictationStyleLevel::Less,
            DictationStyleLevel::Less,
            DictationStyleLevel::More,
            DictationStyleLevel::Less,
        ),
        DictationRewritePreset::Friendly => (
            DictationBaseTone::Friendly,
            DictationStyleLevel::More,
            DictationStyleLevel::Default,
            DictationStyleLevel::Default,
            DictationStyleLevel::Default,
        ),
        DictationRewritePreset::Candid => (
            DictationBaseTone::Candid,
            DictationStyleLevel::Default,
            DictationStyleLevel::Less,
            DictationStyleLevel::Default,
            DictationStyleLevel::Less,
        ),
        DictationRewritePreset::Efficient => (
            DictationBaseTone::Efficient,
            DictationStyleLevel::Less,
            DictationStyleLevel::Less,
            DictationStyleLevel::More,
            DictationStyleLevel::Less,
        ),
        DictationRewritePreset::Nerdy => (
            DictationBaseTone::Nerdy,
            DictationStyleLevel::Default,
            DictationStyleLevel::More,
            DictationStyleLevel::More,
            DictationStyleLevel::Less,
        ),
        DictationRewritePreset::Quirky => (
            DictationBaseTone::Quirky,
            DictationStyleLevel::More,
            DictationStyleLevel::More,
            DictationStyleLevel::Default,
            DictationStyleLevel::More,
        ),
    };

    preferences.base_tone = base_tone;
    preferences.warmth = warmth;
    preferences.enthusiasm = enthusiasm;
    preferences.headers_and_lists = headers_and_lists;
    preferences.emoji = emoji;
}

fn rewrite_preset_display_name(preset: DictationRewritePreset) -> &'static str {
    match preset {
        DictationRewritePreset::Default => "Default",
        DictationRewritePreset::Professional => "Professional",
        DictationRewritePreset::Friendly => "Friendly",
        DictationRewritePreset::Candid => "Candid",
        DictationRewritePreset::Efficient => "Efficient",
        DictationRewritePreset::Nerdy => "Nerdy",
        DictationRewritePreset::Quirky => "Quirky",
    }
}

fn normalize_provider_id(raw: &str) -> String {
    raw.trim().to_ascii_lowercase()
}

fn normalize_provider_order(values: Vec<String>) -> Vec<String> {
    let mut order = Vec::new();
    for value in values {
        let normalized = normalize_provider_id(&value);
        if normalized.is_empty() || order.contains(&normalized) {
            continue;
        }
        order.push(normalized);
    }
    order
}

fn provider_display_name(provider: &str) -> String {
    match normalize_provider_id(provider).as_str() {
        "openai" => "OpenAI".to_string(),
        "gemini" => "Gemini".to_string(),
        "anthropic" => "Anthropic".to_string(),
        other if !other.is_empty() => {
            let mut chars = other.chars();
            if let Some(first) = chars.next() {
                format!(
                    "{}{}",
                    first.to_ascii_uppercase(),
                    chars.collect::<String>()
                )
            } else {
                "Provider".to_string()
            }
        }
        _ => "Provider".to_string(),
    }
}

fn parse_credential_input(raw: &str) -> Vec<String> {
    let values = raw
        .split(|ch| [',', ';', '\n', '\t'].contains(&ch))
        .map(str::trim)
        .filter(|candidate| !candidate.is_empty())
        .map(ToString::to_string)
        .collect::<Vec<_>>();
    normalize_credential_pool(values)
}

fn normalize_credential_pool(credentials: Vec<String>) -> Vec<String> {
    let mut out = Vec::new();
    for credential in credentials {
        let normalized = credential.trim().to_string();
        if normalized.is_empty() || out.contains(&normalized) {
            continue;
        }
        out.push(normalized);
    }
    out
}

fn normalize_model_catalog(models: Vec<String>) -> Vec<String> {
    let mut out = Vec::new();
    for model in models {
        let normalized = model.trim().to_string();
        if normalized.is_empty() || out.contains(&normalized) {
            continue;
        }
        out.push(normalized);
    }
    out
}

fn default_saved_credentials_status_message(provider_display: &str, key_count: usize) -> String {
    if key_count == 1 {
        format!("{provider_display} API key saved in keychain.")
    } else {
        format!("{provider_display} API keys saved in keychain ({key_count}).")
    }
}

fn local_credential_session(token: &str) -> UserSession {
    UserSession {
        access_token: token.to_string(),
        refresh_token: None,
        token_type: "Bearer".to_string(),
        expires_at_unix_ms: i64::MAX,
        account_id: None,
    }
}

pub fn canonical_error_message(code: PlatformErrorCode, detail: Option<&str>) -> String {
    match code {
        PlatformErrorCode::OAuthMissingConfiguration => {
            "ChatGPT OAuth configuration is missing.".to_string()
        }
        PlatformErrorCode::OAuthFailed => format!("OAuth failed: {}", detail.unwrap_or("Unknown")),
        PlatformErrorCode::OAuthStateMismatch => "OAuth failed: State mismatch".to_string(),
        PlatformErrorCode::OAuthAuthorizationCodeMissing => {
            "OAuth failed: Authorization code missing".to_string()
        }
        PlatformErrorCode::Unauthorized => "You are not authenticated.".to_string(),
        PlatformErrorCode::EmptyAudioCapture => "No audio was captured.".to_string(),
        PlatformErrorCode::NoSelectedText => "No selected text.".to_string(),
        PlatformErrorCode::InjectionFailed => {
            "Failed to inject transcript into the focused app.".to_string()
        }
        PlatformErrorCode::InjectionSecureInput => {
            "Injection blocked while secure input is active.".to_string()
        }
        PlatformErrorCode::PermissionDenied => {
            format!("Permission denied: {}.", detail.unwrap_or("Unknown"))
        }
        PlatformErrorCode::FeatureDisabled => format!(
            "{} is disabled by configuration.",
            detail.unwrap_or("Feature")
        ),
        PlatformErrorCode::NetworkError => {
            format!("Network error: {}", detail.unwrap_or("Unknown"))
        }
        PlatformErrorCode::PersistenceError => {
            format!("Persistence error: {}", detail.unwrap_or("Unknown"))
        }
        PlatformErrorCode::ElevationRequired => {
            "The focused app requires elevated mode. Please relaunch flo as admin.".to_string()
        }
        PlatformErrorCode::DictationClipboardFallback => {
            "Couldn't type transcript. Copied to clipboard instead.".to_string()
        }
        PlatformErrorCode::DictationClipboardFallbackFailed => {
            "Couldn't type transcript and could not copy to clipboard.".to_string()
        }
        PlatformErrorCode::LiveTypingPaused => {
            format!(
                "Live typing paused: {}. Final transcript will still complete.",
                detail.unwrap_or("Unknown")
            )
        }
        PlatformErrorCode::LiveFinalizationAppendCopied => {
            "Live transcript differed from final model output. Final transcript copied to clipboard."
                .to_string()
        }
        PlatformErrorCode::LiveFinalizationAppendCopyFailed => {
            "Live transcript differed from final model output. Could not copy final transcript to clipboard."
                .to_string()
        }
        PlatformErrorCode::LiveFinalizationReplace => {
            "Replaced live draft with final transcript.".to_string()
        }
        PlatformErrorCode::ReadAloudCanceled => "Read-aloud canceled.".to_string(),
        PlatformErrorCode::ReadAloudCompleted => "Read-aloud completed.".to_string(),
        PlatformErrorCode::VoicePreviewBusy => {
            "Wait for the current action to finish, then try voice preview again.".to_string()
        }
    }
}

fn normalize_transcript(input: &str) -> String {
    input.trim().to_string()
}

#[cfg(test)]
mod tests {
    use flo_domain::{
        AppIntegrityLevel, AuthState, DictationBaseTone, DictationLiveFinalizationMode,
        DictationRewritePreset, FloatingBarState, KeyCombo, LogicalKey, PermissionKind,
        PermissionState, PermissionStatus, RecorderState, ShortcutAction, ShortcutBinding,
        ShortcutModifiers,
    };

    use super::{
        canonical_error_message, plan_live_finalization, ControllerEffect, ControllerEvent,
        FloCommand, FloController, LiveFinalizationPlan,
    };
    use crate::capabilities::PlatformCapabilities;

    #[test]
    fn start_and_stop_dictation_transitions_state() {
        let mut controller = FloController::new();
        let capabilities = PlatformCapabilities::win32_default();

        let start = controller.dispatch(FloCommand::StartDictationFromHotkey, &capabilities);
        assert!(start.contains(&ControllerEffect::StartSpeechCapture));

        let stop = controller.dispatch(FloCommand::StopDictationFromHotkey, &capabilities);
        assert!(stop.contains(&ControllerEffect::StopSpeechCapture));
    }

    #[test]
    fn read_selected_prompts_for_elevation_when_needed() {
        let mut controller = FloController::new();
        let capabilities = PlatformCapabilities {
            target_requires_elevation: true,
            elevated_mode: false,
            ..PlatformCapabilities::win32_default()
        };

        let effects = controller.dispatch(FloCommand::ReadSelectedTextFromHotkey, &capabilities);
        assert_eq!(effects, vec![ControllerEffect::PromptForElevation]);
    }

    #[test]
    fn read_selected_in_elevated_mode_skips_prompt_and_starts_read_flow() {
        let mut controller = FloController::new();
        let capabilities = PlatformCapabilities {
            target_requires_elevation: true,
            elevated_mode: true,
            ..PlatformCapabilities::win32_default()
        };

        let effects = controller.dispatch(FloCommand::ReadSelectedTextFromHotkey, &capabilities);
        assert_eq!(
            effects,
            vec![
                ControllerEffect::ReadSelected {
                    prefer_uia: true,
                    fallback_to_clipboard: true,
                },
                ControllerEffect::StartTts,
                ControllerEffect::UpdateFloatingBar(FloatingBarState::Speaking),
            ]
        );
        assert_eq!(controller.state.recorder_state, RecorderState::Speaking);
    }

    #[test]
    fn update_shortcut_replaces_existing_action_binding() {
        let mut controller = FloController::new();
        let capabilities = PlatformCapabilities::win32_default();

        let first = ShortcutBinding {
            action: ShortcutAction::DictationHold,
            combo: KeyCombo {
                key: LogicalKey::Character('D'),
                modifiers: ShortcutModifiers {
                    ctrl: true,
                    ..Default::default()
                },
                key_display: "D".to_string(),
            },
            enabled: true,
        };

        let second = ShortcutBinding {
            action: ShortcutAction::DictationHold,
            combo: KeyCombo {
                key: LogicalKey::Character('F'),
                modifiers: ShortcutModifiers {
                    ctrl: true,
                    shift: true,
                    ..Default::default()
                },
                key_display: "F".to_string(),
            },
            enabled: true,
        };

        controller.dispatch(FloCommand::UpdateShortcut(first), &capabilities);
        controller.dispatch(FloCommand::UpdateShortcut(second.clone()), &capabilities);

        assert_eq!(controller.state.shortcut_bindings.len(), 1);
        assert_eq!(controller.state.shortcut_bindings[0], second);
    }

    #[test]
    fn live_finalization_mode_is_mutable() {
        let mut controller = FloController::new();
        let capabilities = PlatformCapabilities::win32_default();

        controller.dispatch(
            FloCommand::SetDictationLiveFinalizationMode(
                DictationLiveFinalizationMode::ReplaceWithFinal,
            ),
            &capabilities,
        );

        assert_eq!(
            controller
                .state
                .dictation_rewrite_preferences
                .live_finalization_mode,
            DictationLiveFinalizationMode::ReplaceWithFinal
        );
    }

    #[test]
    fn append_only_finalization_extracts_delta() {
        let plan = plan_live_finalization(
            "hello world",
            "hello world from flo",
            DictationLiveFinalizationMode::AppendOnly,
        );

        assert_eq!(
            plan,
            LiveFinalizationPlan::InjectDelta(" from flo".to_string())
        );
    }

    #[test]
    fn append_only_finalization_falls_back_to_clipboard_when_prefix_mismatch() {
        let plan = plan_live_finalization(
            "hello world",
            "greetings from flo",
            DictationLiveFinalizationMode::AppendOnly,
        );

        assert_eq!(
            plan,
            LiveFinalizationPlan::CopyFinalToClipboard("greetings from flo".to_string())
        );
    }

    #[test]
    fn replace_with_final_overwrites_live_draft() {
        let plan = plan_live_finalization(
            "draft text",
            "final rewritten text",
            DictationLiveFinalizationMode::ReplaceWithFinal,
        );

        assert_eq!(
            plan,
            LiveFinalizationPlan::ReplaceWithFinal("final rewritten text".to_string())
        );
    }

    #[test]
    fn capture_stopped_emits_finalize_effect() {
        let mut controller = FloController::new();
        controller.state.live_dictation_enabled = true;
        controller.state.live_transcript_preview = "hello".to_string();

        let effects = controller.apply_event(ControllerEvent::CaptureStopped {
            transcript: "hello there".to_string(),
        });

        assert!(effects.contains(&ControllerEffect::UpdateFloatingBar(
            FloatingBarState::Injecting,
        )));
    }

    #[test]
    fn canonical_error_message_matches_secure_input_copy() {
        let message =
            canonical_error_message(flo_domain::PlatformErrorCode::InjectionSecureInput, None);
        assert_eq!(message, "Injection blocked while secure input is active.");
    }

    #[test]
    fn integrity_mismatch_requests_elevation() {
        let mut controller = FloController::new();

        let effects = controller.apply_event(ControllerEvent::InjectionFailed(
            flo_domain::TextInjectionFailureReason::IntegrityMismatch {
                app_integrity: AppIntegrityLevel::Medium,
                target_integrity: AppIntegrityLevel::High,
            },
        ));

        assert!(effects.contains(&ControllerEffect::PromptForElevation));
    }

    #[test]
    fn paste_last_transcript_emits_inject_effect_with_fallback() {
        let mut controller = FloController::new();
        controller.state.last_dictation_transcript = Some("last text".to_string());

        let effects = controller.dispatch(
            FloCommand::PasteLastTranscript,
            &PlatformCapabilities::win32_default(),
        );

        assert_eq!(
            effects,
            vec![ControllerEffect::InjectText {
                text: "last text".to_string(),
                fallback_to_clipboard: true,
            }]
        );
    }

    #[test]
    fn paste_last_transcript_without_history_sets_status_message() {
        let mut controller = FloController::new();

        let effects = controller.dispatch(
            FloCommand::PasteLastTranscript,
            &PlatformCapabilities::win32_default(),
        );

        assert!(effects.is_empty());
        assert_eq!(
            controller.state.status_message.as_deref(),
            Some("No transcript available yet.")
        );
    }

    #[test]
    fn update_voice_and_speed_persists_preferences() {
        let mut controller = FloController::new();
        let capabilities = PlatformCapabilities::win32_default();

        let update_voice =
            controller.dispatch(FloCommand::UpdateVoice("verse".to_string()), &capabilities);
        let update_speed = controller.dispatch(FloCommand::UpdateVoiceSpeed(9.5), &capabilities);

        assert_eq!(
            update_voice,
            vec![ControllerEffect::PersistVoicePreferences]
        );
        assert_eq!(
            update_speed,
            vec![ControllerEffect::PersistVoicePreferences]
        );
        assert_eq!(controller.state.voice_preferences.voice, "verse");
        assert_eq!(controller.state.voice_preferences.speed, 4.0);
    }

    #[test]
    fn apply_rewrite_preset_sets_expected_style_profile() {
        let mut controller = FloController::new();
        let capabilities = PlatformCapabilities::win32_default();

        let effects = controller.dispatch(
            FloCommand::ApplyDictationRewritePreset(DictationRewritePreset::Professional),
            &capabilities,
        );

        assert_eq!(effects, vec![ControllerEffect::PersistRewritePreferences]);
        assert_eq!(
            controller.state.dictation_rewrite_preferences.base_tone,
            DictationBaseTone::Professional
        );
        assert_eq!(
            controller.state.status_message.as_deref(),
            Some("Applied Professional rewrite preset.")
        );
    }

    #[test]
    fn preview_current_voice_is_blocked_when_recorder_busy() {
        let mut controller = FloController::new();
        controller.state.recorder_state = RecorderState::Listening;

        let effects = controller.dispatch(
            FloCommand::PreviewCurrentVoice,
            &PlatformCapabilities::win32_default(),
        );

        assert!(effects.is_empty());
        assert_eq!(
            controller.state.status_message.as_deref(),
            Some("Wait for the current action to finish, then try voice preview again.")
        );
    }

    #[test]
    fn preview_current_voice_sets_preview_state_and_effects_when_idle() {
        let mut controller = FloController::new();

        let effects = controller.dispatch(
            FloCommand::PreviewCurrentVoice,
            &PlatformCapabilities::win32_default(),
        );

        assert_eq!(
            effects,
            vec![
                ControllerEffect::ShowFloatingBar(FloatingBarState::Speaking),
                ControllerEffect::StartTts,
            ]
        );
        assert!(controller.state.is_voice_preview_in_progress);
        assert_eq!(controller.state.recorder_state, RecorderState::Speaking);
    }

    #[test]
    fn reorder_provider_failover_order_dedupes_and_normalizes() {
        let mut controller = FloController::new();

        let effects = controller.dispatch(
            FloCommand::ReorderProvidersInFailoverOrder(vec![
                " OpenAI ".to_string(),
                "gemini".to_string(),
                "openai".to_string(),
            ]),
            &PlatformCapabilities::win32_default(),
        );

        assert_eq!(effects, vec![ControllerEffect::PersistRoutingOverrides]);
        assert_eq!(
            controller.state.provider_routing_overrides.provider_order,
            vec!["openai".to_string(), "gemini".to_string()]
        );
    }

    #[test]
    fn move_provider_up_and_down_adjusts_order() {
        let mut controller = FloController::new();
        controller.state.provider_routing_overrides.provider_order = vec![
            "openai".to_string(),
            "gemini".to_string(),
            "anthropic".to_string(),
        ];

        controller.dispatch(
            FloCommand::MoveProviderDownInFailoverOrder("openai".to_string()),
            &PlatformCapabilities::win32_default(),
        );
        controller.dispatch(
            FloCommand::MoveProviderUpInFailoverOrder("anthropic".to_string()),
            &PlatformCapabilities::win32_default(),
        );

        assert_eq!(
            controller.state.provider_routing_overrides.provider_order,
            vec![
                "gemini".to_string(),
                "anthropic".to_string(),
                "openai".to_string()
            ]
        );
    }

    #[test]
    fn set_provider_enabled_in_failover_updates_allowed_provider_list() {
        let mut controller = FloController::new();
        controller.state.provider_routing_overrides.provider_order =
            vec!["openai".to_string(), "gemini".to_string()];

        controller.dispatch(
            FloCommand::SetProviderEnabledInFailover {
                provider: "gemini".to_string(),
                enabled: false,
            },
            &PlatformCapabilities::win32_default(),
        );

        assert_eq!(
            controller
                .state
                .provider_routing_overrides
                .allowed_providers,
            Some(vec!["openai".to_string()])
        );
    }

    #[test]
    fn save_provider_credential_sets_saved_mode_and_logged_in_session() {
        let mut controller = FloController::new();
        controller.state.active_provider = "openai".to_string();

        let effects = controller.dispatch(
            FloCommand::SaveProviderCredential("k1".to_string()),
            &PlatformCapabilities::win32_default(),
        );

        assert_eq!(
            effects,
            vec![ControllerEffect::PersistProviderCredentials {
                provider: "openai".to_string(),
                credentials: vec!["k1".to_string()],
            }]
        );
        assert!(controller.state.uses_saved_provider_credential);
        assert!(matches!(
            controller.state.auth_state,
            AuthState::LoggedIn(_)
        ));
    }

    #[test]
    fn provider_credential_crud_commands_update_key_pool() {
        let mut controller = FloController::new();
        let capabilities = PlatformCapabilities::win32_default();

        controller.dispatch(
            FloCommand::SaveProviderCredentialForProvider {
                provider: "openai".to_string(),
                credential: "k1".to_string(),
            },
            &capabilities,
        );
        controller.dispatch(
            FloCommand::AddProviderCredential {
                provider: "openai".to_string(),
                credential: "k2".to_string(),
            },
            &capabilities,
        );
        controller.dispatch(
            FloCommand::UpdateProviderCredential {
                provider: "openai".to_string(),
                index: 0,
                credential: "k1-updated".to_string(),
            },
            &capabilities,
        );
        controller.dispatch(
            FloCommand::ReorderProviderCredentials {
                provider: "openai".to_string(),
                credentials: vec!["k2".to_string(), "k1-updated".to_string()],
            },
            &capabilities,
        );
        controller.dispatch(
            FloCommand::RemoveProviderCredential {
                provider: "openai".to_string(),
                index: 0,
            },
            &capabilities,
        );

        assert_eq!(
            controller.provider_credentials("openai"),
            vec!["k1-updated".to_string()]
        );
    }

    #[test]
    fn login_is_blocked_in_saved_api_key_mode() {
        let mut controller = FloController::new();
        controller.state.uses_saved_provider_credential = true;

        let effects =
            controller.dispatch(FloCommand::Login, &PlatformCapabilities::win32_default());

        assert!(effects.is_empty());
        assert_eq!(
            controller.state.status_message.as_deref(),
            Some("Login disabled in API key mode.")
        );
    }

    #[test]
    fn remove_saved_provider_credential_for_provider_clears_when_last_key() {
        let mut controller = FloController::new();
        let capabilities = PlatformCapabilities::win32_default();
        controller.dispatch(
            FloCommand::SaveProviderCredentialForProvider {
                provider: "openai".to_string(),
                credential: "k1".to_string(),
            },
            &capabilities,
        );

        let effects = controller.dispatch(
            FloCommand::RemoveSavedProviderCredentialForProvider("openai".to_string()),
            &capabilities,
        );

        assert_eq!(
            effects,
            vec![ControllerEffect::ClearProviderCredentials {
                provider: "openai".to_string()
            }]
        );
        assert!(matches!(controller.state.auth_state, AuthState::LoggedOut));
    }

    #[test]
    fn request_microphone_access_command_emits_request_and_refresh_effects() {
        let mut controller = FloController::new();

        let effects = controller.dispatch(
            FloCommand::RequestMicrophoneAccess,
            &PlatformCapabilities::win32_default(),
        );

        assert_eq!(
            effects,
            vec![
                ControllerEffect::RequestMicrophoneAccess,
                ControllerEffect::RefreshPermissions,
            ]
        );
    }

    #[test]
    fn prompt_for_required_permissions_requests_only_missing_items() {
        let mut controller = FloController::new();
        controller.state.permission_status = PermissionStatus {
            microphone: PermissionState::Denied,
            accessibility: PermissionState::Granted,
            input_monitoring: PermissionState::Denied,
        };

        let effects = controller.dispatch(
            FloCommand::PromptForRequiredPermissions,
            &PlatformCapabilities::win32_default(),
        );

        assert_eq!(
            effects,
            vec![
                ControllerEffect::RequestMicrophoneAccess,
                ControllerEffect::OpenSystemSettings(PermissionKind::InputMonitoring),
                ControllerEffect::RefreshPermissions,
            ]
        );
    }

    #[test]
    fn open_system_settings_sets_expected_guidance_message() {
        let mut controller = FloController::new();

        let effects = controller.dispatch(
            FloCommand::OpenSystemSettings(PermissionKind::Accessibility),
            &PlatformCapabilities::win32_default(),
        );

        assert_eq!(
            effects,
            vec![ControllerEffect::OpenSystemSettings(
                PermissionKind::Accessibility
            )]
        );
        assert_eq!(
            controller.state.status_message.as_deref(),
            Some(
                "After enabling this permission, quit and reopen FloApp, then press Refresh Permissions."
            )
        );
    }

    #[test]
    fn provider_credentials_loaded_event_enables_saved_credential_mode() {
        let mut controller = FloController::new();
        controller.apply_event(ControllerEvent::ProviderCredentialsLoaded {
            provider: "openai".to_string(),
            credentials: vec!["k1".to_string(), "k2".to_string()],
        });

        assert!(controller.state.uses_saved_provider_credential);
        assert_eq!(controller.configured_key_count("openai"), 2);
        assert!(matches!(
            controller.state.auth_state,
            AuthState::LoggedIn(_)
        ));
    }

    #[test]
    fn provider_query_helpers_reflect_current_state() {
        let mut controller = FloController::new();
        controller.apply_event(ControllerEvent::ProviderCredentialsLoaded {
            provider: "openai".to_string(),
            credentials: vec!["k1".to_string()],
        });
        controller.state.provider_routing_overrides.provider_order =
            vec!["openai".to_string(), "gemini".to_string()];

        assert!(controller.provider_supports_oauth("openai"));
        assert_eq!(
            controller
                .provider_credential_source_label("openai")
                .as_deref(),
            Some("Saved API key")
        );
        assert!(controller.can_remove_saved_provider_credential("openai"));
        assert_eq!(controller.configured_key_count("openai"), 1);
        assert!(controller.provider_supports_failover_operation("openai"));
        assert!(controller.provider_enabled_for_failover("openai"));
        assert!(!controller.can_move_provider_up_in_failover_order("openai"));
        assert!(controller.can_move_provider_down_in_failover_order("openai"));
    }

    #[test]
    fn refresh_models_catalog_command_emits_fetch_effect_and_updates_event_state() {
        let mut controller = FloController::new();

        let effects = controller.dispatch(
            FloCommand::RefreshModelsDevCatalog,
            &PlatformCapabilities::win32_default(),
        );
        assert_eq!(effects, vec![ControllerEffect::FetchModelsCatalog]);

        controller.apply_event(ControllerEvent::ModelsCatalogLoaded {
            provider: "openai".to_string(),
            models: vec![
                "gpt-4.1-mini".to_string(),
                "gpt-4.1-mini".to_string(),
                "gpt-4.1".to_string(),
            ],
        });
        assert_eq!(
            controller.provider_models("openai", ""),
            vec!["gpt-4.1-mini".to_string(), "gpt-4.1".to_string()]
        );
    }

    #[test]
    fn rewrite_model_override_commands_update_routing_overrides() {
        let mut controller = FloController::new();
        let capabilities = PlatformCapabilities::win32_default();

        controller.dispatch(
            FloCommand::SetRewriteModelForProvider {
                provider: "openai".to_string(),
                model_id: "gpt-4.1-mini".to_string(),
            },
            &capabilities,
        );
        controller.dispatch(
            FloCommand::SetRewriteModelForProviderCredential {
                provider: "openai".to_string(),
                credential_index: 1,
                model_id: "gpt-4.1".to_string(),
            },
            &capabilities,
        );

        assert_eq!(
            controller.rewrite_model_override("openai").as_deref(),
            Some("gpt-4.1-mini")
        );
        assert_eq!(
            controller
                .rewrite_model_override_for_credential("openai", 1)
                .as_deref(),
            Some("gpt-4.1")
        );
        assert_eq!(
            controller.active_rewrite_model_for_credential("openai", 1),
            "gpt-4.1".to_string()
        );

        controller.dispatch(
            FloCommand::ClearRewriteModelOverrideForProviderCredential {
                provider: "openai".to_string(),
                credential_index: 1,
            },
            &capabilities,
        );
        controller.dispatch(
            FloCommand::ClearRewriteModelOverrideForProvider("openai".to_string()),
            &capabilities,
        );
        assert_eq!(controller.rewrite_model_override("openai"), None);
        assert_eq!(
            controller.rewrite_model_override_for_credential("openai", 1),
            None
        );
    }

    #[test]
    fn provider_display_logo_and_copy_credential_actions_work() {
        let mut controller = FloController::new();
        let capabilities = PlatformCapabilities::win32_default();
        controller.dispatch(
            FloCommand::SaveProviderCredentialForProvider {
                provider: "openai".to_string(),
                credential: "k1".to_string(),
            },
            &capabilities,
        );

        assert_eq!(controller.provider_display_name("openai"), "OpenAI");
        assert_eq!(
            controller.provider_logo_url("openai").as_deref(),
            Some("https://models.dev/logos/openai.svg")
        );

        let effects = controller.dispatch(
            FloCommand::CopyProviderCredential {
                provider: "openai".to_string(),
                index: 0,
            },
            &capabilities,
        );

        assert_eq!(
            effects,
            vec![ControllerEffect::CopyToClipboard("k1".to_string())]
        );
        assert_eq!(
            controller.state.status_message.as_deref(),
            Some("OpenAI API key copied to clipboard.")
        );
    }
}
