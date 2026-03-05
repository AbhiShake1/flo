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
pub struct SettingsLayoutTokens {
    pub sidebar_width_px: i32,
    pub content_horizontal_padding_px: i32,
    pub content_vertical_padding_px: i32,
    pub section_header_height_px: i32,
    pub control_height_px: i32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OnboardingLayoutTokens {
    pub stage_width_px: i32,
    pub stage_min_height_px: i32,
    pub card_corner_radius_px: i32,
    pub stage_gap_px: i32,
    pub primary_button_height_px: i32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct HistoryProviderLayoutTokens {
    pub row_height_px: i32,
    pub header_height_px: i32,
    pub icon_size_px: i32,
    pub notice_min_height_px: i32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ShellMotionTokens {
    pub onboarding_stage_transition_ms: u64,
    pub settings_route_transition_ms: u64,
    pub tray_menu_open_ms: u64,
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

pub fn settings_layout_tokens(dpi_scale: f32) -> SettingsLayoutTokens {
    SettingsLayoutTokens {
        sidebar_width_px: scale(228.0, dpi_scale),
        content_horizontal_padding_px: scale(20.0, dpi_scale),
        content_vertical_padding_px: scale(18.0, dpi_scale),
        section_header_height_px: scale(34.0, dpi_scale),
        control_height_px: scale(32.0, dpi_scale),
    }
}

pub fn onboarding_layout_tokens(dpi_scale: f32) -> OnboardingLayoutTokens {
    OnboardingLayoutTokens {
        stage_width_px: scale(860.0, dpi_scale),
        stage_min_height_px: scale(560.0, dpi_scale),
        card_corner_radius_px: scale(16.0, dpi_scale),
        stage_gap_px: scale(18.0, dpi_scale),
        primary_button_height_px: scale(40.0, dpi_scale),
    }
}

pub fn history_provider_layout_tokens(dpi_scale: f32) -> HistoryProviderLayoutTokens {
    HistoryProviderLayoutTokens {
        row_height_px: scale(34.0, dpi_scale),
        header_height_px: scale(36.0, dpi_scale),
        icon_size_px: scale(18.0, dpi_scale),
        notice_min_height_px: scale(52.0, dpi_scale),
    }
}

pub const fn shell_motion_tokens() -> ShellMotionTokens {
    ShellMotionTokens {
        onboarding_stage_transition_ms: 220,
        settings_route_transition_ms: 180,
        tray_menu_open_ms: 120,
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
    fn settings_and_onboarding_tokens_scale_consistently() {
        let settings_100 = settings_layout_tokens(1.0);
        let settings_125 = settings_layout_tokens(1.25);
        let onboarding_100 = onboarding_layout_tokens(1.0);
        let onboarding_150 = onboarding_layout_tokens(1.5);

        assert_eq!(settings_100.sidebar_width_px, 228);
        assert_eq!(settings_125.sidebar_width_px, 285);
        assert_eq!(settings_100.control_height_px, 32);
        assert_eq!(settings_125.control_height_px, 40);

        assert_eq!(onboarding_100.stage_width_px, 860);
        assert_eq!(onboarding_150.stage_width_px, 1290);
        assert_eq!(onboarding_100.primary_button_height_px, 40);
        assert_eq!(onboarding_150.primary_button_height_px, 60);
    }

    #[test]
    fn history_provider_tokens_scale_consistently() {
        let at_100 = history_provider_layout_tokens(1.0);
        let at_125 = history_provider_layout_tokens(1.25);

        assert_eq!(at_100.row_height_px, 34);
        assert_eq!(at_125.row_height_px, 43);
        assert_eq!(at_100.notice_min_height_px, 52);
        assert_eq!(at_125.notice_min_height_px, 65);
    }

    #[test]
    fn shell_motion_tokens_match_ui_spec_contract() {
        let motion = shell_motion_tokens();
        assert_eq!(motion.onboarding_stage_transition_ms, 220);
        assert_eq!(motion.settings_route_transition_ms, 180);
        assert_eq!(motion.tray_menu_open_ms, 120);
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
