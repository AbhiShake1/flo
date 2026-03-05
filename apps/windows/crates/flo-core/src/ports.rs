use std::path::PathBuf;

use async_trait::async_trait;
use flo_domain::{
    AppIntegrityLevel, AuthState, DictationRewritePreferences, FloatingBarState, PermissionKind,
    PermissionStatus, PlatformErrorCode, SelectionReadResult, ShortcutBinding,
    TextInjectionFailureReason, UserSession, VoicePreferences,
};
use thiserror::Error;

pub type CoreResult<T> = Result<T, CoreError>;
pub type InjectionResult<T> = Result<T, TextInjectionFailureReason>;

#[derive(Debug, Error)]
pub enum CoreError {
    #[error("unauthorized")]
    Unauthorized,
    #[error("permission denied: {0}")]
    PermissionDenied(String),
    #[error("selection unavailable")]
    SelectionUnavailable,
    #[error("injection failed")]
    InjectionFailed,
    #[error("secure input active")]
    SecureInputActive,
    #[error("io: {0}")]
    Io(String),
    #[error("platform: {0}")]
    Platform(String),
}

impl CoreError {
    pub const fn error_code(&self) -> PlatformErrorCode {
        match self {
            Self::Unauthorized => PlatformErrorCode::Unauthorized,
            Self::PermissionDenied(_) => PlatformErrorCode::PermissionDenied,
            Self::SelectionUnavailable => PlatformErrorCode::NoSelectedText,
            Self::InjectionFailed => PlatformErrorCode::InjectionFailed,
            Self::SecureInputActive => PlatformErrorCode::InjectionSecureInput,
            Self::Io(_) => PlatformErrorCode::PersistenceError,
            Self::Platform(_) => PlatformErrorCode::NetworkError,
        }
    }
}

#[async_trait]
pub trait AuthService: Send {
    async fn restore_session(&mut self) -> Option<UserSession>;
    async fn start_oauth(&mut self) -> CoreResult<UserSession>;
    async fn refresh_session(&mut self, session: &UserSession) -> CoreResult<UserSession>;
    async fn logout(&mut self) -> CoreResult<()>;
}

pub struct HotkeyHandlers {
    pub dictation_started: Box<dyn FnMut() + Send>,
    pub dictation_stopped: Box<dyn FnMut() + Send>,
    pub read_selected_triggered: Box<dyn FnMut() + Send>,
}

pub trait HotkeyManaging: Send {
    fn start(&mut self, bindings: &[ShortcutBinding], handlers: HotkeyHandlers) -> CoreResult<()>;
    fn stop(&mut self) -> CoreResult<()>;
}

pub trait SpeechCaptureService: Send {
    fn start_capture(
        &mut self,
        level_handler: Box<dyn FnMut(f32) + Send>,
        transcript_handler: Option<Box<dyn FnMut(String) + Send>>,
    ) -> CoreResult<()>;
    fn stop_capture(&mut self) -> CoreResult<PathBuf>;
    fn cancel_capture(&mut self);
}

pub trait SelectionReaderService: Send {
    fn read_selected_text(&mut self) -> CoreResult<SelectionReadResult>;
}

pub trait TextInjectionService: Send {
    fn inject_text(&mut self, text: &str) -> InjectionResult<()>;
    fn replace_recent_text(
        &mut self,
        previous_text: &str,
        updated_text: &str,
    ) -> InjectionResult<()>;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ElevationPromptOutcome {
    AlreadyElevated,
    RelaunchRequested,
    PromptDeclined,
}

pub trait ElevationService: Send {
    fn current_integrity_level(&self) -> CoreResult<AppIntegrityLevel>;
    fn focused_target_integrity_level(&self) -> CoreResult<AppIntegrityLevel>;
    fn request_elevated_relaunch(&mut self, reason: &str) -> CoreResult<ElevationPromptOutcome>;
}

#[async_trait]
pub trait TTSService: Send {
    async fn synthesize_and_play(
        &mut self,
        text: &str,
        auth_token: &str,
        voice: &str,
        speed: f32,
    ) -> CoreResult<()>;
    fn stop_playback(&mut self) -> CoreResult<()>;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PermissionSettingsTarget {
    MicrophonePrivacy,
    AccessibilityPrivacy,
    InputMonitoringPrivacy,
}

pub trait PermissionsService: Send {
    fn refresh_status(&mut self) -> PermissionStatus;
    fn request_microphone_access(&mut self) -> CoreResult<bool>;
    fn open_settings_target(
        &mut self,
        permission: PermissionKind,
    ) -> CoreResult<PermissionSettingsTarget>;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FloatingBarBannerKind {
    Success,
    Warning,
    Error,
}

#[derive(Debug, Clone, PartialEq)]
pub struct FloatingBarBanner {
    pub message: String,
    pub kind: FloatingBarBannerKind,
}

#[derive(Debug, Clone, PartialEq)]
pub struct FloatingBarChipModel {
    pub state: FloatingBarState,
    pub transcript_preview: Option<String>,
    pub level_meter: f32,
    pub hint_text: Option<String>,
    pub busy: bool,
    pub show_read_affordance: bool,
    pub banner: Option<FloatingBarBanner>,
}

impl Default for FloatingBarChipModel {
    fn default() -> Self {
        Self {
            state: FloatingBarState::Hidden,
            transcript_preview: None,
            level_meter: 0.0,
            hint_text: None,
            busy: false,
            show_read_affordance: true,
            banner: None,
        }
    }
}

pub struct FloatingBarActions {
    pub toggle_dictation: Box<dyn FnMut() + Send>,
    pub trigger_read_selected: Box<dyn FnMut() + Send>,
    pub open_main_window: Box<dyn FnMut() + Send>,
    pub dictation_hint: String,
    pub read_selected_hint: String,
}

pub trait FloatingBarManaging: Send {
    fn set_actions(&mut self, actions: Option<FloatingBarActions>) -> CoreResult<()>;
    fn render_chip(&mut self, model: &FloatingBarChipModel) -> CoreResult<()>;
    fn hide(&mut self) -> CoreResult<()>;
}

pub trait DictationPreferencesStore: Send {
    fn load(&self) -> DictationRewritePreferences;
    fn save(&mut self, preferences: &DictationRewritePreferences) -> CoreResult<()>;
}

pub trait VoicePreferencesStore: Send {
    fn load(&self) -> VoicePreferences;
    fn save(&mut self, preferences: &VoicePreferences) -> CoreResult<()>;
}

pub trait AuthStateSink: Send {
    fn update_auth_state(&mut self, auth_state: AuthState);
}
