use flo_domain::{
    AuthState, DictationBaseTone, DictationLiveFinalizationMode, DictationRewritePreferences,
    DictationStyleLevel, PermissionKind, PermissionStatus, ProviderRoutingOverrides, RecorderState,
    ShortcutBinding,
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
    pub provider_routing_overrides: ProviderRoutingOverrides,
    pub status_message: Option<String>,
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
            provider_routing_overrides: ProviderRoutingOverrides::default(),
            status_message: None,
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
pub enum ControllerEffect {
    RestoreSession,
    StartOAuth,
    Logout,
    RefreshPermissions,
    RequestPermission(PermissionKind),
    PersistShortcuts,
    PersistRewritePreferences,
    PersistRoutingOverrides,
    ClearHistory,
    ShowFloatingBar(RecorderState),
    UpdateFloatingBar(RecorderState),
    HideFloatingBar,
    StartSpeechCapture,
    StopSpeechCapture,
    ReadSelected {
        prefer_uia: bool,
        fallback_to_clipboard: bool,
    },
    PromptForElevation,
    StartTts,
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
            FloCommand::ClearHistory => vec![ControllerEffect::ClearHistory],
            FloCommand::StartDictationFromHotkey => {
                if !capabilities.injection_supported {
                    self.state.recorder_state =
                        RecorderState::Error("Injection is not supported in this context.".into());
                    self.state.status_message =
                        Some("Injection is not supported for the focused target.".to_string());
                    return Vec::new();
                }
                self.state.recorder_state = RecorderState::Listening;
                self.state.live_transcript_preview.clear();
                vec![
                    ControllerEffect::ShowFloatingBar(RecorderState::Listening),
                    ControllerEffect::StartSpeechCapture,
                ]
            }
            FloCommand::StopDictationFromHotkey => {
                self.state.recorder_state = RecorderState::Transcribing;
                vec![
                    ControllerEffect::UpdateFloatingBar(RecorderState::Transcribing),
                    ControllerEffect::StopSpeechCapture,
                ]
            }
            FloCommand::ReadSelectedTextFromHotkey => {
                if capabilities.target_requires_elevation && !capabilities.elevated_mode {
                    if capabilities.can_prompt_for_elevation {
                        self.state.status_message = Some(
                            "The focused app requires elevated mode. Please relaunch flo as admin."
                                .to_string(),
                        );
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
                    ControllerEffect::UpdateFloatingBar(RecorderState::Speaking),
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
}

#[cfg(test)]
mod tests {
    use flo_domain::{
        DictationLiveFinalizationMode, KeyCombo, LogicalKey, ShortcutAction, ShortcutBinding,
        ShortcutModifiers,
    };

    use super::{ControllerEffect, FloCommand, FloController};
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
}
