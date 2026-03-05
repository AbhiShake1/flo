use thiserror::Error;

pub type SecretResult<T> = Result<T, SecretStoreError>;

#[derive(Debug, Error, Clone, PartialEq, Eq)]
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

#[derive(Debug, Default, Clone, Copy)]
pub struct CredentialManagerSecretStore;

impl SecretStore for CredentialManagerSecretStore {
    fn read_secret(&self, service: &str, account: &str) -> SecretResult<Option<Vec<u8>>> {
        #[cfg(windows)]
        {
            return windows_impl::read_credential(service, account);
        }
        #[cfg(not(windows))]
        {
            let _ = (service, account);
            Err(SecretStoreError::Unavailable(
                "Credential Manager requires Windows".to_string(),
            ))
        }
    }

    fn write_secret(&self, service: &str, account: &str, value: &[u8]) -> SecretResult<()> {
        #[cfg(windows)]
        {
            return windows_impl::write_credential(service, account, value);
        }
        #[cfg(not(windows))]
        {
            let _ = (service, account, value);
            Err(SecretStoreError::Unavailable(
                "Credential Manager requires Windows".to_string(),
            ))
        }
    }

    fn delete_secret(&self, service: &str, account: &str) -> SecretResult<()> {
        #[cfg(windows)]
        {
            return windows_impl::delete_credential(service, account);
        }
        #[cfg(not(windows))]
        {
            let _ = (service, account);
            Err(SecretStoreError::Unavailable(
                "Credential Manager requires Windows".to_string(),
            ))
        }
    }
}

#[derive(Debug, Default, Clone, Copy)]
pub struct WindowsDpapiCipher;

impl DpapiCipher for WindowsDpapiCipher {
    fn protect(&self, plaintext: &[u8], entropy: Option<&[u8]>) -> SecretResult<Vec<u8>> {
        #[cfg(windows)]
        {
            return windows_impl::dpapi_protect(plaintext, entropy);
        }
        #[cfg(not(windows))]
        {
            let _ = (plaintext, entropy);
            Err(SecretStoreError::Unavailable(
                "DPAPI requires Windows".to_string(),
            ))
        }
    }

    fn unprotect(&self, ciphertext: &[u8], entropy: Option<&[u8]>) -> SecretResult<Vec<u8>> {
        #[cfg(windows)]
        {
            return windows_impl::dpapi_unprotect(ciphertext, entropy);
        }
        #[cfg(not(windows))]
        {
            let _ = (ciphertext, entropy);
            Err(SecretStoreError::Unavailable(
                "DPAPI requires Windows".to_string(),
            ))
        }
    }
}

#[cfg(windows)]
mod windows_impl {
    use std::{ffi::c_void, ptr::null_mut};

    use windows::{
        core::{PCWSTR, PWSTR},
        Win32::{
            Foundation::{GetLastError, ERROR_NOT_FOUND},
            Security::{
                Credentials::{
                    CredDeleteW, CredFree, CredReadW, CredWriteW, CREDENTIALW,
                    CRED_MAX_CREDENTIAL_BLOB_SIZE, CRED_PERSIST_LOCAL_MACHINE, CRED_TYPE_GENERIC,
                },
                Cryptography::{
                    CryptProtectData, CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, DATA_BLOB,
                },
            },
            System::Memory::LocalFree,
        },
    };

    use super::{SecretResult, SecretStoreError};

    const TARGET_PREFIX: &str = "flo";

    pub fn read_credential(service: &str, account: &str) -> SecretResult<Option<Vec<u8>>> {
        let target_name = target_name(service, account);
        let target_wide = to_utf16_null(&target_name);
        let mut credential_ptr: *mut CREDENTIALW = null_mut();

        let ok = unsafe {
            CredReadW(
                PCWSTR(target_wide.as_ptr()),
                CRED_TYPE_GENERIC,
                0,
                &mut credential_ptr,
            )
            .as_bool()
        };

        if !ok {
            let error = unsafe { GetLastError() };
            if error == ERROR_NOT_FOUND {
                return Ok(None);
            }
            return Err(SecretStoreError::Unavailable(format!(
                "CredReadW failed: {error:?}"
            )));
        }

        let credential = unsafe { &*credential_ptr };
        let value = if credential.CredentialBlobSize == 0 || credential.CredentialBlob.is_null() {
            Vec::new()
        } else {
            unsafe {
                std::slice::from_raw_parts(
                    credential.CredentialBlob,
                    credential.CredentialBlobSize as usize,
                )
                .to_vec()
            }
        };

        unsafe {
            CredFree(credential_ptr as *const c_void);
        }

        Ok(Some(value))
    }

