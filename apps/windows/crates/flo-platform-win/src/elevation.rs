use std::{
    fs,
    path::{Path, PathBuf},
};

use flo_domain::AppIntegrityLevel;
use serde::{Deserialize, Serialize};
use thiserror::Error;

pub type ElevationResult<T> = Result<T, ElevationError>;

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum ElevationError {
    #[error("prompt canceled")]
    PromptCanceled,
    #[error("relaunch failed: {0}")]
    RelaunchFailed(String),
    #[error("platform error: {0}")]
    Platform(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ElevationDecision {
    AlreadyElevated,
    RelaunchRequested,
    PromptDeclined,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ElevationRelaunchHandoff {
    pub reason: String,
    pub pending_operation: String,
    pub created_unix_ms: i64,
}

pub trait ElevationService: Send + Sync {
    fn current_integrity_level(&self) -> ElevationResult<AppIntegrityLevel>;
    fn focused_target_integrity_level(&self) -> ElevationResult<AppIntegrityLevel>;
    fn request_elevated_relaunch(&self, reason: &str) -> ElevationResult<ElevationDecision>;
}

pub fn persist_relaunch_handoff(
    path: &Path,
    handoff: &ElevationRelaunchHandoff,
) -> ElevationResult<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|err| ElevationError::Platform(format!("create handoff dir: {err}")))?;
    }
    let payload = serde_json::to_vec_pretty(handoff)
        .map_err(|err| ElevationError::Platform(format!("serialize handoff: {err}")))?;
    fs::write(path, payload)
        .map_err(|err| ElevationError::Platform(format!("write handoff: {err}")))
}

pub fn take_relaunch_handoff(path: &Path) -> ElevationResult<Option<ElevationRelaunchHandoff>> {
    if !path.exists() {
        return Ok(None);
    }

    let payload =
        fs::read(path).map_err(|err| ElevationError::Platform(format!("read handoff: {err}")))?;
    let handoff: ElevationRelaunchHandoff = serde_json::from_slice(&payload)
        .map_err(|err| ElevationError::Platform(format!("parse handoff: {err}")))?;

    fs::remove_file(path)
        .map_err(|err| ElevationError::Platform(format!("clear handoff: {err}")))?;
    Ok(Some(handoff))
}

pub fn default_handoff_path(base_dir: &Path) -> PathBuf {
    base_dir.join("runtime").join("elevation-handoff.json")
}

pub fn integrity_requires_elevation(target_integrity: AppIntegrityLevel) -> bool {
    matches!(
        target_integrity,
        AppIntegrityLevel::High | AppIntegrityLevel::System
    )
}

pub fn ensure_elevated_for_focused_target(
    service: &dyn ElevationService,
    reason: &str,
) -> ElevationResult<Option<ElevationDecision>> {
    let target_integrity = service.focused_target_integrity_level()?;
    ensure_elevated_for_target(service, target_integrity, reason)
}

