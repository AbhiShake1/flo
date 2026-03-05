use flo_core::ports::{
    CoreError, CoreResult, ElevationPromptOutcome, ElevationService as CoreElevationService,
    SelectionReaderService, TextInjectionService,
};
use flo_domain::{SelectionReadResult, TextInjectionFailureReason};

use crate::{
    elevation::{ElevationDecision, ElevationError, ElevationService as PlatformElevationService},
    injection::{InjectionMode, SendInputTextInjector},
    selection::{SelectionError, SelectionReader},
};

pub struct CoreSelectionReaderAdapter<R>
where
    R: SelectionReader,
{
    reader: R,
}

impl<R> CoreSelectionReaderAdapter<R>
where
    R: SelectionReader,
{
    pub fn new(reader: R) -> Self {
        Self { reader }
    }

    pub fn reader(&self) -> &R {
        &self.reader
    }
}

impl<R> SelectionReaderService for CoreSelectionReaderAdapter<R>
where
    R: SelectionReader + Send,
{
    fn read_selected_text(&mut self) -> CoreResult<SelectionReadResult> {
        let read = self
            .reader
            .read_selected_text()
            .map_err(map_selection_error)?;

        Ok(SelectionReadResult {
            text: read.text,
            method: read.method,
        })
    }
}

pub trait InjectionDriver: Send {
    fn inject_with_mode(
        &mut self,
        mode: InjectionMode,
        text: &str,
    ) -> Result<(), TextInjectionFailureReason>;
}

impl<I, E> InjectionDriver for SendInputTextInjector<I, E>
where
    I: crate::injection::FocusedWindowInspector + Send,
    E: crate::injection::SendInputExecutor + Send,
{
    fn inject_with_mode(
        &mut self,
        mode: InjectionMode,
        text: &str,
    ) -> Result<(), TextInjectionFailureReason> {
        self.inject(mode, text)
    }
}

pub struct CoreTextInjectionAdapter<D>
where
    D: InjectionDriver,
{
    driver: D,
}

impl<D> CoreTextInjectionAdapter<D>
where
    D: InjectionDriver,
{
    pub fn new(driver: D) -> Self {
        Self { driver }
    }
}

impl<D> TextInjectionService for CoreTextInjectionAdapter<D>
where
    D: InjectionDriver,
{
    fn inject_text(&mut self, text: &str) -> Result<(), TextInjectionFailureReason> {
        self.driver.inject_with_mode(InjectionMode::Append, text)
    }

    fn replace_recent_text(
        &mut self,
        previous_text: &str,
        updated_text: &str,
    ) -> Result<(), TextInjectionFailureReason> {
        self.driver.inject_with_mode(
            InjectionMode::Replace {
                previous_text: previous_text.to_string(),
            },
            updated_text,
        )
    }
}

pub struct CoreElevationServiceAdapter<E>
where
    E: PlatformElevationService,
{
    service: E,
}

impl<E> CoreElevationServiceAdapter<E>
where
    E: PlatformElevationService,
{
    pub fn new(service: E) -> Self {
        Self { service }
    }
}

impl<E> CoreElevationService for CoreElevationServiceAdapter<E>
where
    E: PlatformElevationService + Send,
{
    fn current_integrity_level(&self) -> CoreResult<flo_domain::AppIntegrityLevel> {
        self.service
            .current_integrity_level()
            .map_err(map_elevation_error)
    }

    fn focused_target_integrity_level(&self) -> CoreResult<flo_domain::AppIntegrityLevel> {
        self.service
            .focused_target_integrity_level()
            .map_err(map_elevation_error)
    }

    fn request_elevated_relaunch(&mut self, reason: &str) -> CoreResult<ElevationPromptOutcome> {
        let decision = self
            .service
            .request_elevated_relaunch(reason)
            .map_err(map_elevation_error)?;

        let outcome = match decision {
            ElevationDecision::AlreadyElevated => ElevationPromptOutcome::AlreadyElevated,
            ElevationDecision::RelaunchRequested => ElevationPromptOutcome::RelaunchRequested,
            ElevationDecision::PromptDeclined => ElevationPromptOutcome::PromptDeclined,
        };
        Ok(outcome)
    }
}

fn map_selection_error(error: SelectionError) -> CoreError {
    match error {
        SelectionError::NoSelectedText => CoreError::SelectionUnavailable,
        SelectionError::UiaUnavailable | SelectionError::ClipboardFallbackUnavailable => {
            CoreError::SelectionUnavailable
        }
        SelectionError::Platform(message) => CoreError::Platform(message),
    }
}

