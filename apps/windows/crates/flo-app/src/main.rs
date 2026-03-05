use anyhow::Result;
use flo_core::{
    capabilities::PlatformCapabilities,
    controller::{FloCommand, FloController},
};
use flo_provider::config::FloConfiguration;

#[cfg(test)]
mod acceptance;

fn main() -> Result<()> {
    let config = FloConfiguration::from_process_env()?;
    let mut controller = FloController::new();
    let capabilities = PlatformCapabilities::win32_default();

    let bootstrap_effects = controller.dispatch(FloCommand::Bootstrap, &capabilities);

    println!(
        "flo-app scaffold initialized (provider={}, effects={:?})",
        config.provider, bootstrap_effects
    );
    Ok(())
}
