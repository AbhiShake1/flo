use anyhow::Result;
use flo_core::{
    capabilities::PlatformCapabilities,
    controller::{FloCommand, FloController},
};
use flo_provider::config::FloConfiguration;
use std::path::PathBuf;

#[cfg(test)]
mod acceptance;
mod runtime;
mod services;

use runtime::EffectRuntime;
use services::RuntimeServiceBundle;

fn main() -> Result<()> {
    let config = FloConfiguration::from_process_env()?;
    let mut controller = FloController::new();
    let capabilities = PlatformCapabilities::win32_default();
    let data_dir = resolve_data_dir();
    let mut services = RuntimeServiceBundle::from_data_dir(data_dir);

    let bootstrap_effects = controller.dispatch(FloCommand::Bootstrap, &capabilities);
    let mut runtime = EffectRuntime::new(
        &mut services.selection_reader,
        &mut services.text_injection,
        &mut services.elevation_service,
        &mut services.permissions_service,
        &mut services.floating_bar,
        &mut services.dictation_store,
        &mut services.voice_store,
        &mut services.auth_service,
        &mut services.auth_state_sink,
        &mut services.speech_capture,
        &mut services.tts_service,
    );
    runtime.drive_effects(&mut controller, bootstrap_effects);

    println!(
        "flo-app initialized (provider={}, auth={:?}, permissions={:?}, recorder={:?}, sink={:?})",
        config.provider,
        controller.state.auth_state,
        controller.state.permission_status,
        controller.state.recorder_state,
        services.snapshot_auth_state(),
    );
    Ok(())
}

fn resolve_data_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("FLO_WINDOWS_DATA_DIR") {
        return PathBuf::from(dir);
    }

    std::env::temp_dir().join("flo-windows")
}
