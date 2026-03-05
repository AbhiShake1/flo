use std::{
    collections::VecDeque,
    fs,
    path::Path,
    time::{SystemTime, UNIX_EPOCH},
};

use flo_core::{
    controller::{ControllerEffect, ControllerEvent, FloController},
    ports::{
        AuthService, AuthStateSink, DictationPreferencesStore, ElevationPromptOutcome,
        ElevationService, FloatingBarChipModel, FloatingBarManaging, PermissionsService,
        SelectionReaderService, SpeechCaptureService, TTSService, TextInjectionService,
        VoicePreferencesStore,
    },
};
use flo_domain::{AuthState, PlatformErrorCode};
use futures::executor::block_on;

pub struct EffectRuntime<'a> {
    selection_reader: &'a mut dyn SelectionReaderService,
    text_injection: &'a mut dyn TextInjectionService,
    elevation_service: &'a mut dyn ElevationService,
    permissions_service: &'a mut dyn PermissionsService,
    floating_bar: &'a mut dyn FloatingBarManaging,
    dictation_preferences_store: &'a mut dyn DictationPreferencesStore,
    voice_preferences_store: &'a mut dyn VoicePreferencesStore,
    auth_service: &'a mut dyn AuthService,
    auth_state_sink: &'a mut dyn AuthStateSink,
    speech_capture_service: &'a mut dyn SpeechCaptureService,
    tts_service: &'a mut dyn TTSService,
    pending_tts_text: Option<String>,
}

impl<'a> EffectRuntime<'a> {
    pub fn new(
        selection_reader: &'a mut dyn SelectionReaderService,
        text_injection: &'a mut dyn TextInjectionService,
        elevation_service: &'a mut dyn ElevationService,
        permissions_service: &'a mut dyn PermissionsService,
        floating_bar: &'a mut dyn FloatingBarManaging,
        dictation_preferences_store: &'a mut dyn DictationPreferencesStore,
        voice_preferences_store: &'a mut dyn VoicePreferencesStore,
        auth_service: &'a mut dyn AuthService,
        auth_state_sink: &'a mut dyn AuthStateSink,
        speech_capture_service: &'a mut dyn SpeechCaptureService,
        tts_service: &'a mut dyn TTSService,
    ) -> Self {
        Self {
            selection_reader,
            text_injection,
            elevation_service,
            permissions_service,
            floating_bar,
            dictation_preferences_store,
            voice_preferences_store,
            auth_service,
            auth_state_sink,
            speech_capture_service,
            tts_service,
            pending_tts_text: None,
        }
    }

    pub fn drive_effects(
        &mut self,
        controller: &mut FloController,
        initial_effects: Vec<ControllerEffect>,
    ) -> Vec<ControllerEffect> {
        let mut queue: VecDeque<ControllerEffect> = VecDeque::from(initial_effects);
        let mut derived_effects = Vec::new();

        while let Some(effect) = queue.pop_front() {
            let events = self.execute_effect(controller, &effect);
            for event in events {
                let next_effects = controller.apply_event(event);
                queue.extend(next_effects.iter().cloned());
                derived_effects.extend(next_effects);
            }
        }

        derived_effects
    }

