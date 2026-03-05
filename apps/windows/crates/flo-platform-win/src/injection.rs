use flo_domain::{AppIntegrityLevel, TextInjectionFailureReason};
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InjectionMode {
    Append,
    Replace { previous_text: String },
}

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum InjectionPlatformError {
    #[error("platform error: {0}")]
    Platform(String),
}

pub type InjectionPlatformResult<T> = Result<T, InjectionPlatformError>;
pub type InjectionResult<T> = Result<T, TextInjectionFailureReason>;

pub trait FocusedWindowInspector: Send + Sync {
    fn is_secure_field_focused(&self) -> InjectionPlatformResult<bool>;
    fn focused_target_integrity_level(&self) -> InjectionPlatformResult<AppIntegrityLevel>;
}

pub trait SendInputExecutor: Send + Sync {
    fn send_unicode_text(&self, text: &str) -> InjectionPlatformResult<()>;
    fn send_backspaces(&self, count: usize) -> InjectionPlatformResult<()>;
}

pub struct SendInputTextInjector<I, E>
where
    I: FocusedWindowInspector,
    E: SendInputExecutor,
{
    app_integrity: AppIntegrityLevel,
    inspector: I,
    executor: E,
}

impl<I, E> SendInputTextInjector<I, E>
where
    I: FocusedWindowInspector,
    E: SendInputExecutor,
{
    pub fn new(app_integrity: AppIntegrityLevel, inspector: I, executor: E) -> Self {
        Self {
            app_integrity,
            inspector,
            executor,
        }
    }

    pub fn inject(&self, mode: InjectionMode, text: &str) -> InjectionResult<()> {
        self.ensure_injection_allowed()?;

        match mode {
            InjectionMode::Append => self
                .executor
                .send_unicode_text(text)
                .map_err(|_| TextInjectionFailureReason::GenericFailure),
            InjectionMode::Replace { previous_text } => {
                let replace_len = previous_text.chars().count();
                if replace_len > 0 {
                    self.executor
                        .send_backspaces(replace_len)
                        .map_err(|_| TextInjectionFailureReason::GenericFailure)?;
                }
                self.executor
                    .send_unicode_text(text)
                    .map_err(|_| TextInjectionFailureReason::GenericFailure)
            }
        }
    }

    fn ensure_injection_allowed(&self) -> InjectionResult<()> {
        let secure_field = self
            .inspector
            .is_secure_field_focused()
            .map_err(|_| TextInjectionFailureReason::GenericFailure)?;
        if secure_field {
            return Err(TextInjectionFailureReason::SecureField);
        }

        let target_integrity = self
            .inspector
            .focused_target_integrity_level()
            .map_err(|_| TextInjectionFailureReason::GenericFailure)?;

        if integrity_mismatch_requires_elevation(self.app_integrity, target_integrity) {
            return Err(TextInjectionFailureReason::IntegrityMismatch {
                app_integrity: self.app_integrity,
                target_integrity,
            });
        }

        Ok(())
    }
}

