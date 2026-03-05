use thiserror::Error;

pub type AudioResult<T> = Result<T, AudioError>;

#[derive(Debug, Error, Clone, PartialEq, Eq)]
pub enum AudioError {
    #[error("capture already active")]
    AlreadyCapturing,
    #[error("capture not active")]
    NotCapturing,
    #[error("playback already active")]
    AlreadyPlaying,
    #[error("playback not active")]
    NotPlaying,
    #[error("platform backend error: {0}")]
    Platform(String),
}

pub trait CaptureBackend: Send {
    fn start_capture(&mut self) -> AudioResult<()>;
    fn stop_capture(&mut self) -> AudioResult<Vec<i16>>;
    fn cancel_capture(&mut self) -> AudioResult<()>;
}

pub trait PlaybackBackend: Send {
    fn start_playback(&mut self, pcm: &[i16], sample_rate_hz: u32) -> AudioResult<()>;
    fn stop_playback(&mut self) -> AudioResult<()>;
}

pub struct WasapiAudioCoordinator<C, P>
where
    C: CaptureBackend,
    P: PlaybackBackend,
{
    capture_backend: C,
    playback_backend: P,
    capturing: bool,
    playing: bool,
}

impl<C, P> WasapiAudioCoordinator<C, P>
where
    C: CaptureBackend,
    P: PlaybackBackend,
{
    pub fn new(capture_backend: C, playback_backend: P) -> Self {
        Self {
            capture_backend,
            playback_backend,
            capturing: false,
            playing: false,
        }
    }

    pub fn is_capturing(&self) -> bool {
        self.capturing
    }

    pub fn is_playing(&self) -> bool {
        self.playing
    }

    pub fn start_capture(&mut self) -> AudioResult<()> {
        if self.capturing {
            return Err(AudioError::AlreadyCapturing);
        }

        if self.playing {
            self.playback_backend.stop_playback()?;
            self.playing = false;
        }

        self.capture_backend.start_capture()?;
        self.capturing = true;
        Ok(())
    }

    pub fn stop_capture(&mut self) -> AudioResult<Vec<i16>> {
        if !self.capturing {
            return Err(AudioError::NotCapturing);
        }

        let audio = self.capture_backend.stop_capture()?;
        self.capturing = false;
        Ok(audio)
    }

    pub fn cancel_capture(&mut self) -> AudioResult<()> {
        if !self.capturing {
            return Ok(());
        }

        self.capture_backend.cancel_capture()?;
        self.capturing = false;
        Ok(())
    }

    pub fn start_playback(&mut self, pcm: &[i16], sample_rate_hz: u32) -> AudioResult<()> {
        if self.playing {
            return Err(AudioError::AlreadyPlaying);
        }

        if self.capturing {
            self.capture_backend.cancel_capture()?;
            self.capturing = false;
        }

        self.playback_backend.start_playback(pcm, sample_rate_hz)?;
        self.playing = true;
        Ok(())
    }

    pub fn stop_playback(&mut self) -> AudioResult<()> {
        if !self.playing {
            return Ok(());
        }

        self.playback_backend.stop_playback()?;
        self.playing = false;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};

    use super::*;

    #[derive(Debug, Clone)]
    struct FakeCaptureBackend {
        log: Arc<Mutex<Vec<String>>>,
        stop_audio: Vec<i16>,
    }

    impl FakeCaptureBackend {
        fn new(log: Arc<Mutex<Vec<String>>>) -> Self {
            Self {
                log,
                stop_audio: vec![1, 2, 3],
            }
        }
    }

    impl CaptureBackend for FakeCaptureBackend {
        fn start_capture(&mut self) -> AudioResult<()> {
            self.log
                .lock()
                .expect("lock log")
                .push("capture:start".to_string());
            Ok(())
        }

        fn stop_capture(&mut self) -> AudioResult<Vec<i16>> {
            self.log
                .lock()
                .expect("lock log")
                .push("capture:stop".to_string());
            Ok(self.stop_audio.clone())
        }

        fn cancel_capture(&mut self) -> AudioResult<()> {
            self.log
                .lock()
                .expect("lock log")
                .push("capture:cancel".to_string());
            Ok(())
        }
    }

    #[derive(Debug, Clone)]
    struct FakePlaybackBackend {
        log: Arc<Mutex<Vec<String>>>,
    }

    impl FakePlaybackBackend {
        fn new(log: Arc<Mutex<Vec<String>>>) -> Self {
            Self { log }
        }
    }

    impl PlaybackBackend for FakePlaybackBackend {
        fn start_playback(&mut self, _pcm: &[i16], _sample_rate_hz: u32) -> AudioResult<()> {
            self.log
                .lock()
                .expect("lock log")
                .push("playback:start".to_string());
            Ok(())
        }

        fn stop_playback(&mut self) -> AudioResult<()> {
            self.log
                .lock()
                .expect("lock log")
                .push("playback:stop".to_string());
            Ok(())
        }
    }

    fn log_snapshot(log: &Arc<Mutex<Vec<String>>>) -> Vec<String> {
        log.lock().expect("lock log").clone()
    }

    #[test]
    fn start_capture_interrupts_active_playback() {
        let log = Arc::new(Mutex::new(Vec::new()));
        let mut coordinator = WasapiAudioCoordinator::new(
            FakeCaptureBackend::new(log.clone()),
            FakePlaybackBackend::new(log.clone()),
        );

        coordinator
            .start_playback(&[1, 2], 24_000)
            .expect("playback start should succeed");
        coordinator
            .start_capture()
            .expect("capture start should succeed");

        assert!(coordinator.is_capturing());
        assert!(!coordinator.is_playing());
        assert_eq!(
            log_snapshot(&log),
            vec![
                "playback:start".to_string(),
                "playback:stop".to_string(),
                "capture:start".to_string(),
            ]
        );
    }

    #[test]
    fn start_playback_cancels_active_capture() {
        let log = Arc::new(Mutex::new(Vec::new()));
        let mut coordinator = WasapiAudioCoordinator::new(
            FakeCaptureBackend::new(log.clone()),
            FakePlaybackBackend::new(log.clone()),
        );

        coordinator
            .start_capture()
            .expect("capture start should succeed");
        coordinator
            .start_playback(&[1, 2], 24_000)
            .expect("playback start should succeed");

        assert!(!coordinator.is_capturing());
        assert!(coordinator.is_playing());
        assert_eq!(
            log_snapshot(&log),
            vec![
                "capture:start".to_string(),
                "capture:cancel".to_string(),
                "playback:start".to_string(),
            ]
        );
    }

    #[test]
    fn stop_capture_returns_audio_frames() {
        let log = Arc::new(Mutex::new(Vec::new()));
        let mut coordinator = WasapiAudioCoordinator::new(
            FakeCaptureBackend::new(log.clone()),
            FakePlaybackBackend::new(log.clone()),
        );

        coordinator
            .start_capture()
            .expect("capture start should succeed");
        let frames = coordinator
            .stop_capture()
            .expect("capture stop should succeed");

        assert_eq!(frames, vec![1, 2, 3]);
        assert!(!coordinator.is_capturing());
        assert_eq!(
            log_snapshot(&log),
            vec!["capture:start".to_string(), "capture:stop".to_string(),]
        );
    }

    #[test]
    fn start_capture_fails_when_already_capturing() {
        let log = Arc::new(Mutex::new(Vec::new()));
        let mut coordinator = WasapiAudioCoordinator::new(
            FakeCaptureBackend::new(log.clone()),
            FakePlaybackBackend::new(log),
        );

        coordinator
            .start_capture()
            .expect("initial capture start should succeed");
        let error = coordinator
            .start_capture()
            .expect_err("second start should fail");

        assert_eq!(error, AudioError::AlreadyCapturing);
    }

    #[test]
    fn stop_playback_is_idempotent() {
        let log = Arc::new(Mutex::new(Vec::new()));
        let mut coordinator = WasapiAudioCoordinator::new(
            FakeCaptureBackend::new(log.clone()),
            FakePlaybackBackend::new(log.clone()),
        );

        coordinator
            .stop_playback()
            .expect("first stop should be no-op");
        coordinator
            .start_playback(&[1, 2], 24_000)
            .expect("playback start should succeed");
        coordinator.stop_playback().expect("stop should succeed");

        assert!(!coordinator.is_playing());
        assert_eq!(
            log_snapshot(&log),
            vec!["playback:start".to_string(), "playback:stop".to_string(),]
        );
    }
}
