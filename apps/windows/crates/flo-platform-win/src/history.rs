use std::{
    fs,
    path::PathBuf,
    time::{SystemTime, UNIX_EPOCH},
};

use flo_domain::HistoryEntry;
use getrandom::getrandom;
use thiserror::Error;

use crate::security::{DpapiCipher, SecretStore, SecretStoreError};

const HISTORY_FILE_MAGIC: &[u8] = b"FLOHIST1";
const HISTORY_KEY_SERVICE: &str = "flo.history";
const HISTORY_KEY_ACCOUNT: &str = "history-encryption-key";
const HISTORY_KEY_DPAPI_ENTROPY: &[u8] = b"flo.history.dpapi.key.v1";
const HISTORY_DATA_DPAPI_ENTROPY: &[u8] = b"flo.history.dpapi.data.v1";
const DEFAULT_RETENTION_CAP: usize = 500;

pub type HistoryResult<T> = Result<T, HistoryStoreError>;

#[derive(Debug, Error)]
pub enum HistoryStoreError {
    #[error("security error: {0}")]
    Security(#[from] SecretStoreError),
    #[error("io error: {0}")]
    Io(String),
    #[error("serialization error: {0}")]
    Serialization(String),
    #[error("randomness error: {0}")]
    Randomness(String),
}

pub struct EncryptedHistoryStore<S, C>
where
    S: SecretStore,
    C: DpapiCipher,
{
    history_path: PathBuf,
    secret_store: S,
    cipher: C,
    retention_cap: usize,
    key_service: String,
    key_account: String,
}

impl<S, C> EncryptedHistoryStore<S, C>
where
    S: SecretStore,
    C: DpapiCipher,
{
    pub fn new(history_path: PathBuf, secret_store: S, cipher: C) -> Self {
        Self {
            history_path,
            secret_store,
            cipher,
            retention_cap: DEFAULT_RETENTION_CAP,
            key_service: HISTORY_KEY_SERVICE.to_string(),
            key_account: HISTORY_KEY_ACCOUNT.to_string(),
        }
    }

    pub fn with_retention_cap(mut self, retention_cap: usize) -> Self {
        self.retention_cap = retention_cap;
        self
    }

    pub fn load_entries(&self) -> HistoryResult<Vec<HistoryEntry>> {
        if !self.history_path.exists() {
            return Ok(Vec::new());
        }

        let bytes =
            fs::read(&self.history_path).map_err(|err| HistoryStoreError::Io(err.to_string()))?;
        if bytes.is_empty() {
            return Ok(Vec::new());
        }

        let decrypted = match self.decrypt_payload(&bytes) {
            Ok(payload) => payload,
            Err(_) => {
                self.quarantine_corrupt_history_file()?;
                return Ok(Vec::new());
            }
        };

        let mut entries: Vec<HistoryEntry> = match serde_json::from_slice(&decrypted) {
            Ok(entries) => entries,
            Err(_) => {
                self.quarantine_corrupt_history_file()?;
                return Ok(Vec::new());
            }
        };

        self.apply_retention_cap(&mut entries);
        Ok(entries)
    }

    pub fn append_entry(&self, entry: HistoryEntry) -> HistoryResult<Vec<HistoryEntry>> {
        let mut entries = self.load_entries()?;
        entries.push(entry);
        self.save_entries(&entries)?;
        self.load_entries()
    }

    pub fn save_entries(&self, entries: &[HistoryEntry]) -> HistoryResult<()> {
        let mut bounded = entries.to_vec();
        self.apply_retention_cap(&mut bounded);

        let plaintext = serde_json::to_vec(&bounded)
            .map_err(|err| HistoryStoreError::Serialization(err.to_string()))?;
        let ciphertext = self.encrypt_payload(&plaintext)?;

        if let Some(parent) = self.history_path.parent() {
            fs::create_dir_all(parent).map_err(|err| HistoryStoreError::Io(err.to_string()))?;
        }

        let mut encoded = Vec::with_capacity(HISTORY_FILE_MAGIC.len() + ciphertext.len());
        encoded.extend_from_slice(HISTORY_FILE_MAGIC);
        encoded.extend_from_slice(&ciphertext);

        let temp_path = self.temp_path();
        fs::write(&temp_path, &encoded).map_err(|err| HistoryStoreError::Io(err.to_string()))?;
        fs::rename(&temp_path, &self.history_path)
            .map_err(|err| HistoryStoreError::Io(err.to_string()))?;

        Ok(())
    }

    pub fn clear_history(&self) -> HistoryResult<()> {
        if self.history_path.exists() {
            fs::remove_file(&self.history_path)
                .map_err(|err| HistoryStoreError::Io(err.to_string()))?;
        }

        self.secret_store
            .delete_secret(&self.key_service, &self.key_account)?;

        Ok(())
    }

    fn encrypt_payload(&self, plaintext: &[u8]) -> HistoryResult<Vec<u8>> {
        let key = self.load_or_create_history_key()?;
        let mut entropy = Vec::with_capacity(HISTORY_DATA_DPAPI_ENTROPY.len() + key.len());
        entropy.extend_from_slice(HISTORY_DATA_DPAPI_ENTROPY);
        entropy.extend_from_slice(&key);
        self.cipher
            .protect(plaintext, Some(&entropy))
            .map_err(HistoryStoreError::from)
    }

    fn decrypt_payload(&self, encoded: &[u8]) -> HistoryResult<Vec<u8>> {
        if !encoded.starts_with(HISTORY_FILE_MAGIC) {
            return Err(HistoryStoreError::Serialization(
                "history payload missing magic header".to_string(),
            ));
        }

        let ciphertext = &encoded[HISTORY_FILE_MAGIC.len()..];
        let key = self.load_or_create_history_key()?;
        let mut entropy = Vec::with_capacity(HISTORY_DATA_DPAPI_ENTROPY.len() + key.len());
        entropy.extend_from_slice(HISTORY_DATA_DPAPI_ENTROPY);
        entropy.extend_from_slice(&key);

        self.cipher
            .unprotect(ciphertext, Some(&entropy))
            .map_err(HistoryStoreError::from)
    }

    fn load_or_create_history_key(&self) -> HistoryResult<Vec<u8>> {
        match self
            .secret_store
            .read_secret(&self.key_service, &self.key_account)?
        {
            Some(protected_key) => {
                match self
                    .cipher
                    .unprotect(&protected_key, Some(HISTORY_KEY_DPAPI_ENTROPY))
                {
                    Ok(key) if !key.is_empty() => Ok(key),
                    _ => {
                        // Corrupted or invalid key payload. Reset key material and continue.
                        self.secret_store
                            .delete_secret(&self.key_service, &self.key_account)?;
                        self.generate_and_store_history_key()
                    }
                }
            }
            None => self.generate_and_store_history_key(),
        }
    }

    fn generate_and_store_history_key(&self) -> HistoryResult<Vec<u8>> {
        let mut key = vec![0_u8; 32];
        getrandom(&mut key).map_err(|err| HistoryStoreError::Randomness(err.to_string()))?;

        let protected = self.cipher.protect(&key, Some(HISTORY_KEY_DPAPI_ENTROPY))?;
        self.secret_store
            .write_secret(&self.key_service, &self.key_account, &protected)?;

        Ok(key)
    }

    fn apply_retention_cap(&self, entries: &mut Vec<HistoryEntry>) {
        if self.retention_cap == 0 {
            entries.clear();
            return;
        }

        if entries.len() > self.retention_cap {
            let drop_count = entries.len() - self.retention_cap;
            entries.drain(0..drop_count);
        }
    }

    fn temp_path(&self) -> PathBuf {
        let file_name = self
            .history_path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("history.json");
        self.history_path.with_file_name(format!("{file_name}.tmp"))
    }

    fn quarantine_corrupt_history_file(&self) -> HistoryResult<()> {
        if !self.history_path.exists() {
            return Ok(());
        }

        let file_name = self
            .history_path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("history.json");
        let ts = now_unix_ms();
        let quarantine_path = self
            .history_path
            .with_file_name(format!("{file_name}.corrupt-{ts}"));

        match fs::rename(&self.history_path, &quarantine_path) {
            Ok(()) => Ok(()),
            Err(_) => fs::remove_file(&self.history_path)
                .map_err(|err| HistoryStoreError::Io(err.to_string())),
        }
    }
}

fn now_unix_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use std::{
        collections::HashMap,
        path::PathBuf,
        sync::{Arc, Mutex},
    };

