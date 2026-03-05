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
}

pub trait ElevationService: Send + Sync {
    fn is_process_elevated(&self) -> bool;
    fn prompt_for_elevation(&self, reason: &str) -> ElevationResult<ElevationDecision>;
}

pub fn ensure_elevated_for_target(
    service: &dyn ElevationService,
    target_requires_elevation: bool,
    reason: &str,
) -> ElevationResult<Option<ElevationDecision>> {
    if !target_requires_elevation {
        return Ok(None);
    }
    if service.is_process_elevated() {
        return Ok(Some(ElevationDecision::AlreadyElevated));
    }
    service.prompt_for_elevation(reason).map(Some)
}
