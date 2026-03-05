#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use flo_core::{
        capabilities::PlatformCapabilities,
        controller::{
            ControllerEffect, ControllerEvent, FloCommand, FloController, LiveFinalizationPlan,
        },
    };
    use flo_domain::{
        DictationLiveFinalizationMode, PermissionState, PermissionStatus, ProviderRoutingOverrides,
        RecorderState, SelectionReadMethod,
    };
    use flo_platform_win::{
        elevation::{
            ensure_elevated_for_target, ElevationDecision,
            ElevationService as PlatformElevationService,
        },
        selection::{
            ClipboardSelectionSource, SelectionError, SelectionReader, UiaSelectionSource,
            WindowsSelectionReader,
        },
    };
    use flo_provider::{
        config::FloConfiguration,
        routing::{build_attempt_plan, merge_routing_overrides},
    };

    struct StubUiaSource {
        result: Result<String, SelectionError>,
    }

    impl UiaSelectionSource for StubUiaSource {
        fn read_selected_text(&self) -> Result<String, SelectionError> {
            self.result.clone()
        }
    }

    struct StubClipboardSource {
        result: Result<String, SelectionError>,
    }

    impl ClipboardSelectionSource for StubClipboardSource {
        fn read_selected_text(&self) -> Result<String, SelectionError> {
            self.result.clone()
        }
    }

    struct StubElevationService {
        app_integrity: flo_domain::AppIntegrityLevel,
    }

    impl PlatformElevationService for StubElevationService {
        fn current_integrity_level(
            &self,
        ) -> Result<flo_domain::AppIntegrityLevel, flo_platform_win::elevation::ElevationError>
        {
            Ok(self.app_integrity)
        }

        fn focused_target_integrity_level(
            &self,
        ) -> Result<flo_domain::AppIntegrityLevel, flo_platform_win::elevation::ElevationError>
        {
            Ok(flo_domain::AppIntegrityLevel::High)
        }

        fn request_elevated_relaunch(
            &self,
            _reason: &str,
        ) -> Result<ElevationDecision, flo_platform_win::elevation::ElevationError> {
            Ok(ElevationDecision::RelaunchRequested)
        }
    }

    #[test]
    fn acceptance_a1_dictation_hold_flow() {
        let capabilities = PlatformCapabilities::win32_default();
        let mut controller = FloController::new();

        let effects = controller.dispatch(FloCommand::StartDictationFromHotkey, &capabilities);
        assert_eq!(controller.state.recorder_state, RecorderState::Listening);
        assert_eq!(
            effects,
            vec![
                ControllerEffect::ShowFloatingBar(flo_domain::FloatingBarState::Listening),
                ControllerEffect::StartSpeechCapture,
            ]
        );

        let stop_effects = controller.dispatch(FloCommand::StopDictationFromHotkey, &capabilities);
        assert_eq!(controller.state.recorder_state, RecorderState::Transcribing);
        assert_eq!(
            stop_effects,
            vec![
                ControllerEffect::UpdateFloatingBar(flo_domain::FloatingBarState::Transcribing),
                ControllerEffect::StopSpeechCapture,
            ]
        );

        let finalization_effects = controller.apply_event(ControllerEvent::CaptureStopped {
            transcript: "hello world".to_string(),
        });
        assert_eq!(controller.state.recorder_state, RecorderState::Injecting);
        assert_eq!(
            finalization_effects,
            vec![
                ControllerEffect::UpdateFloatingBar(flo_domain::FloatingBarState::Injecting),
                ControllerEffect::FinalizeDictation(LiveFinalizationPlan::InjectDelta(
                    "hello world".to_string()
                )),
            ]
        );
    }

    #[test]
    fn acceptance_a2_read_selected_uia_and_clipboard_fallback() {
        let uia_reader = WindowsSelectionReader::new(
            StubUiaSource {
                result: Ok("uia text".to_string()),
            },
            StubClipboardSource {
                result: Ok("clipboard text".to_string()),
            },
        );
        let uia_read = uia_reader.read_selected_text().expect("uia should succeed");
        assert_eq!(uia_read.method, SelectionReadMethod::UiAutomation);

        let fallback_reader = WindowsSelectionReader::new(
            StubUiaSource {
                result: Err(SelectionError::UiaUnavailable),
            },
            StubClipboardSource {
                result: Ok("clipboard text".to_string()),
            },
        );
        let fallback_read = fallback_reader
            .read_selected_text()
            .expect("clipboard fallback should succeed");
        assert_eq!(fallback_read.method, SelectionReadMethod::ClipboardFallback);
    }

    #[test]
    fn acceptance_a3_elevated_target_flow_requests_relaunch() {
        let service = StubElevationService {
            app_integrity: flo_domain::AppIntegrityLevel::Medium,
        };

        let decision = ensure_elevated_for_target(
            &service,
            flo_domain::AppIntegrityLevel::High,
            "inject text",
        )
        .expect("elevation check should succeed");

        assert_eq!(decision, Some(ElevationDecision::RelaunchRequested));

        let mut controller = FloController::new();
        let capabilities = PlatformCapabilities {
            target_requires_elevation: true,
            elevated_mode: false,
            can_prompt_for_elevation: true,
            ..PlatformCapabilities::win32_default()
        };

        let effects = controller.dispatch(FloCommand::ReadSelectedTextFromHotkey, &capabilities);
        assert_eq!(effects, vec![ControllerEffect::PromptForElevation]);
    }

    #[test]
    fn acceptance_a4_missing_permissions_prompt_only_missing() {
        let mut controller = FloController::new();
        controller.state.permission_status = PermissionStatus {
            microphone: PermissionState::Denied,
            accessibility: PermissionState::Granted,
            input_monitoring: PermissionState::Denied,
        };

        let effects = controller.dispatch(
            FloCommand::PromptForRequiredPermissions,
            &PlatformCapabilities::win32_default(),
        );

        assert_eq!(
            effects,
            vec![
                ControllerEffect::RequestMicrophoneAccess,
                ControllerEffect::OpenSystemSettings(flo_domain::PermissionKind::InputMonitoring),
                ControllerEffect::RefreshPermissions,
            ]
        );
    }

    #[test]
    fn acceptance_a5_live_finalization_modes() {
        let mut controller = FloController::new();

        controller.state.live_dictation_enabled = true;
        controller.state.live_transcript_preview = "hello".to_string();
        controller
            .state
            .dictation_rewrite_preferences
            .live_finalization_mode = DictationLiveFinalizationMode::AppendOnly;

        let append_effects = controller.apply_event(ControllerEvent::CaptureStopped {
            transcript: "hello world".to_string(),
        });
        assert!(
            append_effects.contains(&ControllerEffect::FinalizeDictation(
                LiveFinalizationPlan::InjectDelta(" world".to_string()),
            ))
        );

        controller.state.live_transcript_preview = "draft".to_string();
        controller
            .state
            .dictation_rewrite_preferences
            .live_finalization_mode = DictationLiveFinalizationMode::ReplaceWithFinal;

        let replace_effects = controller.apply_event(ControllerEvent::CaptureStopped {
            transcript: "final text".to_string(),
        });
        assert!(
            replace_effects.contains(&ControllerEffect::FinalizeDictation(
                LiveFinalizationPlan::ReplaceWithFinal("final text".to_string()),
            ))
        );
    }

    #[test]
    fn acceptance_a6_provider_failover_order() {
        let mut env = HashMap::new();
        env.insert("FLO_PROVIDER".to_string(), "openai".to_string());
        env.insert(
            "FLO_PROVIDER_ORDER".to_string(),
            "openai,gemini".to_string(),
        );
        env.insert(
            "FLO_FAILOVER_ALLOW_CROSS_PROVIDER_FALLBACK".to_string(),
            "true".to_string(),
        );
        env.insert("FLO_FAILOVER_MAX_ATTEMPTS".to_string(), "4".to_string());
        let base = FloConfiguration::from_env_map(&env).expect("base config should parse");

        let overrides = ProviderRoutingOverrides {
            provider_order: vec!["openai".to_string(), "gemini".to_string()],
            allow_cross_provider_fallback: Some(true),
            max_attempts: Some(4),
            failure_threshold: Some(1),
            cooldown_seconds: Some(0),
            allowed_providers: None,
            rewrite_models_by_provider: None,
            rewrite_models_by_provider_credential_index: None,
        };

        let merged = merge_routing_overrides(&base, &overrides);
        let credentials = HashMap::from([
            (
                "openai".to_string(),
                vec!["oa-key-1".to_string(), "oa-key-2".to_string()],
            ),
            ("gemini".to_string(), vec!["g-key-1".to_string()]),
        ]);

        let plan = build_attempt_plan(&merged, &credentials);
        let sequence = plan
            .iter()
            .map(|attempt| (attempt.provider.as_str(), attempt.credential_index))
            .collect::<Vec<_>>();

        assert_eq!(
            sequence,
            vec![("openai", 0), ("openai", 1), ("gemini", 0), ("openai", 0),]
        );
    }
}