    fn execute_effect(
        &mut self,
        controller: &FloController,
        effect: &ControllerEffect,
    ) -> Vec<ControllerEvent> {
        match effect {
            ControllerEffect::RestoreSession => {
                let restored_session = block_on(self.auth_service.restore_session());
                let session = match restored_session {
                    Some(session) if session.is_expired(now_unix_ms()) => {
                        block_on(self.auth_service.refresh_session(&session)).ok()
                    }
                    other => other,
                };
                if let Some(session) = session.clone() {
                    self.auth_state_sink
                        .update_auth_state(AuthState::LoggedIn(session.clone()));
                } else {
                    self.auth_state_sink.update_auth_state(AuthState::LoggedOut);
                }
                vec![ControllerEvent::AuthRestored(session)]
            }
            ControllerEffect::StartOAuth => match block_on(self.auth_service.start_oauth()) {
                Ok(session) => {
                    self.auth_state_sink
                        .update_auth_state(AuthState::LoggedIn(session.clone()));
                    vec![ControllerEvent::AuthRestored(Some(session))]
                }
                Err(error) => vec![ControllerEvent::Error(error.error_code())],
            },
            ControllerEffect::Logout => match block_on(self.auth_service.logout()) {
                Ok(()) => {
                    self.auth_state_sink.update_auth_state(AuthState::LoggedOut);
                    Vec::new()
                }
                Err(error) => vec![ControllerEvent::Error(error.error_code())],
            },
            ControllerEffect::ReadSelected { .. } => {
                match self.selection_reader.read_selected_text() {
                    Ok(read) => {
                        self.pending_tts_text = Some(read.text.clone());
                        vec![ControllerEvent::SelectionRead {
                            text: read.text,
                            method: read.method,
                        }]
                    }
                    Err(error) => vec![ControllerEvent::Error(error.error_code())],
                }
            }
            ControllerEffect::StartSpeechCapture => {
                let capture_started = self
                    .speech_capture_service
                    .start_capture(Box::new(|_| {}), Some(Box::new(|_| {})));
                match capture_started {
                    Ok(()) => vec![ControllerEvent::CaptureStarted],
                    Err(error) => vec![ControllerEvent::Error(error.error_code())],
                }
            }
            ControllerEffect::StopSpeechCapture => {
                match self.speech_capture_service.stop_capture() {
                    Ok(capture_path) => {
                        let transcript = read_transcript_from_capture_path(&capture_path);
                        vec![ControllerEvent::CaptureStopped { transcript }]
                    }
                    Err(error) => vec![ControllerEvent::Error(error.error_code())],
                }
            }
            ControllerEffect::StartTts => {
                let text = self.pending_tts_text.clone().unwrap_or_else(|| {
                    if controller.state.live_transcript_preview.is_empty() {
                        "This is a voice preview.".to_string()
                    } else {
                        controller.state.live_transcript_preview.clone()
                    }
                });
                let auth_token = match &controller.state.auth_state {
                    AuthState::LoggedIn(session) => session.access_token.as_str(),
                    _ => "",
                };

                match block_on(self.tts_service.synthesize_and_play(
                    &text,
                    auth_token,
                    &controller.state.voice_preferences.voice,
                    controller.state.voice_preferences.speed,
                )) {
                    Ok(()) => Vec::new(),
                    Err(error) => vec![ControllerEvent::Error(error.error_code())],
                }
            }
            ControllerEffect::InjectText { text, .. } => {
                match self.text_injection.inject_text(text) {
                    Ok(()) => vec![ControllerEvent::InjectionCompleted],
                    Err(reason) => vec![ControllerEvent::InjectionFailed(reason)],
                }
            }
            ControllerEffect::FinalizeDictation(plan) => match plan {
                flo_core::controller::LiveFinalizationPlan::InjectDelta(text)
                | flo_core::controller::LiveFinalizationPlan::ReplaceWithFinal(text)
                | flo_core::controller::LiveFinalizationPlan::CopyFinalToClipboard(text) => {
                    match self.text_injection.inject_text(text) {
                        Ok(()) => vec![ControllerEvent::InjectionCompleted],
                        Err(reason) => vec![ControllerEvent::InjectionFailed(reason)],
                    }
                }
                flo_core::controller::LiveFinalizationPlan::Noop => Vec::new(),
            },
            ControllerEffect::PromptForElevation => {
                match self
                    .elevation_service
                    .request_elevated_relaunch("The focused app requires elevated mode")
                {
                    Ok(ElevationPromptOutcome::RelaunchRequested) => {
                        vec![ControllerEvent::ElevatedRelaunchRequested]
                    }
                    Ok(ElevationPromptOutcome::AlreadyElevated) => Vec::new(),
                    Ok(ElevationPromptOutcome::PromptDeclined) => {
                        vec![ControllerEvent::Error(PlatformErrorCode::PermissionDenied)]
                    }
                    Err(error) => vec![ControllerEvent::Error(error.error_code())],
                }
            }
            ControllerEffect::RefreshPermissions => {
                let status = self.permissions_service.refresh_status();
                vec![ControllerEvent::PermissionStatusUpdated(status)]
            }
            ControllerEffect::RequestPermission(permission) => {
                let request_result = match permission {
                    flo_domain::PermissionKind::Microphone => self
                        .permissions_service
                        .request_microphone_access()
                        .map(|_| ()),
                    flo_domain::PermissionKind::Accessibility
                    | flo_domain::PermissionKind::InputMonitoring => self
                        .permissions_service
                        .open_settings_target(*permission)
                        .map(|_| ()),
                };

                if let Err(error) = request_result {
                    return vec![ControllerEvent::Error(error.error_code())];
                }

                let status = self.permissions_service.refresh_status();
                vec![ControllerEvent::PermissionStatusUpdated(status)]
            }
            ControllerEffect::RequestMicrophoneAccess => {
                if let Err(error) = self.permissions_service.request_microphone_access() {
                    return vec![ControllerEvent::Error(error.error_code())];
                }
                let status = self.permissions_service.refresh_status();
                vec![ControllerEvent::PermissionStatusUpdated(status)]
            }
            ControllerEffect::PersistRewritePreferences => {
                if let Err(error) = self
                    .dictation_preferences_store
                    .save(&controller.state.dictation_rewrite_preferences)
                {
                    return vec![ControllerEvent::Error(error.error_code())];
                }
                Vec::new()
            }
            ControllerEffect::PersistVoicePreferences => {
                if let Err(error) = self
                    .voice_preferences_store
                    .save(&controller.state.voice_preferences)
                {
                    return vec![ControllerEvent::Error(error.error_code())];
                }
                Vec::new()
            }
            ControllerEffect::OpenSystemSettings(permission) => {
                if let Err(error) = self.permissions_service.open_settings_target(*permission) {
                    return vec![ControllerEvent::Error(error.error_code())];
                }
                Vec::new()
            }
            ControllerEffect::ShowFloatingBar(state)
            | ControllerEffect::UpdateFloatingBar(state) => {
                let model = FloatingBarChipModel {
                    state: *state,
                    transcript_preview: if controller.state.live_transcript_preview.is_empty() {
                        None
                    } else {
                        Some(controller.state.live_transcript_preview.clone())
                    },
                    level_meter: 0.0,
                    hint_text: if state.canonical_message().is_empty() {
                        None
                    } else {
                        Some(state.canonical_message().to_string())
                    },
                    busy: matches!(
                        state,
                        flo_domain::FloatingBarState::Transcribing
                            | flo_domain::FloatingBarState::Injecting
                    ),
                    show_read_affordance: !matches!(
                        state,
                        flo_domain::FloatingBarState::Listening
                            | flo_domain::FloatingBarState::Transcribing
                            | flo_domain::FloatingBarState::Injecting
                    ),
                    banner: None,
                };
                if let Err(error) = self.floating_bar.render_chip(&model) {
                    return vec![ControllerEvent::Error(error.error_code())];
                }
                Vec::new()
            }
            ControllerEffect::HideFloatingBar => {
                if let Err(error) = self.floating_bar.hide() {
                    return vec![ControllerEvent::Error(error.error_code())];
                }
                Vec::new()
            }
            _ => Vec::new(),
        }
    }
}

