use flo_domain::FloatingBarState;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChipBannerTone {
    Success,
    Warning,
    Error,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChipBannerViewModel {
    pub message: String,
    pub tone: ChipBannerTone,
}

#[derive(Debug, Clone, PartialEq)]
pub struct FloatingBarViewModel {
    pub state: FloatingBarState,
    pub transcript_preview: Option<String>,
    pub level_meter: f32,
    pub hint_text: Option<String>,
    pub busy: bool,
    pub show_read_affordance: bool,
    pub banner: Option<ChipBannerViewModel>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ChipGeometry {
    pub left_width_px: i32,
    pub left_height_px: i32,
    pub right_width_px: i32,
    pub right_height_px: i32,
    pub section_gap_px: i32,
    pub bottom_inset_px: i32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BannerGeometry {
    pub min_width_px: i32,
    pub max_width_px: i32,
    pub min_height_px: i32,
    pub corner_radius_px: i32,
    pub horizontal_padding_px: i32,
    pub vertical_padding_px: i32,
    pub dismiss_size_px: i32,
    pub dismiss_trailing_padding_px: i32,
    pub text_spacing_px: i32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MotionTokens {
    pub success_banner_auto_dismiss_ms: u64,
    pub error_banner_auto_dismiss_ms: u64,
    pub selection_poll_ms: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ChipInteractionModel {
    pub dictation_enabled: bool,
    pub read_enabled: bool,
}

pub trait Win32Shell: Send {
    fn show_main_window(&mut self);
    fn hide_main_window(&mut self);
    fn update_floating_bar(&mut self, model: &FloatingBarViewModel);
    fn show_tray_notification(&mut self, title: &str, body: &str);
}

pub fn chip_geometry_for_state(state: FloatingBarState, dpi_scale: f32) -> ChipGeometry {
    let (right_width, right_height) = match state {
        FloatingBarState::Speaking => (60.0, 18.0),
        _ => (20.0, 9.0),
    };

    ChipGeometry {
        left_width_px: scale(37.0, dpi_scale),
        left_height_px: scale(9.0, dpi_scale),
        right_width_px: scale(right_width, dpi_scale),
        right_height_px: scale(right_height, dpi_scale),
        section_gap_px: scale(2.0, dpi_scale),
        bottom_inset_px: scale(14.0, dpi_scale),
    }
}

pub fn banner_geometry(dpi_scale: f32) -> BannerGeometry {
    BannerGeometry {
        min_width_px: scale(300.0, dpi_scale),
        max_width_px: scale(560.0, dpi_scale),
        min_height_px: scale(48.0, dpi_scale),
        corner_radius_px: scale(12.0, dpi_scale),
        horizontal_padding_px: scale(12.0, dpi_scale),
        vertical_padding_px: scale(10.0, dpi_scale),
        dismiss_size_px: scale(20.0, dpi_scale),
        dismiss_trailing_padding_px: scale(10.0, dpi_scale),
        text_spacing_px: scale(10.0, dpi_scale),
    }
}

pub const fn motion_tokens() -> MotionTokens {
    MotionTokens {
        success_banner_auto_dismiss_ms: 2_200,
        error_banner_auto_dismiss_ms: 2_800,
        selection_poll_ms: 350,
    }
}

pub fn read_affordance_alpha(has_selected_text: bool) -> f32 {
    if has_selected_text {
        1.0
    } else {
        0.68
    }
}

pub fn hint_text_for_state(state: FloatingBarState, has_selected_text: bool) -> &'static str {
    match state {
        FloatingBarState::Speaking => "Click to stop narration.",
        _ if has_selected_text => "Read selected text aloud.",
        _ => "Click to try narrating selected text.",
    }
}

pub fn interaction_model(
    state: FloatingBarState,
    banner_visible: bool,
    has_selected_text: bool,
) -> ChipInteractionModel {
    if banner_visible && state == FloatingBarState::Error {
        return ChipInteractionModel {
            dictation_enabled: false,
            read_enabled: false,
        };
    }

    match state {
        FloatingBarState::Hidden | FloatingBarState::IdleReady => ChipInteractionModel {
            dictation_enabled: true,
            read_enabled: has_selected_text,
        },
        FloatingBarState::Listening => ChipInteractionModel {
            dictation_enabled: true,
            read_enabled: false,
        },
        FloatingBarState::Transcribing | FloatingBarState::Injecting => ChipInteractionModel {
            dictation_enabled: false,
            read_enabled: false,
        },
        FloatingBarState::Speaking => ChipInteractionModel {
            dictation_enabled: false,
            read_enabled: true,
        },
        FloatingBarState::Error => ChipInteractionModel {
            dictation_enabled: true,
            read_enabled: has_selected_text,
        },
    }
}

fn scale(value: f32, dpi_scale: f32) -> i32 {
    (value * dpi_scale).round() as i32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn idle_geometry_matches_tokens_at_standard_dpi() {
        let geometry = chip_geometry_for_state(FloatingBarState::IdleReady, 1.0);
        assert_eq!(
            geometry,
            ChipGeometry {
                left_width_px: 37,
                left_height_px: 9,
                right_width_px: 20,
                right_height_px: 9,
                section_gap_px: 2,
                bottom_inset_px: 14,
            }
        );
    }

    #[test]
    fn speaking_geometry_expands_right_segment() {
        let geometry = chip_geometry_for_state(FloatingBarState::Speaking, 1.0);
        assert_eq!(geometry.right_width_px, 60);
        assert_eq!(geometry.right_height_px, 18);
    }

    #[test]
    fn geometry_scales_for_125_and_150_dpi() {
        let g125 = chip_geometry_for_state(FloatingBarState::IdleReady, 1.25);
        let g150 = chip_geometry_for_state(FloatingBarState::IdleReady, 1.5);

        assert_eq!(g125.left_width_px, 46);
        assert_eq!(g125.bottom_inset_px, 18);

        assert_eq!(g150.left_width_px, 56);
        assert_eq!(g150.bottom_inset_px, 21);
    }

    #[test]
    fn banner_geometry_scales_consistently() {
        let banner = banner_geometry(1.5);
        assert_eq!(banner.min_width_px, 450);
        assert_eq!(banner.max_width_px, 840);
        assert_eq!(banner.min_height_px, 72);
        assert_eq!(banner.corner_radius_px, 18);
    }

    #[test]
    fn interaction_matrix_matches_state_contract() {
        assert_eq!(
            interaction_model(FloatingBarState::IdleReady, false, true),
            ChipInteractionModel {
                dictation_enabled: true,
                read_enabled: true,
            }
        );

        assert_eq!(
            interaction_model(FloatingBarState::Listening, false, true),
            ChipInteractionModel {
                dictation_enabled: true,
                read_enabled: false,
            }
        );

        assert_eq!(
            interaction_model(FloatingBarState::Transcribing, false, true),
            ChipInteractionModel {
                dictation_enabled: false,
                read_enabled: false,
            }
        );

        assert_eq!(
            interaction_model(FloatingBarState::Speaking, false, false),
            ChipInteractionModel {
                dictation_enabled: false,
                read_enabled: true,
            }
        );

        assert_eq!(
            interaction_model(FloatingBarState::Error, true, true),
            ChipInteractionModel {
                dictation_enabled: false,
                read_enabled: false,
            }
        );
    }

    #[test]
    fn hint_text_and_alpha_match_expected_behavior() {
        assert_eq!(
            hint_text_for_state(FloatingBarState::IdleReady, true),
            "Read selected text aloud."
        );
        assert_eq!(
            hint_text_for_state(FloatingBarState::IdleReady, false),
            "Click to try narrating selected text."
        );
        assert_eq!(
            hint_text_for_state(FloatingBarState::Speaking, false),
            "Click to stop narration."
        );

        assert_eq!(read_affordance_alpha(true), 1.0);
        assert_eq!(read_affordance_alpha(false), 0.68);
    }

    #[test]
    fn motion_tokens_match_parity_spec() {
        let motion = motion_tokens();
        assert_eq!(motion.success_banner_auto_dismiss_ms, 2_200);
        assert_eq!(motion.error_banner_auto_dismiss_ms, 2_800);
        assert_eq!(motion.selection_poll_ms, 350);
    }
}
