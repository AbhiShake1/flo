use flo_domain::SelectionReadMethod;
use thiserror::Error;

pub type SelectionResult<T> = Result<T, SelectionError>;

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum SelectionError {
    #[error("uia unavailable")]
    UiaUnavailable,
    #[error("no selected text")]
    NoSelectedText,
    #[error("clipboard fallback unavailable")]
    ClipboardFallbackUnavailable,
    #[error("platform error: {0}")]
    Platform(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SelectionRead {
    pub text: String,
    pub method: SelectionReadMethod,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SelectionFallbackReason {
    UiaUnavailable,
    UiaReturnedEmptyText,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SelectionTelemetryEvent {
    ReadSucceeded {
        method: SelectionReadMethod,
        fallback_reason: Option<SelectionFallbackReason>,
    },
    ReadFailed {
        fallback_reason: Option<SelectionFallbackReason>,
    },
}

pub trait SelectionTelemetrySink: Send + Sync {
    fn record(&self, event: SelectionTelemetryEvent);
}

#[derive(Debug, Default, Clone, Copy)]
pub struct NoopSelectionTelemetry;

impl SelectionTelemetrySink for NoopSelectionTelemetry {
    fn record(&self, _event: SelectionTelemetryEvent) {}
}

pub trait UiaSelectionSource: Send + Sync {
    fn read_selected_text(&self) -> SelectionResult<String>;
}

pub trait ClipboardSelectionSource: Send + Sync {
    fn read_selected_text(&self) -> SelectionResult<String>;
}

pub struct WindowsSelectionReader<U, C, T = NoopSelectionTelemetry>
where
    U: UiaSelectionSource,
    C: ClipboardSelectionSource,
    T: SelectionTelemetrySink,
{
    uia_source: U,
    clipboard_source: C,
    telemetry: T,
}

impl<U, C> WindowsSelectionReader<U, C, NoopSelectionTelemetry>
where
    U: UiaSelectionSource,
    C: ClipboardSelectionSource,
{
    pub fn new(uia_source: U, clipboard_source: C) -> Self {
        Self {
            uia_source,
            clipboard_source,
            telemetry: NoopSelectionTelemetry,
        }
    }
}

impl<U, C, T> WindowsSelectionReader<U, C, T>
where
    U: UiaSelectionSource,
    C: ClipboardSelectionSource,
    T: SelectionTelemetrySink,
{
    pub fn with_telemetry(uia_source: U, clipboard_source: C, telemetry: T) -> Self {
        Self {
            uia_source,
            clipboard_source,
            telemetry,
        }
    }
}

pub trait SelectionReader: Send + Sync {
    fn read_via_uia(&self) -> SelectionResult<String>;
    fn read_via_clipboard_fallback(&self) -> SelectionResult<String>;

    fn read_selected_text(&self) -> SelectionResult<SelectionRead> {
        match self.read_via_uia() {
            Ok(text) if !text.trim().is_empty() => Ok(SelectionRead {
                text,
                method: SelectionReadMethod::UiAutomation,
            }),
            _ => {
                let text = self.read_via_clipboard_fallback()?;
                if text.trim().is_empty() {
                    return Err(SelectionError::NoSelectedText);
                }
                Ok(SelectionRead {
                    text,
                    method: SelectionReadMethod::ClipboardFallback,
                })
            }
        }
    }
}

impl<U, C, T> SelectionReader for WindowsSelectionReader<U, C, T>
where
    U: UiaSelectionSource,
    C: ClipboardSelectionSource,
    T: SelectionTelemetrySink,
{
    fn read_via_uia(&self) -> SelectionResult<String> {
        self.uia_source.read_selected_text()
    }

    fn read_via_clipboard_fallback(&self) -> SelectionResult<String> {
        self.clipboard_source.read_selected_text()
    }

    fn read_selected_text(&self) -> SelectionResult<SelectionRead> {
        match self.read_via_uia() {
            Ok(text) if !text.trim().is_empty() => {
                self.telemetry
                    .record(SelectionTelemetryEvent::ReadSucceeded {
                        method: SelectionReadMethod::UiAutomation,
                        fallback_reason: None,
                    });
                Ok(SelectionRead {
                    text,
                    method: SelectionReadMethod::UiAutomation,
                })
            }
            Ok(_) => self.read_via_clipboard_with_telemetry(Some(
                SelectionFallbackReason::UiaReturnedEmptyText,
            )),
            Err(_) => self
                .read_via_clipboard_with_telemetry(Some(SelectionFallbackReason::UiaUnavailable)),
        }
    }
}

impl<U, C, T> WindowsSelectionReader<U, C, T>
where
    U: UiaSelectionSource,
    C: ClipboardSelectionSource,
    T: SelectionTelemetrySink,
{
    fn read_via_clipboard_with_telemetry(
        &self,
        fallback_reason: Option<SelectionFallbackReason>,
    ) -> SelectionResult<SelectionRead> {
        match self.read_via_clipboard_fallback() {
            Ok(text) if !text.trim().is_empty() => {
                self.telemetry
                    .record(SelectionTelemetryEvent::ReadSucceeded {
                        method: SelectionReadMethod::ClipboardFallback,
                        fallback_reason,
                    });
                Ok(SelectionRead {
                    text,
                    method: SelectionReadMethod::ClipboardFallback,
                })
            }
            Ok(_) | Err(_) => {
                self.telemetry
                    .record(SelectionTelemetryEvent::ReadFailed { fallback_reason });
                Err(SelectionError::NoSelectedText)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};

    use super::*;

    #[derive(Debug)]
    struct FakeUiaSource {
        result: SelectionResult<String>,
    }

    impl UiaSelectionSource for FakeUiaSource {
        fn read_selected_text(&self) -> SelectionResult<String> {
            self.result.clone()
        }
    }

    #[derive(Debug)]
    struct FakeClipboardSource {
        result: SelectionResult<String>,
    }

    impl ClipboardSelectionSource for FakeClipboardSource {
        fn read_selected_text(&self) -> SelectionResult<String> {
            self.result.clone()
        }
    }

    #[derive(Debug, Clone, Default)]
    struct CapturingTelemetry {
        events: Arc<Mutex<Vec<SelectionTelemetryEvent>>>,
    }

    impl CapturingTelemetry {
        fn snapshot(&self) -> Vec<SelectionTelemetryEvent> {
            self.events.lock().expect("lock telemetry").clone()
        }
    }

    impl SelectionTelemetrySink for CapturingTelemetry {
        fn record(&self, event: SelectionTelemetryEvent) {
            self.events.lock().expect("lock telemetry").push(event);
        }
    }

    #[test]
    fn prefers_uia_when_text_is_available() {
        let telemetry = CapturingTelemetry::default();
        let reader = WindowsSelectionReader::with_telemetry(
            FakeUiaSource {
                result: Ok("uia text".to_string()),
            },
            FakeClipboardSource {
                result: Ok("clipboard text".to_string()),
            },
            telemetry.clone(),
        );

        let selection = reader.read_selected_text().expect("uia read should win");
        assert_eq!(selection.text, "uia text");
        assert_eq!(selection.method, SelectionReadMethod::UiAutomation);
        assert_eq!(
            telemetry.snapshot(),
            vec![SelectionTelemetryEvent::ReadSucceeded {
                method: SelectionReadMethod::UiAutomation,
                fallback_reason: None,
            }]
        );
    }

    #[test]
    fn falls_back_to_clipboard_when_uia_errors() {
        let telemetry = CapturingTelemetry::default();
        let reader = WindowsSelectionReader::with_telemetry(
            FakeUiaSource {
                result: Err(SelectionError::UiaUnavailable),
            },
            FakeClipboardSource {
                result: Ok("clipboard text".to_string()),
            },
            telemetry.clone(),
        );

        let selection = reader
            .read_selected_text()
            .expect("clipboard fallback should succeed");
        assert_eq!(selection.method, SelectionReadMethod::ClipboardFallback);
        assert_eq!(
            telemetry.snapshot(),
            vec![SelectionTelemetryEvent::ReadSucceeded {
                method: SelectionReadMethod::ClipboardFallback,
                fallback_reason: Some(SelectionFallbackReason::UiaUnavailable),
            }]
        );
    }

    #[test]
    fn falls_back_to_clipboard_when_uia_returns_empty_text() {
        let telemetry = CapturingTelemetry::default();
        let reader = WindowsSelectionReader::with_telemetry(
            FakeUiaSource {
                result: Ok("   ".to_string()),
            },
            FakeClipboardSource {
                result: Ok("clipboard text".to_string()),
            },
            telemetry.clone(),
        );

        let selection = reader
            .read_selected_text()
            .expect("clipboard fallback should succeed");
        assert_eq!(selection.method, SelectionReadMethod::ClipboardFallback);
        assert_eq!(
            telemetry.snapshot(),
            vec![SelectionTelemetryEvent::ReadSucceeded {
                method: SelectionReadMethod::ClipboardFallback,
                fallback_reason: Some(SelectionFallbackReason::UiaReturnedEmptyText),
            }]
        );
    }

    #[test]
    fn reports_no_selected_text_when_both_paths_fail() {
        let telemetry = CapturingTelemetry::default();
        let reader = WindowsSelectionReader::with_telemetry(
            FakeUiaSource {
                result: Err(SelectionError::UiaUnavailable),
            },
            FakeClipboardSource {
                result: Err(SelectionError::ClipboardFallbackUnavailable),
            },
            telemetry.clone(),
        );

        let error = reader
            .read_selected_text()
            .expect_err("both read paths should fail");
        assert!(matches!(error, SelectionError::NoSelectedText));
        assert_eq!(
            telemetry.snapshot(),
            vec![SelectionTelemetryEvent::ReadFailed {
                fallback_reason: Some(SelectionFallbackReason::UiaUnavailable),
            }]
        );
    }
}
