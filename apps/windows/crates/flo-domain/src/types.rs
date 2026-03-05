use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::keys::KeyCombo;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UserSession {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub token_type: String,
    pub expires_at_unix_ms: i64,
    pub account_id: Option<String>,
}

impl UserSession {
    pub fn is_expired(&self, now_unix_ms: i64) -> bool {
        now_unix_ms >= self.expires_at_unix_ms
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum AuthState {
    LoggedOut,
    Authenticating,
    LoggedIn(UserSession),
    AuthError(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ShortcutAction {
    DictationHold,
    ReadSelectedText,
    PushToTalkToggle,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ShortcutBinding {
    pub action: ShortcutAction,
    pub combo: KeyCombo,
    pub enabled: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RecorderState {
    Idle,
    Listening,
    Transcribing,
    Injecting,
    Speaking,
    Error(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum FloatingBarState {
    Hidden,
    IdleReady,
    Listening,
    Transcribing,
    Injecting,
    Speaking,
    Error,
}

impl FloatingBarState {
    pub const fn canonical_message(self) -> &'static str {
        match self {
            Self::Hidden => "",
            Self::IdleReady => {
                "Hold your dictation shortcut to start dictating, or click to start or stop dictation."
            }
            Self::Listening => "Listening",
            Self::Transcribing => "Transcribing",
            Self::Injecting => "Injecting",
            Self::Speaking => "Click to stop narration.",
            Self::Error => "Something went wrong.",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum AppIntegrityLevel {
    Medium,
    High,
    System,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SelectionReadMethod {
    UiAutomation,
    ClipboardFallback,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PlatformErrorCode {
    OAuthMissingConfiguration,
    OAuthFailed,
    OAuthStateMismatch,
    OAuthAuthorizationCodeMissing,
    Unauthorized,
    EmptyAudioCapture,
    NoSelectedText,
    InjectionFailed,
    InjectionSecureInput,
    PermissionDenied,
    FeatureDisabled,
    NetworkError,
    PersistenceError,
    ElevationRequired,
    DictationClipboardFallback,
    DictationClipboardFallbackFailed,
    LiveTypingPaused,
    LiveFinalizationAppendCopied,
    LiveFinalizationAppendCopyFailed,
    LiveFinalizationReplace,
    ReadAloudCanceled,
    ReadAloudCompleted,
    VoicePreviewBusy,
}

impl PlatformErrorCode {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::OAuthMissingConfiguration => "oauth.missing_configuration",
            Self::OAuthFailed => "oauth.failed",
            Self::OAuthStateMismatch => "oauth.state_mismatch",
            Self::OAuthAuthorizationCodeMissing => "oauth.authorization_code_missing",
            Self::Unauthorized => "auth.unauthorized",
            Self::EmptyAudioCapture => "audio.empty_capture",
            Self::NoSelectedText => "selection.none",
            Self::InjectionFailed => "injection.generic_failed",
            Self::InjectionSecureInput => "injection.secure_input_active",
            Self::PermissionDenied => "permission.denied",
            Self::FeatureDisabled => "feature.disabled",
            Self::NetworkError => "network.error",
            Self::PersistenceError => "persistence.error",
            Self::ElevationRequired => "elevation.required_target",
            Self::DictationClipboardFallback => "dictation.fallback.clipboard_copied",
            Self::DictationClipboardFallbackFailed => "dictation.fallback.clipboard_failed",
            Self::LiveTypingPaused => "dictation.live_typing_paused",
            Self::LiveFinalizationAppendCopied => "dictation.live_finalization_append",
            Self::LiveFinalizationAppendCopyFailed => {
                "dictation.live_finalization_append_copy_failed"
            }
            Self::LiveFinalizationReplace => "dictation.live_finalization_replace",
            Self::ReadAloudCanceled => "read_aloud.canceled",
            Self::ReadAloudCompleted => "read_aloud.completed",
            Self::VoicePreviewBusy => "voice_preview.busy",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SelectionReadResult {
    pub text: String,
    pub method: SelectionReadMethod,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TextInjectionFailureReason {
    SecureField,
    IntegrityMismatch {
        app_integrity: AppIntegrityLevel,
        target_integrity: AppIntegrityLevel,
    },
    GenericFailure,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum HistoryEventKind {
    Dictation,
    ReadAloud,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryEntry {
    pub id: String,
    pub timestamp_unix_ms: i64,
    pub kind: HistoryEventKind,
    pub input_text: String,
    pub output_text: Option<String>,
    pub request_id: Option<String>,
    pub latency_ms: Option<u32>,
    pub success: bool,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum DictationBaseTone {
    Default,
    Professional,
    Friendly,
    Candid,
    Efficient,
    Nerdy,
    Quirky,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum DictationStyleLevel {
    Less,
    Default,
    More,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum DictationLiveFinalizationMode {
    AppendOnly,
    ReplaceWithFinal,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum DictationRewritePreset {
    Default,
    Professional,
    Friendly,
    Candid,
    Efficient,
    Nerdy,
    Quirky,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DictationRewritePreferences {
    pub rewrite_enabled: bool,
    pub live_typing_enabled: bool,
    pub live_finalization_mode: DictationLiveFinalizationMode,
    pub base_tone: DictationBaseTone,
    pub warmth: DictationStyleLevel,
    pub enthusiasm: DictationStyleLevel,
    pub headers_and_lists: DictationStyleLevel,
    pub emoji: DictationStyleLevel,
    pub custom_instructions: String,
}

impl Default for DictationRewritePreferences {
    fn default() -> Self {
        Self {
            rewrite_enabled: true,
            live_typing_enabled: false,
            live_finalization_mode: DictationLiveFinalizationMode::AppendOnly,
            base_tone: DictationBaseTone::Default,
            warmth: DictationStyleLevel::Default,
            enthusiasm: DictationStyleLevel::Default,
            headers_and_lists: DictationStyleLevel::Default,
            emoji: DictationStyleLevel::Less,
            custom_instructions: String::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VoicePreferences {
    pub voice: String,
    pub speed: f32,
}

impl Default for VoicePreferences {
    fn default() -> Self {
        Self {
            voice: "alloy".to_string(),
            speed: 1.0,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderRoutingOverrides {
    pub provider_order: Vec<String>,
    pub allow_cross_provider_fallback: Option<bool>,
    pub max_attempts: Option<u32>,
    pub failure_threshold: Option<u32>,
    pub cooldown_seconds: Option<u32>,
    pub allowed_providers: Option<Vec<String>>,
    pub rewrite_models_by_provider: Option<HashMap<String, String>>,
    pub rewrite_models_by_provider_credential_index:
        Option<HashMap<String, HashMap<String, String>>>,
}

impl Default for ProviderRoutingOverrides {
    fn default() -> Self {
        Self {
            provider_order: Vec::new(),
            allow_cross_provider_fallback: None,
            max_attempts: None,
            failure_threshold: None,
            cooldown_seconds: None,
            allowed_providers: None,
            rewrite_models_by_provider: None,
            rewrite_models_by_provider_credential_index: None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PermissionKind {
    Microphone,
    Accessibility,
    InputMonitoring,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PermissionState {
    Granted,
    Denied,
    NotDetermined,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PermissionStatus {
    pub microphone: PermissionState,
    pub accessibility: PermissionState,
    pub input_monitoring: PermissionState,
}

impl Default for PermissionStatus {
    fn default() -> Self {
        Self {
            microphone: PermissionState::NotDetermined,
            accessibility: PermissionState::NotDetermined,
            input_monitoring: PermissionState::NotDetermined,
        }
    }
}