pub fn ensure_elevated_for_target(
    service: &dyn ElevationService,
    target_integrity: AppIntegrityLevel,
    reason: &str,
) -> ElevationResult<Option<ElevationDecision>> {
    if !integrity_requires_elevation(target_integrity) {
        return Ok(None);
    }

    let app_integrity = service.current_integrity_level()?;
    if integrity_requires_elevation(app_integrity) {
        return Ok(Some(ElevationDecision::AlreadyElevated));
    }

    service.request_elevated_relaunch(reason).map(Some)
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::*;

    #[derive(Debug, Clone)]
    struct MockElevationService {
        app_integrity: AppIntegrityLevel,
        target_integrity: AppIntegrityLevel,
        prompt_response: ElevationResult<ElevationDecision>,
        requested_reasons: Arc<Mutex<Vec<String>>>,
    }

    impl MockElevationService {
        fn with_levels(
            app_integrity: AppIntegrityLevel,
            target_integrity: AppIntegrityLevel,
        ) -> Self {
            Self {
                app_integrity,
                target_integrity,
                prompt_response: Ok(ElevationDecision::RelaunchRequested),
                requested_reasons: Arc::new(Mutex::new(Vec::new())),
            }
        }

        fn requested_reasons(&self) -> Vec<String> {
            self.requested_reasons
                .lock()
                .expect("lock requested reasons")
                .clone()
        }
    }

    impl ElevationService for MockElevationService {
        fn current_integrity_level(&self) -> ElevationResult<AppIntegrityLevel> {
            Ok(self.app_integrity)
        }

        fn focused_target_integrity_level(&self) -> ElevationResult<AppIntegrityLevel> {
            Ok(self.target_integrity)
        }

        fn request_elevated_relaunch(&self, reason: &str) -> ElevationResult<ElevationDecision> {
            self.requested_reasons
                .lock()
                .expect("lock requested reasons")
                .push(reason.to_string());
            self.prompt_response.clone()
        }
    }

    #[test]
    fn medium_target_does_not_require_elevation() {
        let service =
            MockElevationService::with_levels(AppIntegrityLevel::Medium, AppIntegrityLevel::Medium);

        let decision = ensure_elevated_for_focused_target(&service, "read-selected")
            .expect("call should succeed");

        assert_eq!(decision, None);
        assert!(service.requested_reasons().is_empty());
    }

    #[test]
    fn elevated_app_skips_prompt_for_high_target() {
        let service =
            MockElevationService::with_levels(AppIntegrityLevel::High, AppIntegrityLevel::High);

        let decision =
            ensure_elevated_for_focused_target(&service, "inject").expect("call should succeed");

        assert_eq!(decision, Some(ElevationDecision::AlreadyElevated));
        assert!(service.requested_reasons().is_empty());
    }

    #[test]
    fn medium_app_requests_relaunch_for_high_target() {
        let service =
            MockElevationService::with_levels(AppIntegrityLevel::Medium, AppIntegrityLevel::High);

        let decision =
            ensure_elevated_for_focused_target(&service, "inject").expect("call should succeed");

        assert_eq!(decision, Some(ElevationDecision::RelaunchRequested));
        assert_eq!(service.requested_reasons(), vec!["inject".to_string()]);
    }

    #[test]
    fn prompt_decline_is_propagated() {
        let mut service =
            MockElevationService::with_levels(AppIntegrityLevel::Medium, AppIntegrityLevel::System);
        service.prompt_response = Ok(ElevationDecision::PromptDeclined);

        let decision = ensure_elevated_for_focused_target(&service, "read-selected")
            .expect("call should succeed");

        assert_eq!(decision, Some(ElevationDecision::PromptDeclined));
        assert_eq!(
            service.requested_reasons(),
            vec!["read-selected".to_string()]
        );
    }

    #[test]
    fn integrity_requirement_helper_is_exact() {
        assert!(!integrity_requires_elevation(AppIntegrityLevel::Medium));
        assert!(!integrity_requires_elevation(AppIntegrityLevel::Unknown));
        assert!(integrity_requires_elevation(AppIntegrityLevel::High));
        assert!(integrity_requires_elevation(AppIntegrityLevel::System));
    }

    fn temp_handoff_path() -> PathBuf {
        let ts = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_nanos())
            .unwrap_or(0);
        std::env::temp_dir().join(format!("flo-elevation-handoff-{ts}.json"))
    }

    #[test]
    fn relaunch_handoff_roundtrip_persists_and_clears() {
        let path = temp_handoff_path();
        let handoff = ElevationRelaunchHandoff {
            reason: "target high integrity".to_string(),
            pending_operation: "read_selected_text".to_string(),
            created_unix_ms: 1_741_180_000_000,
        };

        persist_relaunch_handoff(&path, &handoff).expect("persist should succeed");
        assert!(path.exists());

        let loaded = take_relaunch_handoff(&path)
            .expect("load should succeed")
            .expect("handoff should exist");
        assert_eq!(loaded, handoff);
        assert!(!path.exists());
    }

    #[test]
    fn take_handoff_returns_none_when_missing() {
        let path = temp_handoff_path();
        let loaded = take_relaunch_handoff(&path).expect("lookup should succeed");
        assert_eq!(loaded, None);
    }
}
