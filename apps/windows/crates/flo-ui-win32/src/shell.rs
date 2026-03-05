use flo_domain::{PermissionState, PermissionStatus};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SettingsRoute {
    General,
    Dictation,
    Providers,
    History,
    Permissions,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OnboardingStage {
    Welcome,
    Login,
    Permissions,
    Hotkeys,
    Complete,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShellSurface {
    TrayOnly,
    Onboarding(OnboardingStage),
    Settings(SettingsRoute),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrayCommand {
    OpenSettings,
    OpenHistory,
    OpenProviderWorkbench,
    StartDictation,
    ReadSelected,
    Quit,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShellIntent {
    ShowOnboarding(OnboardingStage),
    ShowSettings(SettingsRoute),
    StartDictation,
    ReadSelected,
    QuitApp,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ShellLayoutTokens {
    pub settings_min_width_px: i32,
    pub settings_min_height_px: i32,
    pub tray_row_height_px: i32,
    pub section_gap_px: i32,
    pub horizontal_padding_px: i32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ShellAccessibilityLabels {
    pub tray_icon_name: &'static str,
    pub settings_window_name: &'static str,
    pub onboarding_window_name: &'static str,
    pub history_tab_name: &'static str,
    pub provider_tab_name: &'static str,
    pub permissions_tab_name: &'static str,
}

pub const fn shell_accessibility_labels() -> ShellAccessibilityLabels {
    ShellAccessibilityLabels {
        tray_icon_name: "Flo tray icon",
        settings_window_name: "Flo Settings",
        onboarding_window_name: "Flo Onboarding",
        history_tab_name: "History",
        provider_tab_name: "Provider Workbench",
        permissions_tab_name: "Permissions",
    }
}

pub fn shell_layout_tokens(dpi_scale: f32) -> ShellLayoutTokens {
    ShellLayoutTokens {
        settings_min_width_px: scale(960.0, dpi_scale),
        settings_min_height_px: scale(640.0, dpi_scale),
        tray_row_height_px: scale(30.0, dpi_scale),
        section_gap_px: scale(10.0, dpi_scale),
        horizontal_padding_px: scale(12.0, dpi_scale),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Win32ShellState {
    pub surface: ShellSurface,
    pub onboarding_stage: OnboardingStage,
    pub permission_status: PermissionStatus,
    pub last_settings_route: SettingsRoute,
}

impl Win32ShellState {
    pub fn new(permission_status: PermissionStatus) -> Self {
        let requires_permissions = has_missing_required_permissions(permission_status);
        Self {
            surface: if requires_permissions {
                ShellSurface::Onboarding(OnboardingStage::Welcome)
            } else {
                ShellSurface::TrayOnly
            },
            onboarding_stage: OnboardingStage::Welcome,
            permission_status,
            last_settings_route: SettingsRoute::General,
        }
    }

    pub fn update_permissions(&mut self, status: PermissionStatus) {
        self.permission_status = status;
        if self.onboarding_stage == OnboardingStage::Permissions
            && !has_missing_required_permissions(self.permission_status)
        {
            self.onboarding_stage = OnboardingStage::Hotkeys;
            self.surface = ShellSurface::Onboarding(OnboardingStage::Hotkeys);
        }
    }

    pub fn advance_onboarding(&mut self) -> ShellIntent {
        self.onboarding_stage = match self.onboarding_stage {
            OnboardingStage::Welcome => OnboardingStage::Login,
            OnboardingStage::Login => {
                if has_missing_required_permissions(self.permission_status) {
                    OnboardingStage::Permissions
                } else {
                    OnboardingStage::Hotkeys
                }
            }
            OnboardingStage::Permissions => {
                if has_missing_required_permissions(self.permission_status) {
                    OnboardingStage::Permissions
                } else {
                    OnboardingStage::Hotkeys
                }
            }
            OnboardingStage::Hotkeys => OnboardingStage::Complete,
            OnboardingStage::Complete => OnboardingStage::Complete,
        };

        if self.onboarding_stage == OnboardingStage::Complete {
            self.surface = ShellSurface::Settings(SettingsRoute::General);
            self.last_settings_route = SettingsRoute::General;
            ShellIntent::ShowSettings(SettingsRoute::General)
        } else {
            self.surface = ShellSurface::Onboarding(self.onboarding_stage);
            ShellIntent::ShowOnboarding(self.onboarding_stage)
        }
    }

    pub fn open_settings_route(&mut self, route: SettingsRoute) -> ShellIntent {
        if has_missing_required_permissions(self.permission_status) {
            self.onboarding_stage = OnboardingStage::Permissions;
            self.surface = ShellSurface::Onboarding(OnboardingStage::Permissions);
            return ShellIntent::ShowOnboarding(OnboardingStage::Permissions);
        }

        self.surface = ShellSurface::Settings(route);
        self.last_settings_route = route;
        ShellIntent::ShowSettings(route)
    }

    pub fn handle_tray_command(&mut self, command: TrayCommand) -> Vec<ShellIntent> {
        match command {
            TrayCommand::OpenSettings => vec![self.open_settings_route(SettingsRoute::General)],
            TrayCommand::OpenHistory => vec![self.open_settings_route(SettingsRoute::History)],
            TrayCommand::OpenProviderWorkbench => {
                vec![self.open_settings_route(SettingsRoute::Providers)]
            }
            TrayCommand::StartDictation => vec![ShellIntent::StartDictation],
            TrayCommand::ReadSelected => vec![ShellIntent::ReadSelected],
            TrayCommand::Quit => vec![ShellIntent::QuitApp],
        }
    }
}

pub fn has_missing_required_permissions(status: PermissionStatus) -> bool {
    status.microphone != PermissionState::Granted
        || status.accessibility != PermissionState::Granted
        || status.input_monitoring != PermissionState::Granted
}

fn scale(value: f32, dpi_scale: f32) -> i32 {
    (value * dpi_scale).round() as i32
}

#[cfg(test)]
mod tests {
    use super::*;

    fn granted_permissions() -> PermissionStatus {
        PermissionStatus {
            microphone: PermissionState::Granted,
            accessibility: PermissionState::Granted,
            input_monitoring: PermissionState::Granted,
        }
    }

    #[test]
    fn missing_permissions_force_onboarding_gate_from_tray() {
        let mut shell = Win32ShellState::new(PermissionStatus::default());

        let intents = shell.handle_tray_command(TrayCommand::OpenHistory);
        assert_eq!(
            intents,
            vec![ShellIntent::ShowOnboarding(OnboardingStage::Permissions)]
        );
        assert_eq!(
            shell.surface,
            ShellSurface::Onboarding(OnboardingStage::Permissions)
        );
    }

    #[test]
    fn onboarding_advances_to_hotkeys_after_permissions_are_granted() {
        let mut shell = Win32ShellState::new(PermissionStatus::default());
        assert_eq!(
            shell.advance_onboarding(),
            ShellIntent::ShowOnboarding(OnboardingStage::Login)
        );
        assert_eq!(
            shell.advance_onboarding(),
            ShellIntent::ShowOnboarding(OnboardingStage::Permissions)
        );

        shell.update_permissions(granted_permissions());
        assert_eq!(
            shell.surface,
            ShellSurface::Onboarding(OnboardingStage::Hotkeys)
        );
    }

    #[test]
    fn tray_commands_route_to_expected_settings_tabs_after_onboarding_gate() {
        let mut shell = Win32ShellState::new(granted_permissions());

        assert_eq!(
            shell.handle_tray_command(TrayCommand::OpenProviderWorkbench),
            vec![ShellIntent::ShowSettings(SettingsRoute::Providers)]
        );
        assert_eq!(
            shell.surface,
            ShellSurface::Settings(SettingsRoute::Providers)
        );

        assert_eq!(
            shell.handle_tray_command(TrayCommand::OpenHistory),
            vec![ShellIntent::ShowSettings(SettingsRoute::History)]
        );
        assert_eq!(
            shell.surface,
            ShellSurface::Settings(SettingsRoute::History)
        );
    }

    #[test]
    fn layout_tokens_scale_for_100_125_150_dpi() {
        let at_100 = shell_layout_tokens(1.0);
        let at_125 = shell_layout_tokens(1.25);
        let at_150 = shell_layout_tokens(1.5);

        assert_eq!(at_100.settings_min_width_px, 960);
        assert_eq!(at_125.settings_min_width_px, 1200);
        assert_eq!(at_150.settings_min_width_px, 1440);

        assert_eq!(at_100.tray_row_height_px, 30);
        assert_eq!(at_125.tray_row_height_px, 38);
        assert_eq!(at_150.tray_row_height_px, 45);
    }

    #[test]
    fn accessibility_labels_are_stable_and_non_empty() {
        let labels = shell_accessibility_labels();
        assert!(!labels.tray_icon_name.is_empty());
        assert!(!labels.settings_window_name.is_empty());
        assert!(!labels.onboarding_window_name.is_empty());
        assert!(!labels.history_tab_name.is_empty());
        assert!(!labels.provider_tab_name.is_empty());
        assert!(!labels.permissions_tab_name.is_empty());
    }
}
