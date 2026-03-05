use thiserror::Error;

pub type SecretResult<T> = Result<T, SecretStoreError>;

#[derive(Debug, Error)]
pub enum SecretStoreError {
    #[error("store unavailable: {0}")]
    Unavailable(String),
    #[error("serialization error: {0}")]
    Serialization(String),
    #[error("io error: {0}")]
    Io(String),
}

pub trait SecretStore: Send + Sync {
    fn read_secret(&self, service: &str, account: &str) -> SecretResult<Option<Vec<u8>>>;
    fn write_secret(&self, service: &str, account: &str, value: &[u8]) -> SecretResult<()>;
    fn delete_secret(&self, service: &str, account: &str) -> SecretResult<()>;
}

pub trait DpapiCipher: Send + Sync {
    fn protect(&self, plaintext: &[u8], entropy: Option<&[u8]>) -> SecretResult<Vec<u8>>;
    fn unprotect(&self, ciphertext: &[u8], entropy: Option<&[u8]>) -> SecretResult<Vec<u8>>;
}

#[derive(Debug, Default)]
pub struct CredentialManagerSecretStore;

impl SecretStore for CredentialManagerSecretStore {
    fn read_secret(&self, _service: &str, _account: &str) -> SecretResult<Option<Vec<u8>>> {
        #[cfg(windows)]
        {
            // Scaffold: Win32 Credential Manager wiring lands in W4.
            return Err(SecretStoreError::Unavailable(
                "Credential Manager backend not wired yet".to_string(),
            ));
        }
        #[cfg(not(windows))]
        {
            Err(SecretStoreError::Unavailable(
                "Credential Manager requires Windows".to_string(),
            ))
        }
    }

    fn write_secret(&self, _service: &str, _account: &str, _value: &[u8]) -> SecretResult<()> {
        #[cfg(windows)]
        {
            return Err(SecretStoreError::Unavailable(
                "Credential Manager backend not wired yet".to_string(),
            ));
        }
        #[cfg(not(windows))]
        {
            Err(SecretStoreError::Unavailable(
                "Credential Manager requires Windows".to_string(),
            ))
        }
    }

    fn delete_secret(&self, _service: &str, _account: &str) -> SecretResult<()> {
        #[cfg(windows)]
        {
            return Err(SecretStoreError::Unavailable(
                "Credential Manager backend not wired yet".to_string(),
            ));
        }
        #[cfg(not(windows))]
        {
            Err(SecretStoreError::Unavailable(
                "Credential Manager requires Windows".to_string(),
            ))
        }
    }
}

#[derive(Debug, Default)]
pub struct WindowsDpapiCipher;

impl DpapiCipher for WindowsDpapiCipher {
    fn protect(&self, _plaintext: &[u8], _entropy: Option<&[u8]>) -> SecretResult<Vec<u8>> {
        #[cfg(windows)]
        {
            // Scaffold: DPAPI wiring lands in W4.
            return Ok(_plaintext.to_vec());
        }
        #[cfg(not(windows))]
        {
            Err(SecretStoreError::Unavailable(
                "DPAPI requires Windows".to_string(),
            ))
        }
    }

    fn unprotect(&self, _ciphertext: &[u8], _entropy: Option<&[u8]>) -> SecretResult<Vec<u8>> {
        #[cfg(windows)]
        {
            return Ok(_ciphertext.to_vec());
        }
        #[cfg(not(windows))]
        {
            Err(SecretStoreError::Unavailable(
                "DPAPI requires Windows".to_string(),
            ))
        }
    }
}
