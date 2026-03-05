use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum LogicalKey {
    Character(char),
    Enter,
    Tab,
    Space,
    Escape,
    Backspace,
    Delete,
    ArrowUp,
    ArrowDown,
    ArrowLeft,
    ArrowRight,
    Function(u8),
    Unknown(u32),
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ShortcutModifiers {
    pub ctrl: bool,
    pub alt: bool,
    pub shift: bool,
    pub meta: bool,
}

impl ShortcutModifiers {
    pub fn human_readable(self) -> String {
        let mut out = String::new();
        if self.ctrl {
            out.push_str("Ctrl+");
        }
        if self.alt {
            out.push_str("Alt+");
        }
        if self.shift {
            out.push_str("Shift+");
        }
        if self.meta {
            out.push_str("Win+");
        }
        out
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KeyCombo {
    pub key: LogicalKey,
    pub modifiers: ShortcutModifiers,
    pub key_display: String,
}

impl KeyCombo {
    pub fn human_readable(&self) -> String {
        format!("{}{}", self.modifiers.human_readable(), self.key_display)
    }
}
