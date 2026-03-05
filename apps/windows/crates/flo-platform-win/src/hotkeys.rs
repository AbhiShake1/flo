use std::collections::{HashMap, HashSet};

use flo_domain::{KeyCombo, ShortcutAction, ShortcutBinding};
use thiserror::Error;

pub type HotkeyResult<T> = Result<T, HotkeyError>;

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum HotkeyError {
    #[error("shortcut conflict on {combo}")]
    Conflict {
        combo: String,
        existing: ShortcutAction,
        incoming: ShortcutAction,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HotkeyRuntimeEvent {
    DictationStarted,
    DictationStopped,
    ReadSelectedTriggered,
    PushToTalkToggled,
}

#[derive(Debug, Default)]
pub struct WindowsHotkeyManager {
    bindings: HashMap<KeyCombo, ShortcutAction>,
    active_holds: HashSet<KeyCombo>,
}

impl WindowsHotkeyManager {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn register_bindings(&mut self, bindings: &[ShortcutBinding]) -> HotkeyResult<()> {
        let mut next = HashMap::new();
        for binding in bindings.iter().filter(|binding| binding.enabled) {
            if let Some(existing) = next.get(&binding.combo) {
                if existing != &binding.action {
                    return Err(HotkeyError::Conflict {
                        combo: binding.combo.human_readable(),
                        existing: *existing,
                        incoming: binding.action,
                    });
                }
            }
            next.insert(binding.combo.clone(), binding.action);
        }

        self.bindings = next;
        self.active_holds.clear();
        Ok(())
    }

    pub fn binding_count(&self) -> usize {
        self.bindings.len()
    }

    pub fn handle_key_down(&mut self, combo: &KeyCombo) -> Vec<HotkeyRuntimeEvent> {
        let Some(action) = self.bindings.get(combo) else {
            return Vec::new();
        };

        match action {
            ShortcutAction::DictationHold => {
                if !self.active_holds.insert(combo.clone()) {
                    return Vec::new();
                }
                vec![HotkeyRuntimeEvent::DictationStarted]
            }
            ShortcutAction::ReadSelectedText => vec![HotkeyRuntimeEvent::ReadSelectedTriggered],
            ShortcutAction::PushToTalkToggle => vec![HotkeyRuntimeEvent::PushToTalkToggled],
        }
    }

    pub fn handle_key_up(&mut self, combo: &KeyCombo) -> Vec<HotkeyRuntimeEvent> {
        let Some(action) = self.bindings.get(combo) else {
            return Vec::new();
        };

        if *action == ShortcutAction::DictationHold && self.active_holds.remove(combo) {
            return vec![HotkeyRuntimeEvent::DictationStopped];
        }

        Vec::new()
    }
}

#[cfg(test)]
mod tests {
    use flo_domain::{LogicalKey, ShortcutModifiers};

    use super::*;

    fn combo(key: char) -> KeyCombo {
        KeyCombo {
            key: LogicalKey::Character(key),
            modifiers: ShortcutModifiers {
                ctrl: true,
                ..ShortcutModifiers::default()
            },
            key_display: key.to_ascii_uppercase().to_string(),
        }
    }

    fn binding(action: ShortcutAction, key: char, enabled: bool) -> ShortcutBinding {
        ShortcutBinding {
            action,
            combo: combo(key),
            enabled,
        }
    }

    #[test]
    fn rejects_conflicting_bindings() {
        let mut manager = WindowsHotkeyManager::new();
        let err = manager
            .register_bindings(&[
                binding(ShortcutAction::DictationHold, 'd', true),
                binding(ShortcutAction::ReadSelectedText, 'd', true),
            ])
            .expect_err("conflicting combo should fail registration");

        assert!(matches!(err, HotkeyError::Conflict { .. }));
    }

    #[test]
    fn hold_shortcut_emits_start_and_stop_once_per_press() {
        let mut manager = WindowsHotkeyManager::new();
        manager
            .register_bindings(&[binding(ShortcutAction::DictationHold, 'd', true)])
            .expect("registration should succeed");
        let key = combo('d');

        assert_eq!(
            manager.handle_key_down(&key),
            vec![HotkeyRuntimeEvent::DictationStarted]
        );
        assert!(manager.handle_key_down(&key).is_empty());
        assert_eq!(
            manager.handle_key_up(&key),
            vec![HotkeyRuntimeEvent::DictationStopped]
        );
        assert!(manager.handle_key_up(&key).is_empty());
    }

    #[test]
    fn read_selected_triggers_on_key_down() {
        let mut manager = WindowsHotkeyManager::new();
        manager
            .register_bindings(&[binding(ShortcutAction::ReadSelectedText, 'r', true)])
            .expect("registration should succeed");
        let key = combo('r');

        assert_eq!(
            manager.handle_key_down(&key),
            vec![HotkeyRuntimeEvent::ReadSelectedTriggered]
        );
        assert!(manager.handle_key_up(&key).is_empty());
    }

    #[test]
    fn disabled_bindings_are_ignored() {
        let mut manager = WindowsHotkeyManager::new();
        manager
            .register_bindings(&[binding(ShortcutAction::ReadSelectedText, 'r', false)])
            .expect("registration should succeed");

        assert_eq!(manager.binding_count(), 0);
        assert!(manager.handle_key_down(&combo('r')).is_empty());
    }

    #[test]
    fn push_to_talk_toggle_emits_toggle_event() {
        let mut manager = WindowsHotkeyManager::new();
        manager
            .register_bindings(&[binding(ShortcutAction::PushToTalkToggle, 't', true)])
            .expect("registration should succeed");

        assert_eq!(
            manager.handle_key_down(&combo('t')),
            vec![HotkeyRuntimeEvent::PushToTalkToggled]
        );
    }
}