fn map_elevation_error(error: ElevationError) -> CoreError {
    match error {
        ElevationError::PromptCanceled => {
            CoreError::PermissionDenied("Elevation prompt canceled".to_string())
        }
        ElevationError::RelaunchFailed(message) => CoreError::Platform(message),
        ElevationError::Platform(message) => CoreError::Platform(message),
    }
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};

    use flo_core::ports::ElevationService as _;
    use flo_domain::{AppIntegrityLevel, SelectionReadMethod};

    use super::*;
    use crate::selection::SelectionRead;

    struct FakeSelectionReader {
        next: Result<SelectionRead, SelectionError>,
    }

    impl SelectionReader for FakeSelectionReader {
        fn read_via_uia(&self) -> Result<String, SelectionError> {
            unreachable!("not used in test")
        }

        fn read_via_clipboard_fallback(&self) -> Result<String, SelectionError> {
            unreachable!("not used in test")
        }

        fn read_selected_text(&self) -> Result<SelectionRead, SelectionError> {
            self.next.clone()
        }
    }

    #[test]
    fn selection_adapter_maps_success_result() {
        let mut adapter = CoreSelectionReaderAdapter::new(FakeSelectionReader {
            next: Ok(SelectionRead {
                text: "hello".to_string(),
                method: SelectionReadMethod::UiAutomation,
            }),
        });

        let read = adapter.read_selected_text().expect("read should succeed");
        assert_eq!(read.text, "hello");
        assert_eq!(read.method, SelectionReadMethod::UiAutomation);
    }

    #[test]
    fn selection_adapter_maps_no_selection_to_core_error() {
        let mut adapter = CoreSelectionReaderAdapter::new(FakeSelectionReader {
            next: Err(SelectionError::NoSelectedText),
        });

        let err = adapter
            .read_selected_text()
            .expect_err("no selection should fail");
        assert!(matches!(err, CoreError::SelectionUnavailable));
    }

    #[derive(Clone, Default)]
    struct CapturingInjectionDriver {
        calls: Arc<Mutex<Vec<(InjectionMode, String)>>>,
    }

    impl InjectionDriver for CapturingInjectionDriver {
        fn inject_with_mode(
            &mut self,
            mode: InjectionMode,
            text: &str,
        ) -> Result<(), TextInjectionFailureReason> {
            self.calls
                .lock()
                .expect("lock calls")
                .push((mode, text.to_string()));
            Ok(())
        }
    }

    #[test]
    fn text_injection_adapter_uses_append_and_replace_modes() {
        let driver = CapturingInjectionDriver::default();
        let snapshot = driver.clone();
        let mut adapter = CoreTextInjectionAdapter::new(driver);

        adapter.inject_text("hello").expect("append should succeed");
        adapter
            .replace_recent_text("old", "new")
            .expect("replace should succeed");

        let calls = snapshot.calls.lock().expect("lock calls").clone();
        assert_eq!(calls.len(), 2);
        assert_eq!(calls[0], (InjectionMode::Append, "hello".to_string()));
        assert_eq!(
            calls[1],
            (
                InjectionMode::Replace {
                    previous_text: "old".to_string(),
                },
                "new".to_string(),
            )
        );
    }

    #[derive(Clone, Copy)]
    struct FakeElevationService {
        app_integrity: AppIntegrityLevel,
        target_integrity: AppIntegrityLevel,
        decision: ElevationDecision,
    }

    impl PlatformElevationService for FakeElevationService {
        fn current_integrity_level(&self) -> Result<AppIntegrityLevel, ElevationError> {
            Ok(self.app_integrity)
        }

        fn focused_target_integrity_level(&self) -> Result<AppIntegrityLevel, ElevationError> {
            Ok(self.target_integrity)
        }

        fn request_elevated_relaunch(
            &self,
            _reason: &str,
        ) -> Result<ElevationDecision, ElevationError> {
            Ok(self.decision)
        }
    }

    #[test]
    fn elevation_adapter_maps_decisions_to_core_outcomes() {
        let mut adapter = CoreElevationServiceAdapter::new(FakeElevationService {
            app_integrity: AppIntegrityLevel::Medium,
            target_integrity: AppIntegrityLevel::High,
            decision: ElevationDecision::RelaunchRequested,
        });

        let outcome = adapter
            .request_elevated_relaunch("need admin")
            .expect("request should succeed");

        assert_eq!(outcome, ElevationPromptOutcome::RelaunchRequested);
    }
}
