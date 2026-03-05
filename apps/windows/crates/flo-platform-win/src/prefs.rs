use std::{
    fs,
    path::{Path, PathBuf},
};

use flo_core::ports::{
    AuthStateSink, CoreError, CoreResult, DictationPreferencesStore, VoicePreferencesStore,
};
use flo_domain::{AuthState, DictationRewritePreferences, VoicePreferences};

#[derive(Debug, Clone)]
pub struct JsonDictationPreferencesStore {
    path: PathBuf,
}

impl JsonDictationPreferencesStore {
    pub fn new(path: PathBuf) -> Self {
        Self { path }
    }
}

impl DictationPreferencesStore for JsonDictationPreferencesStore {
    fn load(&self) -> DictationRewritePreferences {
        load_json_file::<DictationRewritePreferences>(&self.path).unwrap_or_default()
    }

    fn save(&mut self, preferences: &DictationRewritePreferences) -> CoreResult<()> {
        save_json_file(&self.path, preferences)
    }
}

#[derive(Debug, Clone)]
pub struct JsonVoicePreferencesStore {
    path: PathBuf,
}

impl JsonVoicePreferencesStore {
    pub fn new(path: PathBuf) -> Self {
        Self { path }
    }
}

impl VoicePreferencesStore for JsonVoicePreferencesStore {
    fn load(&self) -> VoicePreferences {
        load_json_file::<VoicePreferences>(&self.path).unwrap_or_default()
    }

    fn save(&mut self, preferences: &VoicePreferences) -> CoreResult<()> {
        save_json_file(&self.path, preferences)
    }
}

#[derive(Debug, Default, Clone)]
pub struct MemoryAuthStateSink {
    last_state: Option<AuthState>,
}

impl MemoryAuthStateSink {
    pub fn last_state(&self) -> Option<&AuthState> {
        self.last_state.as_ref()
    }
}

impl AuthStateSink for MemoryAuthStateSink {
    fn update_auth_state(&mut self, auth_state: AuthState) {
        self.last_state = Some(auth_state);
    }
}

fn load_json_file<T>(path: &Path) -> Option<T>
where
    T: serde::de::DeserializeOwned,
{
    let bytes = fs::read(path).ok()?;
    serde_json::from_slice(&bytes).ok()
}

fn save_json_file<T>(path: &Path, value: &T) -> CoreResult<()>
where
    T: serde::Serialize,
{
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| CoreError::Io(err.to_string()))?;
    }

    let bytes = serde_json::to_vec_pretty(value).map_err(|err| CoreError::Io(err.to_string()))?;
    fs::write(path, bytes).map_err(|err| CoreError::Io(err.to_string()))
}

#[cfg(test)]
mod tests {
    use std::time::{SystemTime, UNIX_EPOCH};

    use flo_core::ports::{DictationPreferencesStore, VoicePreferencesStore};

    use super::*;

    fn temp_path(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "flo-platform-win-{name}-{}.json",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or(0)
        ))
    }

    #[test]
    fn dictation_preferences_store_roundtrip() {
        let path = temp_path("dictation-prefs");
        let mut store = JsonDictationPreferencesStore::new(path.clone());

        let mut prefs = DictationRewritePreferences::default();
        prefs.custom_instructions = "be concise".to_string();

        store.save(&prefs).expect("save should succeed");
        let loaded = store.load();
        assert_eq!(loaded.custom_instructions, "be concise");

        let _ = fs::remove_file(path);
    }

    #[test]
    fn voice_preferences_store_roundtrip() {
        let path = temp_path("voice-prefs");
        let mut store = JsonVoicePreferencesStore::new(path.clone());

        let prefs = VoicePreferences {
            voice: "alloy".to_string(),
            speed: 1.25,
        };

        store.save(&prefs).expect("save should succeed");
        let loaded = store.load();
        assert_eq!(loaded.voice, "alloy");
        assert_eq!(loaded.speed, 1.25);

        let _ = fs::remove_file(path);
    }

    #[test]
    fn corrupt_json_falls_back_to_defaults() {
        let path = temp_path("corrupt-prefs");
        fs::write(&path, b"not json").expect("write corrupt file");

        let store = JsonVoicePreferencesStore::new(path.clone());
        let loaded = store.load();
        assert_eq!(loaded, VoicePreferences::default());

        let _ = fs::remove_file(path);
    }

    #[test]
    fn memory_auth_state_sink_tracks_latest_state() {
        let mut sink = MemoryAuthStateSink::default();
        sink.update_auth_state(AuthState::LoggedOut);

        assert!(matches!(sink.last_state(), Some(AuthState::LoggedOut)));
    }
}
