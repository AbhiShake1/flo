use std::{
    cmp::Ordering,
    fs::{self, File},
    io::{BufReader, Read},
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;

pub type UpdateResult<T> = Result<T, UpdateError>;

#[derive(Debug, Error)]
pub enum UpdateError {
    #[error("feed unavailable: {0}")]
    FeedUnavailable(String),
    #[error("feed parse failed: {0}")]
    FeedParseFailed(String),
    #[error("download failed: {0}")]
    DownloadFailed(String),
    #[error("checksum mismatch")]
    ChecksumMismatch,
    #[error("apply failed: {0}")]
    ApplyFailed(String),
    #[error("io error: {0}")]
    Io(String),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
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
    pub staged_manifest_path: PathBuf,
    pub rollback_pointer_path: PathBuf,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
struct UpdateFeedEnvelope {
    releases: Vec<UpdateManifest>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct StagedUpdateMetadata {
    staged_artifact_filename: String,
    staged_sha256: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
struct RollbackPointer {
    previous_artifact_path: String,
}

#[derive(Debug, Clone, Default)]
pub struct ZipChannelUpdater {
    feed_path: Option<PathBuf>,
}

impl ZipChannelUpdater {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn with_feed_path(feed_path: PathBuf) -> Self {
        Self {
            feed_path: Some(feed_path),
        }
    }

    pub fn select_update_from_feed_json(
        &self,
        feed_json: &str,
        current_version: &str,
        channel: &str,
    ) -> UpdateResult<Option<UpdateManifest>> {
        let envelope = parse_feed_json(feed_json)?;
        let channel = channel.trim().to_ascii_lowercase();

        let candidate = envelope
            .releases
            .into_iter()
            .filter(|release| release.channel.trim().eq_ignore_ascii_case(&channel))
            .filter(|release| {
                compare_versions(&release.version, current_version) == Ordering::Greater
            })
            .max_by(|a, b| compare_versions(&a.version, &b.version));

        Ok(candidate)
    }
}

impl UpdateService for ZipChannelUpdater {
    fn check_feed(
        &self,
        current_version: &str,
        channel: &str,
    ) -> UpdateResult<Option<UpdateManifest>> {
        let Some(feed_path) = self.feed_path.as_ref() else {
            return Ok(None);
        };

        let feed_json = fs::read_to_string(feed_path)
            .map_err(|err| UpdateError::FeedUnavailable(err.to_string()))?;

        self.select_update_from_feed_json(&feed_json, current_version, channel)
    }

    fn download_update(
        &self,
        manifest: &UpdateManifest,
        destination_dir: &Path,
    ) -> UpdateResult<PathBuf> {
        fs::create_dir_all(destination_dir).map_err(|err| UpdateError::Io(err.to_string()))?;

        let filename = manifest
            .artifact_url
            .rsplit('/')
            .next()
            .filter(|it| !it.is_empty())
            .unwrap_or("flo-update.zip");
        let destination = destination_dir.join(filename);

        if let Some(path) = manifest.artifact_url.strip_prefix("file://") {
            fs::copy(path, &destination)
                .map_err(|err| UpdateError::DownloadFailed(err.to_string()))?;
            return Ok(destination);
        }

        if manifest.artifact_url.starts_with("http://")
            || manifest.artifact_url.starts_with("https://")
        {
            return Err(UpdateError::DownloadFailed(
                "network downloader is not wired yet; use file:// feed artifacts in scaffold"
                    .to_string(),
            ));
        }

        Err(UpdateError::DownloadFailed(format!(
            "unsupported artifact URL: {}",
            manifest.artifact_url
        )))
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
        if !artifact_path.exists() {
            return Err(UpdateError::ApplyFailed(format!(
                "artifact path does not exist: {}",
                artifact_path.display()
            )));
        }

        let parent = artifact_path.parent().unwrap_or_else(|| Path::new("."));
        let staging_dir = parent.join("staged-update").join(now_unix_ms().to_string());
        fs::create_dir_all(&staging_dir).map_err(|err| UpdateError::Io(err.to_string()))?;

        let artifact_name = artifact_path
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("flo-update.zip")
            .to_string();

        let staged_artifact_path = staging_dir.join(&artifact_name);
        fs::copy(artifact_path, &staged_artifact_path)
            .map_err(|err| UpdateError::ApplyFailed(err.to_string()))?;

        let metadata = StagedUpdateMetadata {
            staged_artifact_filename: artifact_name,
            staged_sha256: sha256_file(&staged_artifact_path)?,
        };

        let staged_manifest_path = staging_dir.join("apply-manifest.json");
        let metadata_json =
            serde_json::to_vec_pretty(&metadata).map_err(|err| UpdateError::Io(err.to_string()))?;
        fs::write(&staged_manifest_path, metadata_json)
            .map_err(|err| UpdateError::Io(err.to_string()))?;

        let rollback_pointer = RollbackPointer {
            previous_artifact_path: artifact_path.display().to_string(),
        };
        let rollback_pointer_path = staging_dir.join("rollback.pointer.json");
        let rollback_json = serde_json::to_vec_pretty(&rollback_pointer)
            .map_err(|err| UpdateError::Io(err.to_string()))?;
        fs::write(&rollback_pointer_path, rollback_json)
            .map_err(|err| UpdateError::Io(err.to_string()))?;

        Ok(UpdateApplyPlan {
            artifact_path: staged_artifact_path,
            staging_dir,
            staged_manifest_path,
            rollback_pointer_path,
            restart_required: true,
        })
    }
}

fn parse_feed_json(feed_json: &str) -> UpdateResult<UpdateFeedEnvelope> {
    if let Ok(releases) = serde_json::from_str::<Vec<UpdateManifest>>(feed_json) {
        return Ok(UpdateFeedEnvelope { releases });
    }

    serde_json::from_str::<UpdateFeedEnvelope>(feed_json)
        .map_err(|err| UpdateError::FeedParseFailed(err.to_string()))
}

fn compare_versions(left: &str, right: &str) -> Ordering {
    let left_parts = normalize_semver_parts(left);
    let right_parts = normalize_semver_parts(right);

    for index in 0..left_parts.len().max(right_parts.len()) {
        let left_part = *left_parts.get(index).unwrap_or(&0);
        let right_part = *right_parts.get(index).unwrap_or(&0);
        match left_part.cmp(&right_part) {
            Ordering::Equal => continue,
            other => return other,
        }
    }

    Ordering::Equal
}

fn normalize_semver_parts(version: &str) -> Vec<u64> {
    version
        .split(['.', '-', '+'])
        .filter_map(|part| {
            let digits: String = part.chars().take_while(|ch| ch.is_ascii_digit()).collect();
            if digits.is_empty() {
                None
            } else {
                digits.parse::<u64>().ok()
            }
        })
        .collect()
}

fn now_unix_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(0)
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

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(test_name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("flo-update-{test_name}-{}", now_unix_ms()));
        fs::create_dir_all(&dir).expect("create temp dir");
        dir
    }

    #[test]
    fn selects_latest_release_in_channel() {
        let updater = ZipChannelUpdater::new();
        let feed = r#"
        {
          "releases": [
            {"version":"1.2.0","channel":"stable","published_at_utc":"2026-01-01T00:00:00Z","artifact_url":"file:///tmp/flo-1.2.0.zip","sha256":"abc","notes_url":null},
            {"version":"1.4.0","channel":"beta","published_at_utc":"2026-01-01T00:00:00Z","artifact_url":"file:///tmp/flo-1.4.0.zip","sha256":"abc","notes_url":null},
            {"version":"1.3.1","channel":"stable","published_at_utc":"2026-02-01T00:00:00Z","artifact_url":"file:///tmp/flo-1.3.1.zip","sha256":"abc","notes_url":null}
          ]
        }
        "#;

        let release = updater
            .select_update_from_feed_json(feed, "1.2.9", "stable")
            .expect("feed parse should succeed")
            .expect("newer stable release should exist");

        assert_eq!(release.version, "1.3.1");
    }

    #[test]
    fn returns_none_when_no_newer_release() {
        let updater = ZipChannelUpdater::new();
        let feed = r#"
        [
          {"version":"1.0.0","channel":"stable","published_at_utc":"2026-01-01T00:00:00Z","artifact_url":"file:///tmp/flo-1.0.0.zip","sha256":"abc","notes_url":null}
        ]
        "#;

        let release = updater
            .select_update_from_feed_json(feed, "1.0.0", "stable")
            .expect("feed parse should succeed");
        assert!(release.is_none());
    }

    #[test]
    fn downloads_from_file_scheme() {
        let updater = ZipChannelUpdater::new();
        let source_dir = temp_dir("download-source");
        let destination_dir = temp_dir("download-destination");
        let source_file = source_dir.join("flo.zip");
        fs::write(&source_file, b"zip-bytes").expect("write source file");

        let manifest = UpdateManifest {
            version: "1.2.0".to_string(),
            channel: "stable".to_string(),
            published_at_utc: "2026-03-01T00:00:00Z".to_string(),
            artifact_url: format!("file://{}", source_file.display()),
            sha256: "unused".to_string(),
            notes_url: None,
        };

        let downloaded = updater
            .download_update(&manifest, &destination_dir)
            .expect("download should succeed");

        assert!(downloaded.exists());
        assert_eq!(
            fs::read(downloaded).expect("read downloaded bytes"),
            b"zip-bytes"
        );
    }

    #[test]
    fn checksum_verification_rejects_mismatch() {
        let updater = ZipChannelUpdater::new();
        let dir = temp_dir("checksum");
        let artifact = dir.join("flo.zip");
        fs::write(&artifact, b"abc").expect("write artifact");

        let err = updater
            .verify_checksum(&artifact, "deadbeef")
            .expect_err("mismatched checksum should fail");
        assert!(matches!(err, UpdateError::ChecksumMismatch));
    }

    #[test]
    fn stage_apply_creates_manifest_and_rollback_pointer() {
        let updater = ZipChannelUpdater::new();
        let dir = temp_dir("stage");
        let artifact = dir.join("flo.zip");
        fs::write(&artifact, b"artifact").expect("write artifact");

        let plan = updater
            .stage_apply(&artifact)
            .expect("stage apply should work");

        assert!(plan.artifact_path.exists());
        assert!(plan.staging_dir.exists());
        assert!(plan.staged_manifest_path.exists());
        assert!(plan.rollback_pointer_path.exists());

        let metadata_bytes = fs::read(&plan.staged_manifest_path).expect("read staged metadata");
        let metadata: StagedUpdateMetadata =
            serde_json::from_slice(&metadata_bytes).expect("parse staged metadata");
        assert_eq!(metadata.staged_artifact_filename, "flo.zip");
        assert!(!metadata.staged_sha256.is_empty());

        let rollback_bytes = fs::read(&plan.rollback_pointer_path).expect("read rollback pointer");
        let rollback: RollbackPointer =
            serde_json::from_slice(&rollback_bytes).expect("parse rollback pointer");
        assert_eq!(
            rollback.previous_artifact_path,
            artifact.display().to_string()
        );
    }
}
