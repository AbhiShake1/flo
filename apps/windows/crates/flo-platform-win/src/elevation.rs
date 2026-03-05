use flo_domain::AppIntegrityLevel;
use thiserror::Error;

pub type ElevationResult<T> = Result<T, ElevationError>;

#[derive(Debug, Error)]
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

pub fn ensure_elevated_for_target(
    service: &dyn ElevationService,
    target_integrity: AppIntegrityLevel,
    reason: &str,
) -> ElevationResult<Option<ElevationDecision>> {
    if target_integrity != AppIntegrityLevel::High && target_integrity != AppIntegrityLevel::System
    {
        return Ok(None);
    }
    let app_integrity = service.current_integrity_level()?;
    if app_integrity == AppIntegrityLevel::High || app_integrity == AppIntegrityLevel::System {
        return Ok(Some(ElevationDecision::AlreadyElevated));
    }
    service.request_elevated_relaunch(reason).map(Some)
}