    use flo_domain::HistoryEventKind;

    use super::*;
    use crate::security::SecretResult;

    #[derive(Clone, Default)]
    struct InMemorySecretStore {
        map: Arc<Mutex<HashMap<(String, String), Vec<u8>>>>,
    }

    impl InMemorySecretStore {
        fn write_raw(&self, service: &str, account: &str, value: Vec<u8>) {
            self.map
                .lock()
                .expect("lock secret store")
                .insert((service.to_string(), account.to_string()), value);
        }

        fn read_raw(&self, service: &str, account: &str) -> Option<Vec<u8>> {
            self.map
                .lock()
                .expect("lock secret store")
                .get(&(service.to_string(), account.to_string()))
                .cloned()
        }
    }

    impl SecretStore for InMemorySecretStore {
        fn read_secret(&self, service: &str, account: &str) -> SecretResult<Option<Vec<u8>>> {
            Ok(self
                .map
                .lock()
                .expect("lock secret store")
                .get(&(service.to_string(), account.to_string()))
                .cloned())
        }

        fn write_secret(&self, service: &str, account: &str, value: &[u8]) -> SecretResult<()> {
            self.map
                .lock()
                .expect("lock secret store")
                .insert((service.to_string(), account.to_string()), value.to_vec());
            Ok(())
        }

