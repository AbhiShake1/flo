use std::path::PathBuf;

use async_trait::async_trait;
use flo_domain::{
    AuthState, DictationRewritePreferences, PermissionKind, PermissionStatus, RecorderState,
    ShortcutBinding, UserSession,
};
use thiserror::Error;

pub type CoreResult<T> = Result<T, CoreError>;

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
    fn get_selected_text_uia(&mut self) -> CoreResult<String>;
    fn get_selected_text_clipboard_fallback(&mut self) -> CoreResult<String>;
}

pub trait TextInjectionService: Send {
    fn inject_text(&mut self, text: &str) -> CoreResult<()>;
    fn replace_recent_text(&mut self, previous_text: &str, updated_text: &str) -> CoreResult<()>;
    fn is_secure_field_active(&self) -> bool {
        false
    }
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

pub trait PermissionsService: Send {
    fn refresh_status(&mut self) -> PermissionStatus;
    fn request_microphone_access(&mut self) -> CoreResult<bool>;
    fn open_system_settings(&mut self, permission: PermissionKind) -> CoreResult<()>;
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FloatingBarBannerKind {
    Success,
    Warning,
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
    fn show(&mut self, state: RecorderState) -> CoreResult<()>;
    fn update(&mut self, state: RecorderState) -> CoreResult<()>;
    fn update_audio_level(&mut self, level: f32) -> CoreResult<()>;
    fn show_banner(&mut self, message: &str, kind: FloatingBarBannerKind) -> CoreResult<()>;
    fn hide(&mut self) -> CoreResult<()>;
}

pub trait DictationPreferencesStore: Send {
    fn load(&self) -> DictationRewritePreferences;
    fn save(&mut self, preferences: &DictationRewritePreferences) -> CoreResult<()>;
}

pub trait AuthStateSink: Send {
    fn update_auth_state(&mut self, auth_state: AuthState);
}