fn read_transcript_from_capture_path(path: &Path) -> String {
    if !path.as_os_str().is_empty() && path.exists() {
        return fs::read_to_string(path)
            .map(|contents| contents.trim().to_string())
            .unwrap_or_default();
    }

    String::new()
}

fn now_unix_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::PathBuf;
    use std::sync::{Arc, Mutex};

    use async_trait::async_trait;
    use flo_core::{
        capabilities::PlatformCapabilities,
        controller::FloCommand,
        ports::{
            AuthService, AuthStateSink, CoreError, CoreResult, DictationPreferencesStore,
            FloatingBarActions, PermissionSettingsTarget, SpeechCaptureService, TTSService,
            VoicePreferencesStore,
        },
    };
    use flo_domain::{
        AppIntegrityLevel, AuthState, DictationRewritePreferences, PermissionKind, PermissionState,
        PermissionStatus, SelectionReadMethod, TextInjectionFailureReason, UserSession,
        VoicePreferences,
    };

    use super::*;

    struct FakeSelectionService {
        read: Option<flo_domain::SelectionReadResult>,
    }

    impl SelectionReaderService for FakeSelectionService {
        fn read_selected_text(&mut self) -> CoreResult<flo_domain::SelectionReadResult> {
            self.read.clone().ok_or(CoreError::SelectionUnavailable)
        }
    }

    #[derive(Default)]
    struct FakeTextInjectionService {
        fail: Option<TextInjectionFailureReason>,
    }

    impl TextInjectionService for FakeTextInjectionService {
        fn inject_text(&mut self, _text: &str) -> Result<(), TextInjectionFailureReason> {
            match &self.fail {
                Some(reason) => Err(reason.clone()),
                None => Ok(()),
            }
        }

        fn replace_recent_text(
            &mut self,
            _previous_text: &str,
            _updated_text: &str,
        ) -> Result<(), TextInjectionFailureReason> {
            Ok(())
        }
    }

    struct FakeElevationService {
        outcome: ElevationPromptOutcome,
        fail: bool,
    }

    impl ElevationService for FakeElevationService {
        fn current_integrity_level(&self) -> CoreResult<AppIntegrityLevel> {
            Ok(AppIntegrityLevel::Medium)
        }

        fn focused_target_integrity_level(&self) -> CoreResult<AppIntegrityLevel> {
            Ok(AppIntegrityLevel::High)
        }

        fn request_elevated_relaunch(
            &mut self,
            _reason: &str,
        ) -> CoreResult<ElevationPromptOutcome> {
            if self.fail {
                return Err(CoreError::PermissionDenied(
                    "Elevation prompt failed".to_string(),
                ));
            }
            Ok(self.outcome)
        }
    }

    struct FakePermissionsService {
        status: PermissionStatus,
        opened_targets: Vec<PermissionKind>,
    }

    impl PermissionsService for FakePermissionsService {
        fn refresh_status(&mut self) -> PermissionStatus {
            self.status
        }

        fn request_microphone_access(&mut self) -> CoreResult<bool> {
            self.status.microphone = PermissionState::Granted;
            Ok(true)
        }

        fn open_settings_target(
            &mut self,
            permission: PermissionKind,
        ) -> CoreResult<PermissionSettingsTarget> {
            self.opened_targets.push(permission);
            Ok(match permission {
                PermissionKind::Microphone => PermissionSettingsTarget::MicrophonePrivacy,
                PermissionKind::Accessibility => PermissionSettingsTarget::AccessibilityPrivacy,
                PermissionKind::InputMonitoring => PermissionSettingsTarget::InputMonitoringPrivacy,
            })
        }
    }

    #[derive(Default)]
    struct FakeFloatingBarService {
        hide_calls: usize,
        render_calls: usize,
    }

    impl FloatingBarManaging for FakeFloatingBarService {
        fn set_actions(&mut self, _actions: Option<FloatingBarActions>) -> CoreResult<()> {
            Ok(())
        }

        fn render_chip(&mut self, _model: &FloatingBarChipModel) -> CoreResult<()> {
            self.render_calls += 1;
            Ok(())
        }

        fn hide(&mut self) -> CoreResult<()> {
            self.hide_calls += 1;
            Ok(())
        }
    }

    #[derive(Default)]
    struct FakeDictationPreferencesStore {
        saved: Option<DictationRewritePreferences>,
        fail: bool,
    }

    impl DictationPreferencesStore for FakeDictationPreferencesStore {
        fn load(&self) -> DictationRewritePreferences {
            self.saved.clone().unwrap_or_default()
        }

        fn save(&mut self, preferences: &DictationRewritePreferences) -> CoreResult<()> {
            if self.fail {
                return Err(CoreError::Io("dictation save failed".to_string()));
            }
            self.saved = Some(preferences.clone());
            Ok(())
        }
    }

    #[derive(Default)]
    struct FakeVoicePreferencesStore {
        saved: Option<VoicePreferences>,
        fail: bool,
    }

    impl VoicePreferencesStore for FakeVoicePreferencesStore {
        fn load(&self) -> VoicePreferences {
            self.saved.clone().unwrap_or_default()
        }

        fn save(&mut self, preferences: &VoicePreferences) -> CoreResult<()> {
            if self.fail {
                return Err(CoreError::Io("voice save failed".to_string()));
            }
            self.saved = Some(preferences.clone());
            Ok(())
        }
    }

    struct FakeAuthService {
        restored: Option<UserSession>,
        oauth_session: Option<UserSession>,
        fail_start_oauth: bool,
        fail_refresh: bool,
        fail_logout: bool,
        refresh_calls: Arc<Mutex<usize>>,
    }

    impl Default for FakeAuthService {
        fn default() -> Self {
            Self {
                restored: None,
                oauth_session: None,
                fail_start_oauth: false,
                fail_refresh: false,
                fail_logout: false,
                refresh_calls: Arc::new(Mutex::new(0)),
            }
        }
    }

    #[async_trait]
    impl AuthService for FakeAuthService {
        async fn restore_session(&mut self) -> Option<UserSession> {
            self.restored.clone()
        }

        async fn start_oauth(&mut self) -> CoreResult<UserSession> {
            if self.fail_start_oauth {
                return Err(CoreError::Unauthorized);
            }
            self.oauth_session.clone().ok_or(CoreError::Unauthorized)
        }

        async fn refresh_session(&mut self, session: &UserSession) -> CoreResult<UserSession> {
            *self.refresh_calls.lock().expect("lock refresh calls") += 1;
            if self.fail_refresh {
                return Err(CoreError::Unauthorized);
            }
            let mut next = session.clone();
            next.expires_at_unix_ms = i64::MAX;
            Ok(next)
        }

        async fn logout(&mut self) -> CoreResult<()> {
            if self.fail_logout {
                return Err(CoreError::Unauthorized);
            }
            Ok(())
        }
    }

    #[derive(Default)]
    struct FakeAuthStateSink {
        states: Vec<AuthState>,
    }

    impl AuthStateSink for FakeAuthStateSink {
        fn update_auth_state(&mut self, auth_state: AuthState) {
            self.states.push(auth_state);
        }
    }

    #[derive(Default)]
    struct FakeSpeechCaptureService {
        fail_start: bool,
        fail_stop: bool,
        stop_path: PathBuf,
        canceled: bool,
    }

    impl SpeechCaptureService for FakeSpeechCaptureService {
        fn start_capture(
            &mut self,
            _level_handler: Box<dyn FnMut(f32) + Send>,
            _transcript_handler: Option<Box<dyn FnMut(String) + Send>>,
        ) -> CoreResult<()> {
            if self.fail_start {
                return Err(CoreError::Platform("capture-start".to_string()));
            }
            Ok(())
        }

        fn stop_capture(&mut self) -> CoreResult<PathBuf> {
            if self.fail_stop {
                return Err(CoreError::Platform("capture-stop".to_string()));
            }
            Ok(self.stop_path.clone())
        }

        fn cancel_capture(&mut self) {
            self.canceled = true;
        }
    }

    #[derive(Default)]
    struct FakeTtsService {
        fail: bool,
        calls: Arc<Mutex<Vec<(String, String, String, f32)>>>,
    }

    #[async_trait]
    impl TTSService for FakeTtsService {
        async fn synthesize_and_play(
            &mut self,
            text: &str,
            auth_token: &str,
            voice: &str,
            speed: f32,
        ) -> CoreResult<()> {
            if self.fail {
                return Err(CoreError::Platform("tts".to_string()));
            }
            self.calls.lock().expect("lock calls").push((
                text.to_string(),
                auth_token.to_string(),
                voice.to_string(),
                speed,
            ));
            Ok(())
        }

        fn stop_playback(&mut self) -> CoreResult<()> {
            Ok(())
        }
    }

    fn sample_session(expiry_offset_ms: i64) -> UserSession {
        UserSession {
            access_token: "token".to_string(),
            refresh_token: Some("refresh".to_string()),
            token_type: "Bearer".to_string(),
            expires_at_unix_ms: now_unix_ms() + expiry_offset_ms,
            account_id: Some("acct".to_string()),
        }
    }

    fn new_runtime<'a>(
        selection: &'a mut FakeSelectionService,
        injection: &'a mut FakeTextInjectionService,
        elevation: &'a mut FakeElevationService,
        permissions: &'a mut FakePermissionsService,
        floating: &'a mut FakeFloatingBarService,
        dictation_store: &'a mut FakeDictationPreferencesStore,
        voice_store: &'a mut FakeVoicePreferencesStore,
        auth_service: &'a mut FakeAuthService,
        auth_state_sink: &'a mut FakeAuthStateSink,
        speech_capture: &'a mut FakeSpeechCaptureService,
        tts: &'a mut FakeTtsService,
    ) -> EffectRuntime<'a> {
        EffectRuntime::new(
            selection,
            injection,
            elevation,
            permissions,
            floating,
            dictation_store,
            voice_store,
            auth_service,
            auth_state_sink,
            speech_capture,
            tts,
        )
    }

    #[test]
    fn drive_effects_processes_read_selected_and_updates_controller_state() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService {
            read: Some(flo_domain::SelectionReadResult {
                text: "hello".to_string(),
                method: SelectionReadMethod::UiAutomation,
            }),
        };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::RelaunchRequested,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();
        let mut auth = FakeAuthService::default();
        let mut auth_sink = FakeAuthStateSink::default();
        let mut speech = FakeSpeechCaptureService::default();
        let mut tts = FakeTtsService::default();

        let mut runtime = new_runtime(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
            &mut auth,
            &mut auth_sink,
            &mut speech,
            &mut tts,
        );

        let effects = controller.dispatch(
            FloCommand::ReadSelectedTextFromHotkey,
            &PlatformCapabilities::win32_default(),
        );
        runtime.drive_effects(&mut controller, effects);

        assert_eq!(
            controller.state.last_selection_read_method,
            Some(SelectionReadMethod::UiAutomation)
        );
        assert_eq!(
            controller.state.recorder_state,
            flo_domain::RecorderState::Speaking
        );
    }

    #[test]
    fn drive_effects_maps_elevation_prompt_decline_to_permission_error() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService { read: None };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::PromptDeclined,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();
        let mut auth = FakeAuthService::default();
        let mut auth_sink = FakeAuthStateSink::default();
        let mut speech = FakeSpeechCaptureService::default();
        let mut tts = FakeTtsService::default();

        let mut runtime = new_runtime(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
            &mut auth,
            &mut auth_sink,
            &mut speech,
            &mut tts,
        );

        runtime.drive_effects(&mut controller, vec![ControllerEffect::PromptForElevation]);

        assert_eq!(
            controller.state.status_message.as_deref(),
            Some("Permission denied: Unknown.")
        );
    }

    #[test]
    fn drive_effects_refreshes_permissions_via_port_service() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService { read: None };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::AlreadyElevated,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus {
                microphone: PermissionState::Denied,
                accessibility: PermissionState::Granted,
                input_monitoring: PermissionState::NotDetermined,
            },
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();
        let mut auth = FakeAuthService::default();
        let mut auth_sink = FakeAuthStateSink::default();
        let mut speech = FakeSpeechCaptureService::default();
        let mut tts = FakeTtsService::default();

        let mut runtime = new_runtime(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
            &mut auth,
            &mut auth_sink,
            &mut speech,
            &mut tts,
        );

        runtime.drive_effects(&mut controller, vec![ControllerEffect::RefreshPermissions]);

        assert_eq!(
            controller.state.permission_status.microphone,
            PermissionState::Denied
        );
        assert_eq!(
            controller.state.permission_status.input_monitoring,
            PermissionState::NotDetermined
        );
    }

    #[test]
    fn drive_effects_handles_request_permission_for_non_microphone_targets() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService { read: None };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::AlreadyElevated,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();
        let mut auth = FakeAuthService::default();
        let mut auth_sink = FakeAuthStateSink::default();
        let mut speech = FakeSpeechCaptureService::default();
        let mut tts = FakeTtsService::default();

        let mut runtime = new_runtime(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
            &mut auth,
            &mut auth_sink,
            &mut speech,
            &mut tts,
        );

        runtime.drive_effects(
            &mut controller,
            vec![ControllerEffect::RequestPermission(
                flo_domain::PermissionKind::Accessibility,
            )],
        );

        assert_eq!(
            permissions.opened_targets,
            vec![PermissionKind::Accessibility]
        );
    }

    #[test]
    fn drive_effects_persists_voice_and_rewrite_preferences() {
        let mut controller = FloController::new();
        controller.state.voice_preferences.voice = "verse".to_string();
        controller.state.voice_preferences.speed = 1.4;
        controller
            .state
            .dictation_rewrite_preferences
            .custom_instructions = "short bullets".to_string();

        let mut selection = FakeSelectionService { read: None };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::AlreadyElevated,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();
        let mut auth = FakeAuthService::default();
        let mut auth_sink = FakeAuthStateSink::default();
        let mut speech = FakeSpeechCaptureService::default();
        let mut tts = FakeTtsService::default();

        let mut runtime = new_runtime(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
            &mut auth,
            &mut auth_sink,
            &mut speech,
            &mut tts,
        );

        runtime.drive_effects(
            &mut controller,
            vec![
                ControllerEffect::PersistVoicePreferences,
                ControllerEffect::PersistRewritePreferences,
            ],
        );

        assert_eq!(
            voice_store.saved.as_ref().map(|saved| saved.voice.as_str()),
            Some("verse")
        );
        assert_eq!(
            dictation_store
                .saved
                .as_ref()
                .map(|saved| saved.custom_instructions.as_str()),
            Some("short bullets")
        );
    }

    #[test]
    fn drive_effects_maps_preference_store_failures_to_persistence_error() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService { read: None };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::AlreadyElevated,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore {
            saved: None,
            fail: true,
        };
        let mut voice_store = FakeVoicePreferencesStore::default();
        let mut auth = FakeAuthService::default();
        let mut auth_sink = FakeAuthStateSink::default();
        let mut speech = FakeSpeechCaptureService::default();
        let mut tts = FakeTtsService::default();

        let mut runtime = new_runtime(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
            &mut auth,
            &mut auth_sink,
            &mut speech,
            &mut tts,
        );

        runtime.drive_effects(
            &mut controller,
            vec![ControllerEffect::PersistRewritePreferences],
        );

        assert_eq!(
            controller.state.status_message.as_deref(),
            Some("Persistence error: Unknown")
        );
    }

    #[test]
    fn drive_effects_restore_session_refreshes_expired_session() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService { read: None };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::AlreadyElevated,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();
        let mut auth = FakeAuthService {
            restored: Some(sample_session(-1_000)),
            ..FakeAuthService::default()
        };
        let refresh_counter = auth.refresh_calls.clone();
        let mut auth_sink = FakeAuthStateSink::default();
        let mut speech = FakeSpeechCaptureService::default();
        let mut tts = FakeTtsService::default();

        let mut runtime = new_runtime(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
            &mut auth,
            &mut auth_sink,
            &mut speech,
            &mut tts,
        );

        runtime.drive_effects(&mut controller, vec![ControllerEffect::RestoreSession]);

        assert!(matches!(
            controller.state.auth_state,
            AuthState::LoggedIn(_)
        ));
        assert_eq!(*refresh_counter.lock().expect("lock refresh"), 1);
        assert!(matches!(
            auth_sink.states.last(),
            Some(AuthState::LoggedIn(_))
        ));
    }

    #[test]
    fn drive_effects_start_oauth_and_logout_update_auth_sink() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService { read: None };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::AlreadyElevated,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();
        let mut auth = FakeAuthService {
            oauth_session: Some(sample_session(120_000)),
            ..FakeAuthService::default()
        };
        let mut auth_sink = FakeAuthStateSink::default();
        let mut speech = FakeSpeechCaptureService::default();
        let mut tts = FakeTtsService::default();

        let mut runtime = new_runtime(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
            &mut auth,
            &mut auth_sink,
            &mut speech,
            &mut tts,
        );

        runtime.drive_effects(&mut controller, vec![ControllerEffect::StartOAuth]);
        runtime.drive_effects(&mut controller, vec![ControllerEffect::Logout]);

        assert!(matches!(
            controller.state.auth_state,
            AuthState::LoggedIn(_)
        ));
        assert!(matches!(
            auth_sink.states.first(),
            Some(AuthState::LoggedIn(_))
        ));
        assert!(matches!(
            auth_sink.states.last(),
            Some(AuthState::LoggedOut)
        ));
    }

    #[test]
    fn drive_effects_stop_capture_reads_transcript_from_path() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService { read: None };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::AlreadyElevated,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();
        let mut auth = FakeAuthService::default();
        let mut auth_sink = FakeAuthStateSink::default();

        let transcript_path =
            std::env::temp_dir().join(format!("flo-runtime-{}.txt", now_unix_ms()));
        fs::write(&transcript_path, "captured text").expect("write transcript fixture");
        let mut speech = FakeSpeechCaptureService {
            stop_path: transcript_path.clone(),
            ..FakeSpeechCaptureService::default()
        };
        let mut tts = FakeTtsService::default();

        let mut runtime = new_runtime(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
            &mut auth,
            &mut auth_sink,
            &mut speech,
            &mut tts,
        );

        runtime.drive_effects(&mut controller, vec![ControllerEffect::StopSpeechCapture]);

        assert_eq!(
            controller.state.last_dictation_transcript.as_deref(),
            Some("captured text")
        );

        let _ = fs::remove_file(transcript_path);
    }

    #[test]
    fn drive_effects_start_tts_uses_pending_selected_text() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService {
            read: Some(flo_domain::SelectionReadResult {
                text: "read this".to_string(),
                method: SelectionReadMethod::UiAutomation,
            }),
        };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::AlreadyElevated,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();
        let mut auth = FakeAuthService::default();
        let mut auth_sink = FakeAuthStateSink::default();
        let mut speech = FakeSpeechCaptureService::default();
        let mut tts = FakeTtsService::default();
        let tts_calls = tts.calls.clone();

        let mut runtime = new_runtime(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
            &mut auth,
            &mut auth_sink,
            &mut speech,
            &mut tts,
        );

        let effects = controller.dispatch(
            FloCommand::ReadSelectedTextFromHotkey,
            &PlatformCapabilities::win32_default(),
        );
        runtime.drive_effects(&mut controller, effects);

        let calls = tts_calls.lock().expect("lock tts calls").clone();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].0, "read this");
    }

    #[test]
    fn drive_effects_maps_oauth_failure_to_unauthorized_message() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService { read: None };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::AlreadyElevated,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();
        let mut auth = FakeAuthService {
            fail_start_oauth: true,
            ..FakeAuthService::default()
        };
        let mut auth_sink = FakeAuthStateSink::default();
        let mut speech = FakeSpeechCaptureService::default();
        let mut tts = FakeTtsService::default();

        let mut runtime = new_runtime(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
            &mut auth,
            &mut auth_sink,
            &mut speech,
            &mut tts,
        );

        runtime.drive_effects(&mut controller, vec![ControllerEffect::StartOAuth]);

        assert_eq!(
            controller.state.status_message.as_deref(),
            Some("You are not authenticated.")
        );
    }

    #[test]
    fn drive_effects_maps_capture_start_failure_to_network_error() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService { read: None };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::AlreadyElevated,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();
        let mut auth = FakeAuthService::default();
        let mut auth_sink = FakeAuthStateSink::default();
        let mut speech = FakeSpeechCaptureService {
            fail_start: true,
            ..FakeSpeechCaptureService::default()
        };
        let mut tts = FakeTtsService::default();

        let mut runtime = new_runtime(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
            &mut auth,
            &mut auth_sink,
            &mut speech,
            &mut tts,
        );

        runtime.drive_effects(&mut controller, vec![ControllerEffect::StartSpeechCapture]);

        assert_eq!(
            controller.state.status_message.as_deref(),
            Some("Network error: Unknown")
        );
    }

    #[test]
    fn drive_effects_maps_tts_failure_to_network_error() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService { read: None };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::AlreadyElevated,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();
        let mut auth = FakeAuthService::default();
        let mut auth_sink = FakeAuthStateSink::default();
        let mut speech = FakeSpeechCaptureService::default();
        let mut tts = FakeTtsService {
            fail: true,
            ..FakeTtsService::default()
        };

        let mut runtime = new_runtime(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
            &mut auth,
            &mut auth_sink,
            &mut speech,
            &mut tts,
        );

        runtime.drive_effects(&mut controller, vec![ControllerEffect::StartTts]);

        assert_eq!(
            controller.state.status_message.as_deref(),
            Some("Network error: Unknown")
        );
    }

    #[test]
    fn drive_effects_handles_empty_capture_as_audio_error() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService { read: None };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::AlreadyElevated,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();
        let mut auth = FakeAuthService::default();
        let mut auth_sink = FakeAuthStateSink::default();
        let mut speech = FakeSpeechCaptureService::default();
        let mut tts = FakeTtsService::default();

        let mut runtime = new_runtime(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
            &mut auth,
            &mut auth_sink,
            &mut speech,
            &mut tts,
        );

        runtime.drive_effects(&mut controller, vec![ControllerEffect::StopSpeechCapture]);

        assert_eq!(
            controller.state.status_message.as_deref(),
            Some("No audio was captured.")
        );
    }
}
