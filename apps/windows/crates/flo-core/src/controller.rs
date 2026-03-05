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
    pub provider_routing_overrides: ProviderRoutingOverrides,
    pub status_message: Option<String>,
    pub last_selection_read_method: Option<SelectionReadMethod>,
    pub last_dictation_transcript: Option<String>,
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
            provider_routing_overrides: ProviderRoutingOverrides::default(),
            status_message: None,
            last_selection_read_method: None,
            last_dictation_transcript: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum FloCommand {
    Bootstrap,
    Login,
    Logout,
    RefreshPermissions,
    RequestPermission(PermissionKind),
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
    PasteLastTranscript,
    UpdateVoice(String),
    UpdateVoiceSpeed(f32),
    ClearHistory,
    StartDictationFromHotkey,
    StopDictationFromHotkey,
    ReadSelectedTextFromHotkey,
    PreviewCurrentVoice,
    CompleteHotkeyConfirmation,
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
    RequestPermission(PermissionKind),
    PersistShortcuts,
    PersistRewritePreferences,
    PersistVoicePreferences,
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
                self.state.auth_state = AuthState::Authenticating;
                vec![ControllerEffect::StartOAuth]
            }
            FloCommand::Logout => {
                self.state.auth_state = AuthState::LoggedOut;
                self.state.recorder_state = RecorderState::Idle;
                self.state.live_transcript_preview.clear();
                self.state.last_dictation_transcript = None;
                vec![ControllerEffect::Logout, ControllerEffect::HideFloatingBar]
            }
            FloCommand::RefreshPermissions => vec![ControllerEffect::RefreshPermissions],
            FloCommand::RequestPermission(permission) => {
                vec![ControllerEffect::RequestPermission(permission)]
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
            FloCommand::PreviewCurrentVoice => vec![ControllerEffect::StartTts],
            FloCommand::CompleteHotkeyConfirmation => {
                self.state.status_message = Some("Hotkey onboarding confirmed.".to_string());
                Vec::new()
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
                self.state.status_message.replace(canonical_error_message(
                    PlatformErrorCode::ReadAloudCompleted,
                    None,
                ));
                vec![ControllerEffect::HideFloatingBar]
            }
            ControllerEvent::TtsCanceled => {
                self.state.recorder_state = RecorderState::Idle;
                self.state.status_message.replace(canonical_error_message(
                    PlatformErrorCode::ReadAloudCanceled,
                    None,
                ));
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
        AppIntegrityLevel, DictationBaseTone, DictationLiveFinalizationMode,
        DictationRewritePreset, FloatingBarState, KeyCombo, LogicalKey, ShortcutAction,
        ShortcutBinding, ShortcutModifiers,
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
}