        fn delete_secret(&self, service: &str, account: &str) -> SecretResult<()> {
            self.map
                .lock()
                .expect("lock secret store")
                .remove(&(service.to_string(), account.to_string()));
            Ok(())
        }
    }

    #[derive(Clone, Default)]
    struct PrefixCipher;

    impl DpapiCipher for PrefixCipher {
        fn protect(&self, plaintext: &[u8], _entropy: Option<&[u8]>) -> SecretResult<Vec<u8>> {
            let mut out = b"enc:".to_vec();
            out.extend_from_slice(plaintext);
            Ok(out)
        }

        fn unprotect(&self, ciphertext: &[u8], _entropy: Option<&[u8]>) -> SecretResult<Vec<u8>> {
            if !ciphertext.starts_with(b"enc:") {
                return Err(SecretStoreError::Serialization(
                    "invalid encrypted payload".to_string(),
                ));
            }
            Ok(ciphertext[b"enc:".len()..].to_vec())
        }
    }

    fn temp_history_path(test_name: &str) -> PathBuf {
        let mut path = std::env::temp_dir();
        path.push(format!("flo-platform-win-{test_name}-{}", now_unix_ms()));
        path.push("history.enc");
        path
    }

    fn sample_entry(id: &str, ts: i64) -> HistoryEntry {
        HistoryEntry {
            id: id.to_string(),
            timestamp_unix_ms: ts,
            kind: HistoryEventKind::Dictation,
            input_text: format!("input-{id}"),
            output_text: Some(format!("output-{id}")),
            request_id: None,
            latency_ms: Some(120),
            success: true,
            error_message: None,
        }
    }

    #[test]
    fn append_and_load_roundtrip_applies_retention_cap() {
        let path = temp_history_path("retention");
        let store = InMemorySecretStore::default();
        let history =
            EncryptedHistoryStore::new(path.clone(), store, PrefixCipher).with_retention_cap(2);

        history
            .append_entry(sample_entry("1", 1))
            .expect("append 1 should succeed");
        history
            .append_entry(sample_entry("2", 2))
            .expect("append 2 should succeed");
        history
            .append_entry(sample_entry("3", 3))
            .expect("append 3 should succeed");

        let entries = history.load_entries().expect("load should succeed");
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].id, "2");
        assert_eq!(entries[1].id, "3");

        let _ = fs::remove_file(path);
    }

    #[test]
    fn corrupted_history_file_is_quarantined_and_reset() {
        let path = temp_history_path("corrupt-file");
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).expect("create parent");
        }

        fs::write(&path, b"not-a-valid-history-file").expect("write corrupt history");

        let store = InMemorySecretStore::default();
        let history = EncryptedHistoryStore::new(path.clone(), store, PrefixCipher);
        let loaded = history.load_entries().expect("load should recover");

        assert!(loaded.is_empty());
        assert!(!path.exists());

        let parent = path.parent().expect("history parent path");
        let file_name = path
            .file_name()
            .and_then(|name| name.to_str())
            .expect("history file name");
        let quarantine_found = fs::read_dir(parent)
            .expect("read history parent")
            .flatten()
            .filter_map(|entry| entry.file_name().to_str().map(ToString::to_string))
            .any(|name| name.starts_with(&format!("{file_name}.corrupt-")));
        assert!(quarantine_found);
    }

    #[test]
    fn corrupted_history_key_is_regenerated() {
        let path = temp_history_path("corrupt-key");
        let store = InMemorySecretStore::default();
        store.write_raw(
            HISTORY_KEY_SERVICE,
            HISTORY_KEY_ACCOUNT,
            b"bad-key-payload".to_vec(),
        );

        let history = EncryptedHistoryStore::new(path.clone(), store.clone(), PrefixCipher);
        history
            .save_entries(&[sample_entry("1", 1)])
            .expect("save should recover from bad key payload");

        let key = store
            .read_raw(HISTORY_KEY_SERVICE, HISTORY_KEY_ACCOUNT)
            .expect("history key should be stored");
        assert!(key.starts_with(b"enc:"));

        let _ = fs::remove_file(path);
    }

    #[test]
    fn clear_history_removes_file_and_key() {
        let path = temp_history_path("clear");
        let store = InMemorySecretStore::default();
        let history = EncryptedHistoryStore::new(path.clone(), store.clone(), PrefixCipher);

        history
            .save_entries(&[sample_entry("1", 1)])
            .expect("save should succeed");
        assert!(path.exists());
        assert!(store
            .read_raw(HISTORY_KEY_SERVICE, HISTORY_KEY_ACCOUNT)
            .is_some());

        history.clear_history().expect("clear should succeed");
        assert!(!path.exists());
        assert!(store
            .read_raw(HISTORY_KEY_SERVICE, HISTORY_KEY_ACCOUNT)
            .is_none());
    }
}
