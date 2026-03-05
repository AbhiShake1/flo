use flo_core::controller::{canonical_error_message, ControllerEvent, FloController};
use flo_domain::{PlatformErrorCode, TextInjectionFailureReason};

#[test]
fn canonical_error_messages_match_parity_table() {
    assert_eq!(
        canonical_error_message(PlatformErrorCode::OAuthMissingConfiguration, None),
        "ChatGPT OAuth configuration is missing."
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::OAuthFailed, Some("boom")),
        "OAuth failed: boom"
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::OAuthStateMismatch, None),
        "OAuth failed: State mismatch"
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::OAuthAuthorizationCodeMissing, None),
        "OAuth failed: Authorization code missing"
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::Unauthorized, None),
        "You are not authenticated."
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::EmptyAudioCapture, None),
        "No audio was captured."
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::NoSelectedText, None),
        "No selected text."
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::InjectionFailed, None),
        "Failed to inject transcript into the focused app."
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::InjectionSecureInput, None),
        "Injection blocked while secure input is active."
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::PermissionDenied, Some("microphone")),
        "Permission denied: microphone."
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::FeatureDisabled, Some("Dictation")),
        "Dictation is disabled by configuration."
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::NetworkError, Some("timeout")),
        "Network error: timeout"
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::PersistenceError, Some("disk full")),
        "Persistence error: disk full"
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::ElevationRequired, None),
        "The focused app requires elevated mode. Please relaunch flo as admin."
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::DictationClipboardFallback, None),
        "Couldn't type transcript. Copied to clipboard instead."
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::DictationClipboardFallbackFailed, None),
        "Couldn't type transcript and could not copy to clipboard."
    );
    assert_eq!(
        canonical_error_message(
            PlatformErrorCode::LiveTypingPaused,
            Some("backend unavailable")
        ),
        "Live typing paused: backend unavailable. Final transcript will still complete."
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::LiveFinalizationAppendCopied, None),
        "Live transcript differed from final model output. Final transcript copied to clipboard."
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::LiveFinalizationAppendCopyFailed, None),
        "Live transcript differed from final model output. Could not copy final transcript to clipboard."
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::LiveFinalizationReplace, None),
        "Replaced live draft with final transcript."
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::ReadAloudCanceled, None),
        "Read-aloud canceled."
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::ReadAloudCompleted, None),
        "Read-aloud completed."
    );
    assert_eq!(
        canonical_error_message(PlatformErrorCode::VoicePreviewBusy, None),
        "Wait for the current action to finish, then try voice preview again."
    );
}

#[test]
fn injection_failures_map_to_specific_error_messages() {
    let mut controller = FloController::new();

    controller.apply_event(ControllerEvent::InjectionFailed(
        TextInjectionFailureReason::SecureField,
    ));
    assert_eq!(
        controller.state.status_message.as_deref(),
        Some("Injection blocked while secure input is active.")
    );

    controller.apply_event(ControllerEvent::InjectionFailed(
        TextInjectionFailureReason::IntegrityMismatch {
            app_integrity: flo_domain::AppIntegrityLevel::Medium,
            target_integrity: flo_domain::AppIntegrityLevel::High,
        },
    ));
    assert_eq!(
        controller.state.status_message.as_deref(),
        Some("The focused app requires elevated mode. Please relaunch flo as admin.")
    );

    controller.apply_event(ControllerEvent::InjectionFailed(
        TextInjectionFailureReason::GenericFailure,
    ));
    assert_eq!(
        controller.state.status_message.as_deref(),
        Some("Failed to inject transcript into the focused app.")
    );
}

#[test]
fn explicit_error_event_uses_canonical_message() {
    let mut controller = FloController::new();
    controller.apply_event(ControllerEvent::Error(PlatformErrorCode::NoSelectedText));
    assert_eq!(
        controller.state.status_message.as_deref(),
        Some("No selected text.")
    );
}
