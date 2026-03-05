#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PlatformCapabilities {
    pub elevated_mode: bool,
    pub can_prompt_for_elevation: bool,
    pub target_requires_elevation: bool,
    pub uia_available: bool,
    pub clipboard_fallback_available: bool,
    pub injection_supported: bool,
    pub secure_field_detection: bool,
}

impl PlatformCapabilities {
    pub fn win32_default() -> Self {
        Self {
            elevated_mode: false,
            can_prompt_for_elevation: true,
            target_requires_elevation: false,
            uia_available: true,
            clipboard_fallback_available: true,
            injection_supported: true,
            secure_field_detection: true,
        }
    }
}
