use flo_domain::AppIntegrityLevel;
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

pub trait ElevationService: Send + Sync {
    fn current_integrity_level(&self) -> ElevationResult<AppIntegrityLevel>;
    fn focused_target_integrity_level(&self) -> ElevationResult<AppIntegrityLevel>;
    fn request_elevated_relaunch(&self, reason: &str) -> ElevationResult<ElevationDecision>;
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
}
