use flo_domain::SelectionReadMethod;
use thiserror::Error;

pub type SelectionResult<T> = Result<T, SelectionError>;

#[derive(Debug, Error)]
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
