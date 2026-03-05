use flo_domain::FloatingBarState;

#[derive(Debug, Clone, PartialEq, Eq)]
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

pub trait Win32Shell: Send {
    fn show_main_window(&mut self);
    fn hide_main_window(&mut self);
    fn update_floating_bar(&mut self, model: &FloatingBarViewModel);
    fn show_tray_notification(&mut self, title: &str, body: &str);
}
