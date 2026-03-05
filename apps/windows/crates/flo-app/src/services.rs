use std::{fs, path::PathBuf};

use async_trait::async_trait;
use flo_core::ports::{
    AuthService, CoreError, CoreResult, ElevationPromptOutcome, ElevationService,
    FloatingBarActions, FloatingBarChipModel, FloatingBarManaging, PermissionSettingsTarget,
    PermissionsService, SelectionReaderService, SpeechCaptureService, TTSService,
    TextInjectionService,
};
use flo_domain::{
    AppIntegrityLevel, AuthState, PermissionKind, PermissionState, PermissionStatus,
    SelectionReadResult, TextInjectionFailureReason, UserSession,
};
use flo_platform_win::prefs::{
    JsonDictationPreferencesStore, JsonVoicePreferencesStore, MemoryAuthStateSink,
};

#[derive(Default)]
pub struct DefaultAuthService {
    session: Option<UserSession>,
}

impl DefaultAuthService {
    pub fn with_session(session: Option<UserSession>) -> Self {
        Self { session }
    }
}

#[async_trait]
impl AuthService for DefaultAuthService {
    async fn restore_session(&mut self) -> Option<UserSession> {
        self.session.clone()
    }

    async fn start_oauth(&mut self) -> CoreResult<UserSession> {
        self.session
            .clone()
            .ok_or(CoreError::Unauthorized)
            .map(|session| {
                self.session = Some(session.clone());
                session
            })
    }

    async fn refresh_session(&mut self, session: &UserSession) -> CoreResult<UserSession> {
        self.session = Some(session.clone());
        Ok(session.clone())
    }

    async fn logout(&mut self) -> CoreResult<()> {
        self.session = None;
        Ok(())
    }
}

#[derive(Default)]
pub struct EmptySelectionReaderService;

impl SelectionReaderService for EmptySelectionReaderService {
    fn read_selected_text(&mut self) -> CoreResult<SelectionReadResult> {
        Err(CoreError::SelectionUnavailable)
    }
}

#[derive(Default)]
pub struct NoopTextInjectionService;

impl TextInjectionService for NoopTextInjectionService {
    fn inject_text(&mut self, _text: &str) -> Result<(), TextInjectionFailureReason> {
        Ok(())
    }

    fn replace_recent_text(
        &mut self,
        _previous_text: &str,
        _updated_text: &str,
    ) -> Result<(), TextInjectionFailureReason> {
        Ok(())
    }
}

pub struct DefaultElevationService {
    app_integrity: AppIntegrityLevel,
    target_integrity: AppIntegrityLevel,
}

impl Default for DefaultElevationService {
    fn default() -> Self {
        Self {
            app_integrity: AppIntegrityLevel::Medium,
            target_integrity: AppIntegrityLevel::Medium,
        }
    }
}

impl ElevationService for DefaultElevationService {
    fn current_integrity_level(&self) -> CoreResult<AppIntegrityLevel> {
        Ok(self.app_integrity)
    }

    fn focused_target_integrity_level(&self) -> CoreResult<AppIntegrityLevel> {
        Ok(self.target_integrity)
    }

    fn request_elevated_relaunch(&mut self, _reason: &str) -> CoreResult<ElevationPromptOutcome> {
        Ok(ElevationPromptOutcome::PromptDeclined)
    }
}

#[derive(Default)]
pub struct InMemoryPermissionsService {
    status: PermissionStatus,
}

impl PermissionsService for InMemoryPermissionsService {
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
        Ok(match permission {
            PermissionKind::Microphone => PermissionSettingsTarget::MicrophonePrivacy,
            PermissionKind::Accessibility => PermissionSettingsTarget::AccessibilityPrivacy,
            PermissionKind::InputMonitoring => PermissionSettingsTarget::InputMonitoringPrivacy,
        })
    }
}

#[derive(Default)]
pub struct InMemoryFloatingBarService {
    pub last_model: Option<FloatingBarChipModel>,
}