    pub fn write_credential(service: &str, account: &str, value: &[u8]) -> SecretResult<()> {
        if value.len() > CRED_MAX_CREDENTIAL_BLOB_SIZE as usize {
            return Err(SecretStoreError::Serialization(format!(
                "credential blob exceeds max size ({})",
                CRED_MAX_CREDENTIAL_BLOB_SIZE
            )));
        }

        let target_name = target_name(service, account);
        let mut target_wide = to_utf16_null(&target_name);
        let mut account_wide = to_utf16_null(account);
        let mut blob = value.to_vec();

        let credential = CREDENTIALW {
            Type: CRED_TYPE_GENERIC,
            TargetName: PWSTR(target_wide.as_mut_ptr()),
            UserName: PWSTR(account_wide.as_mut_ptr()),
            CredentialBlobSize: blob.len() as u32,
            CredentialBlob: if blob.is_empty() {
                null_mut()
            } else {
                blob.as_mut_ptr()
            },
            Persist: CRED_PERSIST_LOCAL_MACHINE,
            ..Default::default()
        };

        let ok = unsafe { CredWriteW(&credential, 0).as_bool() };
        if ok {
            Ok(())
        } else {
            let error = unsafe { GetLastError() };
            Err(SecretStoreError::Unavailable(format!(
                "CredWriteW failed: {error:?}"
            )))
        }
    }

    pub fn delete_credential(service: &str, account: &str) -> SecretResult<()> {
        let target_name = target_name(service, account);
        let target_wide = to_utf16_null(&target_name);
        let ok =
            unsafe { CredDeleteW(PCWSTR(target_wide.as_ptr()), CRED_TYPE_GENERIC, 0).as_bool() };

        if ok {
            return Ok(());
        }

        let error = unsafe { GetLastError() };
        if error == ERROR_NOT_FOUND {
            Ok(())
        } else {
            Err(SecretStoreError::Unavailable(format!(
                "CredDeleteW failed: {error:?}"
            )))
        }
    }

    pub fn dpapi_protect(plaintext: &[u8], entropy: Option<&[u8]>) -> SecretResult<Vec<u8>> {
        let mut input_blob = to_blob(plaintext);
        let mut entropy_buf = entropy.map(|bytes| bytes.to_vec());
        let mut entropy_blob = entropy_buf.as_deref_mut().map(to_blob);
        let mut output_blob = DATA_BLOB::default();

        let ok = unsafe {
            CryptProtectData(
                &mut input_blob,
                None,
                entropy_blob
                    .as_mut()
                    .map(|blob| blob as *mut DATA_BLOB)
                    .map(|blob| blob as _),
                None,
                None,
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output_blob,
            )
            .as_bool()
        };

        if !ok {
            let error = unsafe { GetLastError() };
            return Err(SecretStoreError::Unavailable(format!(
                "CryptProtectData failed: {error:?}"
            )));
        }

        let encrypted = unsafe {
            std::slice::from_raw_parts(output_blob.pbData, output_blob.cbData as usize).to_vec()
        };
        unsafe {
            let _ = LocalFree(output_blob.pbData as isize);
        }

        Ok(encrypted)
    }

    pub fn dpapi_unprotect(ciphertext: &[u8], entropy: Option<&[u8]>) -> SecretResult<Vec<u8>> {
        let mut input_blob = to_blob(ciphertext);
        let mut entropy_buf = entropy.map(|bytes| bytes.to_vec());
        let mut entropy_blob = entropy_buf.as_deref_mut().map(to_blob);
        let mut output_blob = DATA_BLOB::default();

        let ok = unsafe {
            CryptUnprotectData(
                &mut input_blob,
                None,
                entropy_blob
                    .as_mut()
                    .map(|blob| blob as *mut DATA_BLOB)
                    .map(|blob| blob as _),
                None,
                None,
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output_blob,
            )
            .as_bool()
        };

        if !ok {
            let error = unsafe { GetLastError() };
            return Err(SecretStoreError::Unavailable(format!(
                "CryptUnprotectData failed: {error:?}"
            )));
        }

        let plaintext = unsafe {
            std::slice::from_raw_parts(output_blob.pbData, output_blob.cbData as usize).to_vec()
        };
        unsafe {
            let _ = LocalFree(output_blob.pbData as isize);
        }

        Ok(plaintext)
    }

    fn target_name(service: &str, account: &str) -> String {
        format!("{TARGET_PREFIX}/{service}/{account}")
    }

    fn to_utf16_null(value: &str) -> Vec<u16> {
        value.encode_utf16().chain(std::iter::once(0)).collect()
    }

    fn to_blob(bytes: &mut [u8]) -> DATA_BLOB {
        DATA_BLOB {
            cbData: bytes.len() as u32,
            pbData: if bytes.is_empty() {
                null_mut()
            } else {
                bytes.as_mut_ptr()
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        CredentialManagerSecretStore, DpapiCipher, SecretStore, SecretStoreError,
        WindowsDpapiCipher,
    };

    #[cfg(not(windows))]
    #[test]
    fn credential_manager_store_reports_unavailable_on_non_windows() {
        let store = CredentialManagerSecretStore;
        assert!(matches!(
            store.read_secret("svc", "acct"),
            Err(SecretStoreError::Unavailable(_))
        ));
    }

    #[cfg(not(windows))]
    #[test]
    fn dpapi_cipher_reports_unavailable_on_non_windows() {
        let cipher = WindowsDpapiCipher;
        assert!(matches!(
            cipher.protect(b"hello", None),
            Err(SecretStoreError::Unavailable(_))
        ));
        assert!(matches!(
            cipher.unprotect(b"hello", None),
            Err(SecretStoreError::Unavailable(_))
        ));
    }
}
