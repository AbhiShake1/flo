use std::collections::VecDeque;

use flo_core::{
    controller::{ControllerEffect, ControllerEvent, FloController},
    ports::{
        CoreError, DictationPreferencesStore, ElevationPromptOutcome, ElevationService,
        FloatingBarChipModel, FloatingBarManaging, PermissionsService, SelectionReaderService,
        TextInjectionService, VoicePreferencesStore,
    },
};
use flo_domain::PlatformErrorCode;

pub struct EffectRuntime<'a> {
    selection_reader: &'a mut dyn SelectionReaderService,
    text_injection: &'a mut dyn TextInjectionService,
    elevation_service: &'a mut dyn ElevationService,
    permissions_service: &'a mut dyn PermissionsService,
    floating_bar: &'a mut dyn FloatingBarManaging,
    dictation_preferences_store: &'a mut dyn DictationPreferencesStore,
    voice_preferences_store: &'a mut dyn VoicePreferencesStore,
}

impl<'a> EffectRuntime<'a> {
    pub fn new(
        selection_reader: &'a mut dyn SelectionReaderService,
        text_injection: &'a mut dyn TextInjectionService,
        elevation_service: &'a mut dyn ElevationService,
        permissions_service: &'a mut dyn PermissionsService,
        floating_bar: &'a mut dyn FloatingBarManaging,
        dictation_preferences_store: &'a mut dyn DictationPreferencesStore,
        voice_preferences_store: &'a mut dyn VoicePreferencesStore,
    ) -> Self {
        Self {
            selection_reader,
            text_injection,
            elevation_service,
            permissions_service,
            floating_bar,
            dictation_preferences_store,
            voice_preferences_store,
        }
    }

    pub fn drive_effects(
        &mut self,
        controller: &mut FloController,
        initial_effects: Vec<ControllerEffect>,
    ) -> Vec<ControllerEffect> {
        let mut queue: VecDeque<ControllerEffect> = VecDeque::from(initial_effects);
        let mut derived_effects = Vec::new();

        while let Some(effect) = queue.pop_front() {
            let events = self.execute_effect(controller, &effect);
            for event in events {
                let next_effects = controller.apply_event(event);
                queue.extend(next_effects.iter().cloned());
                derived_effects.extend(next_effects);
            }
        }

        derived_effects
    }