impl FloatingBarManaging for InMemoryFloatingBarService {
    fn set_actions(&mut self, _actions: Option<FloatingBarActions>) -> CoreResult<()> {
        Ok(())
    }

    fn render_chip(&mut self, model: &FloatingBarChipModel) -> CoreResult<()> {
        self.last_model = Some(model.clone());
        Ok(())
    }

    fn hide(&mut self) -> CoreResult<()> {
        self.last_model = None;
        Ok(())
    }
}

pub struct FileSpeechCaptureService {
    capture_path: PathBuf,
    active: bool,
}

impl FileSpeechCaptureService {
    pub fn new(capture_path: PathBuf) -> Self {
        Self {
            capture_path,
            active: false,
        }
    }
}

impl SpeechCaptureService for FileSpeechCaptureService {
    fn start_capture(
        &mut self,
        _level_handler: Box<dyn FnMut(f32) + Send>,
        _transcript_handler: Option<Box<dyn FnMut(String) + Send>>,
    ) -> CoreResult<()> {
        self.active = true;
        Ok(())
    }

    fn stop_capture(&mut self) -> CoreResult<PathBuf> {
        if !self.active {
            return Err(CoreError::Platform("capture not active".to_string()));
        }
        self.active = false;

        if !self.capture_path.exists() {
            if let Some(parent) = self.capture_path.parent() {
                fs::create_dir_all(parent).map_err(|err| CoreError::Io(err.to_string()))?;
            }
            fs::write(&self.capture_path, "").map_err(|err| CoreError::Io(err.to_string()))?;
        }

        Ok(self.capture_path.clone())
    }

    fn cancel_capture(&mut self) {
        self.active = false;
    }
}

#[derive(Default)]
pub struct NoopTtsService;

#[async_trait]
impl TTSService for NoopTtsService {
    async fn synthesize_and_play(
        &mut self,
        _text: &str,
        _auth_token: &str,
        _voice: &str,
        _speed: f32,
    ) -> CoreResult<()> {
        Ok(())
    }

    fn stop_playback(&mut self) -> CoreResult<()> {
        Ok(())
    }
}

pub struct RuntimeServiceBundle {
    pub auth_service: DefaultAuthService,
    pub selection_reader: EmptySelectionReaderService,
    pub text_injection: NoopTextInjectionService,
    pub elevation_service: DefaultElevationService,
    pub permissions_service: InMemoryPermissionsService,
    pub floating_bar: InMemoryFloatingBarService,
    pub dictation_store: JsonDictationPreferencesStore,
    pub voice_store: JsonVoicePreferencesStore,
    pub auth_state_sink: MemoryAuthStateSink,
    pub speech_capture: FileSpeechCaptureService,
    pub tts_service: NoopTtsService,
}

impl RuntimeServiceBundle {
    pub fn from_data_dir(data_dir: PathBuf) -> Self {
        let prefs_dir = data_dir.join("preferences");
        let capture_path = data_dir.join("runtime").join("capture.txt");

        Self {
            auth_service: DefaultAuthService::with_session(None),
            selection_reader: EmptySelectionReaderService,
            text_injection: NoopTextInjectionService,
            elevation_service: DefaultElevationService::default(),
            permissions_service: InMemoryPermissionsService::default(),
            floating_bar: InMemoryFloatingBarService::default(),
            dictation_store: JsonDictationPreferencesStore::new(
                prefs_dir.join("dictation-preferences.json"),
            ),
            voice_store: JsonVoicePreferencesStore::new(prefs_dir.join("voice-preferences.json")),
            auth_state_sink: MemoryAuthStateSink::default(),
            speech_capture: FileSpeechCaptureService::new(capture_path),
            tts_service: NoopTtsService,
        }
    }

    pub fn snapshot_auth_state(&self) -> Option<&AuthState> {
        self.auth_state_sink.last_state()
    }
}