pub fn integrity_mismatch_requires_elevation(
    app_integrity: AppIntegrityLevel,
    target_integrity: AppIntegrityLevel,
) -> bool {
    let target_privileged = matches!(
        target_integrity,
        AppIntegrityLevel::High | AppIntegrityLevel::System
    );
    let app_privileged = matches!(
        app_integrity,
        AppIntegrityLevel::High | AppIntegrityLevel::System
    );

    target_privileged && !app_privileged
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};

    use super::*;

    #[derive(Debug, Clone)]
    struct FakeInspector {
        secure_field: bool,
        target_integrity: AppIntegrityLevel,
    }

    impl FocusedWindowInspector for FakeInspector {
        fn is_secure_field_focused(&self) -> InjectionPlatformResult<bool> {
            Ok(self.secure_field)
        }

        fn focused_target_integrity_level(&self) -> InjectionPlatformResult<AppIntegrityLevel> {
            Ok(self.target_integrity)
        }
    }

    #[derive(Debug, Clone, Default)]
    struct FakeExecutor {
        writes: Arc<Mutex<Vec<String>>>,
        backspaces: Arc<Mutex<Vec<usize>>>,
        fail_writes: bool,
        fail_backspaces: bool,
    }

    impl FakeExecutor {
        fn writes(&self) -> Vec<String> {
            self.writes.lock().expect("lock writes").clone()
        }

        fn backspaces(&self) -> Vec<usize> {
            self.backspaces.lock().expect("lock backspaces").clone()
        }
    }

    impl SendInputExecutor for FakeExecutor {
        fn send_unicode_text(&self, text: &str) -> InjectionPlatformResult<()> {
            if self.fail_writes {
                return Err(InjectionPlatformError::Platform(
                    "send input failed".to_string(),
                ));
            }
            self.writes
                .lock()
                .expect("lock writes")
                .push(text.to_string());
            Ok(())
        }

        fn send_backspaces(&self, count: usize) -> InjectionPlatformResult<()> {
            if self.fail_backspaces {
                return Err(InjectionPlatformError::Platform(
                    "backspace injection failed".to_string(),
                ));
            }
            self.backspaces.lock().expect("lock backspaces").push(count);
            Ok(())
        }
    }

    #[test]
    fn secure_field_blocks_injection() {
        let injector = SendInputTextInjector::new(
            AppIntegrityLevel::Medium,
            FakeInspector {
                secure_field: true,
                target_integrity: AppIntegrityLevel::Medium,
            },
            FakeExecutor::default(),
        );

        let error = injector
            .inject(InjectionMode::Append, "hello")
            .expect_err("secure fields must block injection");
        assert_eq!(error, TextInjectionFailureReason::SecureField);
    }

    #[test]
    fn integrity_mismatch_is_reported_for_unelevated_app() {
        let injector = SendInputTextInjector::new(
            AppIntegrityLevel::Medium,
            FakeInspector {
                secure_field: false,
                target_integrity: AppIntegrityLevel::High,
            },
            FakeExecutor::default(),
        );

        let error = injector
            .inject(InjectionMode::Append, "hello")
            .expect_err("integrity mismatch should fail");
        assert_eq!(
            error,
            TextInjectionFailureReason::IntegrityMismatch {
                app_integrity: AppIntegrityLevel::Medium,
                target_integrity: AppIntegrityLevel::High,
            }
        );
    }

    #[test]
    fn append_mode_writes_text_when_allowed() {
        let executor = FakeExecutor::default();
        let injector = SendInputTextInjector::new(
            AppIntegrityLevel::High,
            FakeInspector {
                secure_field: false,
                target_integrity: AppIntegrityLevel::High,
            },
            executor.clone(),
        );

        injector
            .inject(InjectionMode::Append, "hello")
            .expect("append should succeed");

        assert_eq!(executor.writes(), vec!["hello".to_string()]);
        assert!(executor.backspaces().is_empty());
    }

    #[test]
    fn replace_mode_sends_backspaces_then_text() {
        let executor = FakeExecutor::default();
        let injector = SendInputTextInjector::new(
            AppIntegrityLevel::High,
            FakeInspector {
                secure_field: false,
                target_integrity: AppIntegrityLevel::High,
            },
            executor.clone(),
        );

        injector
            .inject(
                InjectionMode::Replace {
                    previous_text: "abc".to_string(),
                },
                "xyz",
            )
            .expect("replace should succeed");

        assert_eq!(executor.backspaces(), vec![3]);
        assert_eq!(executor.writes(), vec!["xyz".to_string()]);
    }

    #[test]
    fn platform_failures_surface_as_generic_failures() {
        let executor = FakeExecutor {
            fail_writes: true,
            ..FakeExecutor::default()
        };
        let injector = SendInputTextInjector::new(
            AppIntegrityLevel::High,
            FakeInspector {
                secure_field: false,
                target_integrity: AppIntegrityLevel::High,
            },
            executor,
        );

        let error = injector
            .inject(InjectionMode::Append, "hello")
            .expect_err("write failure should map to generic failure");
        assert_eq!(error, TextInjectionFailureReason::GenericFailure);
    }

    #[test]
    fn integrity_mismatch_helper_matches_privilege_boundary_rules() {
        assert!(!integrity_mismatch_requires_elevation(
            AppIntegrityLevel::Medium,
            AppIntegrityLevel::Medium
        ));
        assert!(!integrity_mismatch_requires_elevation(
            AppIntegrityLevel::High,
            AppIntegrityLevel::System
        ));
        assert!(integrity_mismatch_requires_elevation(
            AppIntegrityLevel::Medium,
            AppIntegrityLevel::System
        ));
    }
}