    fn execute_effect(
        &mut self,
        controller: &FloController,
        effect: &ControllerEffect,
    ) -> Vec<ControllerEvent> {
        match effect {
            ControllerEffect::ReadSelected { .. } => {
                match self.selection_reader.read_selected_text() {
                    Ok(read) => vec![ControllerEvent::SelectionRead {
                        text: read.text,
                        method: read.method,
                    }],
                    Err(error) => vec![ControllerEvent::Error(error.error_code())],
                }
            }
            ControllerEffect::InjectText { text, .. } => {
                match self.text_injection.inject_text(text) {
                    Ok(()) => vec![ControllerEvent::InjectionCompleted],
                    Err(reason) => vec![ControllerEvent::InjectionFailed(reason)],
                }
            }
            ControllerEffect::FinalizeDictation(plan) => match plan {
                flo_core::controller::LiveFinalizationPlan::InjectDelta(text)
                | flo_core::controller::LiveFinalizationPlan::ReplaceWithFinal(text)
                | flo_core::controller::LiveFinalizationPlan::CopyFinalToClipboard(text) => {
                    match self.text_injection.inject_text(text) {
                        Ok(()) => vec![ControllerEvent::InjectionCompleted],
                        Err(reason) => vec![ControllerEvent::InjectionFailed(reason)],
                    }
                }
                flo_core::controller::LiveFinalizationPlan::Noop => Vec::new(),
            },
            ControllerEffect::PromptForElevation => {
                match self
                    .elevation_service
                    .request_elevated_relaunch("The focused app requires elevated mode")
                {
                    Ok(ElevationPromptOutcome::RelaunchRequested) => {
                        vec![ControllerEvent::ElevatedRelaunchRequested]
                    }
                    Ok(ElevationPromptOutcome::AlreadyElevated) => Vec::new(),
                    Ok(ElevationPromptOutcome::PromptDeclined) => {
                        vec![ControllerEvent::Error(PlatformErrorCode::PermissionDenied)]
                    }
                    Err(error) => vec![ControllerEvent::Error(error.error_code())],
                }
            }
            ControllerEffect::RefreshPermissions => {
                let status = self.permissions_service.refresh_status();
                vec![ControllerEvent::PermissionStatusUpdated(status)]
            }
            ControllerEffect::RequestPermission(permission) => {
                let request_result = match permission {
                    flo_domain::PermissionKind::Microphone => self
                        .permissions_service
                        .request_microphone_access()
                        .map(|_| ()),
                    flo_domain::PermissionKind::Accessibility
                    | flo_domain::PermissionKind::InputMonitoring => self
                        .permissions_service
                        .open_settings_target(*permission)
                        .map(|_| ()),
                };

                if let Err(error) = request_result {
                    return vec![ControllerEvent::Error(error.error_code())];
                }

                let status = self.permissions_service.refresh_status();
                vec![ControllerEvent::PermissionStatusUpdated(status)]
            }
            ControllerEffect::RequestMicrophoneAccess => {
                if let Err(error) = self.permissions_service.request_microphone_access() {
                    return vec![ControllerEvent::Error(error.error_code())];
                }
                let status = self.permissions_service.refresh_status();
                vec![ControllerEvent::PermissionStatusUpdated(status)]
            }
            ControllerEffect::PersistRewritePreferences => {
                if let Err(error) = self
                    .dictation_preferences_store
                    .save(&controller.state.dictation_rewrite_preferences)
                {
                    return vec![ControllerEvent::Error(error.error_code())];
                }
                Vec::new()
            }
            ControllerEffect::PersistVoicePreferences => {
                if let Err(error) = self
                    .voice_preferences_store
                    .save(&controller.state.voice_preferences)
                {
                    return vec![ControllerEvent::Error(error.error_code())];
                }
                Vec::new()
            }
            ControllerEffect::OpenSystemSettings(permission) => {
                if let Err(error) = self.permissions_service.open_settings_target(*permission) {
                    return vec![ControllerEvent::Error(error.error_code())];
                }
                Vec::new()
            }
            ControllerEffect::ShowFloatingBar(state)
            | ControllerEffect::UpdateFloatingBar(state) => {
                let model = FloatingBarChipModel {
                    state: *state,
                    transcript_preview: if controller.state.live_transcript_preview.is_empty() {
                        None
                    } else {
                        Some(controller.state.live_transcript_preview.clone())
                    },
                    level_meter: 0.0,
                    hint_text: if state.canonical_message().is_empty() {
                        None
                    } else {
                        Some(state.canonical_message().to_string())
                    },
                    busy: matches!(
                        state,
                        flo_domain::FloatingBarState::Transcribing
                            | flo_domain::FloatingBarState::Injecting
                    ),
                    show_read_affordance: !matches!(
                        state,
                        flo_domain::FloatingBarState::Listening
                            | flo_domain::FloatingBarState::Transcribing
                            | flo_domain::FloatingBarState::Injecting
                    ),
                    banner: None,
                };
                if let Err(error) = self.floating_bar.render_chip(&model) {
                    return vec![ControllerEvent::Error(error.error_code())];
                }
                Vec::new()
            }
            ControllerEffect::HideFloatingBar => {
                if let Err(error) = self.floating_bar.hide() {
                    return vec![ControllerEvent::Error(error.error_code())];
                }
                Vec::new()
            }
            _ => Vec::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use flo_core::{
        capabilities::PlatformCapabilities,
        controller::FloCommand,
        ports::{
            CoreResult, DictationPreferencesStore, FloatingBarActions, PermissionSettingsTarget,
            VoicePreferencesStore,
        },
    };
    use flo_domain::{
        AppIntegrityLevel, DictationRewritePreferences, PermissionKind, PermissionState,
        PermissionStatus, SelectionReadMethod, TextInjectionFailureReason, VoicePreferences,
    };

    use super::*;

    struct FakeSelectionService {
        read: Option<flo_domain::SelectionReadResult>,
    }

    impl SelectionReaderService for FakeSelectionService {
        fn read_selected_text(&mut self) -> CoreResult<flo_domain::SelectionReadResult> {
            self.read.clone().ok_or(CoreError::SelectionUnavailable)
        }
    }

    #[derive(Default)]
    struct FakeTextInjectionService {
        fail: Option<TextInjectionFailureReason>,
    }

    impl TextInjectionService for FakeTextInjectionService {
        fn inject_text(&mut self, _text: &str) -> Result<(), TextInjectionFailureReason> {
            match &self.fail {
                Some(reason) => Err(reason.clone()),
                None => Ok(()),
            }
        }

        fn replace_recent_text(
            &mut self,
            _previous_text: &str,
            _updated_text: &str,
        ) -> Result<(), TextInjectionFailureReason> {
            Ok(())
        }
    }

    struct FakeElevationService {
        outcome: ElevationPromptOutcome,
        fail: bool,
    }

    impl ElevationService for FakeElevationService {
        fn current_integrity_level(&self) -> CoreResult<AppIntegrityLevel> {
            Ok(AppIntegrityLevel::Medium)
        }

        fn focused_target_integrity_level(&self) -> CoreResult<AppIntegrityLevel> {
            Ok(AppIntegrityLevel::High)
        }

        fn request_elevated_relaunch(
            &mut self,
            _reason: &str,
        ) -> CoreResult<ElevationPromptOutcome> {
            if self.fail {
                return Err(CoreError::PermissionDenied(
                    "Elevation prompt failed".to_string(),
                ));
            }
            Ok(self.outcome)
        }
    }

    struct FakePermissionsService {
        status: PermissionStatus,
        opened_targets: Vec<PermissionKind>,
    }

    impl PermissionsService for FakePermissionsService {
        fn refresh_status(&mut self) -> PermissionStatus {
            self.status
        }

        fn request_microphone_access(&mut self) -> CoreResult<bool> {
            self.status.microphone = PermissionState::Granted;
            Ok(true)
        }

        fn open_settings_target(
            &mut self,
            permission: PermissionKind,
        ) -> CoreResult<PermissionSettingsTarget> {
            self.opened_targets.push(permission);
            Ok(match permission {
                PermissionKind::Microphone => PermissionSettingsTarget::MicrophonePrivacy,
                PermissionKind::Accessibility => PermissionSettingsTarget::AccessibilityPrivacy,
                PermissionKind::InputMonitoring => PermissionSettingsTarget::InputMonitoringPrivacy,
            })
        }
    }

    #[derive(Default)]
    struct FakeFloatingBarService {
        hide_calls: usize,
        render_calls: usize,
    }

    impl FloatingBarManaging for FakeFloatingBarService {
        fn set_actions(&mut self, _actions: Option<FloatingBarActions>) -> CoreResult<()> {
            Ok(())
        }

        fn render_chip(&mut self, _model: &FloatingBarChipModel) -> CoreResult<()> {
            self.render_calls += 1;
            Ok(())
        }

        fn hide(&mut self) -> CoreResult<()> {
            self.hide_calls += 1;
            Ok(())
        }
    }

    #[derive(Default)]
    struct FakeDictationPreferencesStore {
        saved: Option<DictationRewritePreferences>,
        fail: bool,
    }

    impl DictationPreferencesStore for FakeDictationPreferencesStore {
        fn load(&self) -> DictationRewritePreferences {
            self.saved.clone().unwrap_or_default()
        }

        fn save(&mut self, preferences: &DictationRewritePreferences) -> CoreResult<()> {
            if self.fail {
                return Err(CoreError::Io("dictation save failed".to_string()));
            }
            self.saved = Some(preferences.clone());
            Ok(())
        }
    }

    #[derive(Default)]
    struct FakeVoicePreferencesStore {
        saved: Option<VoicePreferences>,
        fail: bool,
    }

    impl VoicePreferencesStore for FakeVoicePreferencesStore {
        fn load(&self) -> VoicePreferences {
            self.saved.clone().unwrap_or_default()
        }

        fn save(&mut self, preferences: &VoicePreferences) -> CoreResult<()> {
            if self.fail {
                return Err(CoreError::Io("voice save failed".to_string()));
            }
            self.saved = Some(preferences.clone());
            Ok(())
        }
    }

    #[test]
    fn drive_effects_processes_read_selected_and_updates_controller_state() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService {
            read: Some(flo_domain::SelectionReadResult {
                text: "hello".to_string(),
                method: SelectionReadMethod::UiAutomation,
            }),
        };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::RelaunchRequested,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();

        let mut runtime = EffectRuntime::new(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
        );

        let effects = controller.dispatch(
            FloCommand::ReadSelectedTextFromHotkey,
            &PlatformCapabilities::win32_default(),
        );
        runtime.drive_effects(&mut controller, effects);

        assert_eq!(
            controller.state.last_selection_read_method,
            Some(SelectionReadMethod::UiAutomation)
        );
        assert_eq!(
            controller.state.recorder_state,
            flo_domain::RecorderState::Speaking
        );
    }

    #[test]
    fn drive_effects_maps_elevation_prompt_decline_to_permission_error() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService { read: None };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::PromptDeclined,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();

        let mut runtime = EffectRuntime::new(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
        );

        runtime.drive_effects(&mut controller, vec![ControllerEffect::PromptForElevation]);

        assert_eq!(
            controller.state.status_message.as_deref(),
            Some("Permission denied: Unknown.")
        );
    }

