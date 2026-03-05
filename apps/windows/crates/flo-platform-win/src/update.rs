use std::{
    fs::File,
    io::{BufReader, Read},
    path::{Path, PathBuf},
};

use sha2::{Digest, Sha256};
use thiserror::Error;

pub type UpdateResult<T> = Result<T, UpdateError>;

#[derive(Debug, Error)]
pub enum UpdateError {
    #[error("feed unavailable: {0}")]
    FeedUnavailable(String),
    #[error("download failed: {0}")]
    DownloadFailed(String),
    #[error("checksum mismatch")]
    ChecksumMismatch,
    #[error("apply failed: {0}")]
    ApplyFailed(String),
    #[error("io error: {0}")]
    Io(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpdateManifest {
    pub version: String,
    pub channel: String,
    pub published_at_utc: String,
    pub artifact_url: String,
    pub sha256: String,
    pub notes_url: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpdateApplyPlan {
    pub artifact_path: PathBuf,
    pub staging_dir: PathBuf,
    pub restart_required: bool,
}

pub trait UpdateService: Send + Sync {
    fn check_feed(
        &self,
        current_version: &str,
        channel: &str,
    ) -> UpdateResult<Option<UpdateManifest>>;
    fn download_update(
        &self,
        manifest: &UpdateManifest,
        destination_dir: &Path,
    ) -> UpdateResult<PathBuf>;
    fn verify_checksum(&self, artifact_path: &Path, expected_sha256: &str) -> UpdateResult<()>;
    fn stage_apply(&self, artifact_path: &Path) -> UpdateResult<UpdateApplyPlan>;
}

#[derive(Debug, Default)]
pub struct ZipChannelUpdater;

impl UpdateService for ZipChannelUpdater {
    fn check_feed(
        &self,
        _current_version: &str,
        _channel: &str,
    ) -> UpdateResult<Option<UpdateManifest>> {
        // Scaffold: feed client lands in W8.
        Ok(None)
    }

    fn download_update(
        &self,
        manifest: &UpdateManifest,
        destination_dir: &Path,
    ) -> UpdateResult<PathBuf> {
        let filename = manifest
            .artifact_url
            .rsplit('/')
            .next()
            .filter(|it| !it.is_empty())
            .unwrap_or("flo-update.zip");
        Ok(destination_dir.join(filename))
    }

    fn verify_checksum(&self, artifact_path: &Path, expected_sha256: &str) -> UpdateResult<()> {
        let actual = sha256_file(artifact_path)?;
        if actual.eq_ignore_ascii_case(expected_sha256) {
            Ok(())
        } else {
            Err(UpdateError::ChecksumMismatch)
        }
    }

    fn stage_apply(&self, artifact_path: &Path) -> UpdateResult<UpdateApplyPlan> {
        let staging_dir = artifact_path
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .join("staged-update");
        Ok(UpdateApplyPlan {
            artifact_path: artifact_path.to_path_buf(),
            staging_dir,
            restart_required: true,
        })
    }
}

fn sha256_file(path: &Path) -> UpdateResult<String> {
    let file = File::open(path).map_err(|err| UpdateError::Io(err.to_string()))?;
    let mut reader = BufReader::new(file);
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 8 * 1024];

    loop {
        let read = reader
            .read(&mut buffer)
            .map_err(|err| UpdateError::Io(err.to_string()))?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }

    Ok(hex::encode(hasher.finalize()))
}
