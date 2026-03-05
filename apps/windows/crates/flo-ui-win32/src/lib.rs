use flo_domain::RecorderState;

#[derive(Debug, Clone, PartialEq)]
pub struct FloatingBarViewModel {
    pub state: RecorderState,
    pub audio_level: f32,
    pub status_text: Option<String>,
}

pub trait Win32Shell: Send {
    fn show_main_window(&mut self);
    fn hide_main_window(&mut self);
    fn update_floating_bar(&mut self, model: &FloatingBarViewModel);
    fn show_tray_notification(&mut self, title: &str, body: &str);
}