    #[test]
    fn drive_effects_refreshes_permissions_via_port_service() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService { read: None };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::AlreadyElevated,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus {
                microphone: PermissionState::Denied,
                accessibility: PermissionState::Granted,
                input_monitoring: PermissionState::NotDetermined,
            },
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();

        let mut runtime = EffectRuntime::new(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
        );

        runtime.drive_effects(&mut controller, vec![ControllerEffect::RefreshPermissions]);

        assert_eq!(
            controller.state.permission_status.microphone,
            PermissionState::Denied
        );
        assert_eq!(
            controller.state.permission_status.input_monitoring,
            PermissionState::NotDetermined
        );
    }

    #[test]
    fn drive_effects_handles_request_permission_for_non_microphone_targets() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService { read: None };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::AlreadyElevated,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();

        let mut runtime = EffectRuntime::new(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
        );

        runtime.drive_effects(
            &mut controller,
            vec![ControllerEffect::RequestPermission(
                flo_domain::PermissionKind::Accessibility,
            )],
        );

        assert_eq!(
            permissions.opened_targets,
            vec![PermissionKind::Accessibility]
        );
    }

    #[test]
    fn drive_effects_persists_voice_and_rewrite_preferences() {
        let mut controller = FloController::new();
        controller.state.voice_preferences.voice = "verse".to_string();
        controller.state.voice_preferences.speed = 1.4;
        controller
            .state
            .dictation_rewrite_preferences
            .custom_instructions = "short bullets".to_string();

        let mut selection = FakeSelectionService { read: None };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::AlreadyElevated,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore::default();
        let mut voice_store = FakeVoicePreferencesStore::default();

        let mut runtime = EffectRuntime::new(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
        );

        runtime.drive_effects(
            &mut controller,
            vec![
                ControllerEffect::PersistVoicePreferences,
                ControllerEffect::PersistRewritePreferences,
            ],
        );

        assert_eq!(
            voice_store.saved.as_ref().map(|saved| saved.voice.as_str()),
            Some("verse")
        );
        assert_eq!(
            dictation_store
                .saved
                .as_ref()
                .map(|saved| saved.custom_instructions.as_str()),
            Some("short bullets")
        );
    }

    #[test]
    fn drive_effects_maps_preference_store_failures_to_persistence_error() {
        let mut controller = FloController::new();
        let mut selection = FakeSelectionService { read: None };
        let mut injection = FakeTextInjectionService::default();
        let mut elevation = FakeElevationService {
            outcome: ElevationPromptOutcome::AlreadyElevated,
            fail: false,
        };
        let mut permissions = FakePermissionsService {
            status: PermissionStatus::default(),
            opened_targets: Vec::new(),
        };
        let mut floating = FakeFloatingBarService::default();
        let mut dictation_store = FakeDictationPreferencesStore {
            saved: None,
            fail: true,
        };
        let mut voice_store = FakeVoicePreferencesStore::default();

        let mut runtime = EffectRuntime::new(
            &mut selection,
            &mut injection,
            &mut elevation,
            &mut permissions,
            &mut floating,
            &mut dictation_store,
            &mut voice_store,
        );

        runtime.drive_effects(
            &mut controller,
            vec![ControllerEffect::PersistRewritePreferences],
        );

        assert_eq!(
            controller.state.status_message.as_deref(),
            Some("Persistence error: Unknown")
        );
    }
}
