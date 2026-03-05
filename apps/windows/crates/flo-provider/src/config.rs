use std::collections::{HashMap, HashSet};

type Result<T> = std::result::Result<T, ConfigError>;

use serde::{Deserialize, Serialize};
use thiserror::Error;
use url::Url;

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("invalid url for {key}: {value}")]
    InvalidUrl { key: String, value: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderCapabilities {
    pub transcription: bool,
    pub tts: bool,
    pub rewrite: bool,
}

impl Default for ProviderCapabilities {
    fn default() -> Self {
        Self {
            transcription: true,
            tts: true,
            rewrite: true,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderRuntimeConfiguration {
    pub provider: String,
    pub transcription_url: Url,
    pub tts_url: Url,
    pub rewrite_url: Url,
    pub transcription_model: String,
    pub tts_model: String,
    pub rewrite_model: String,
    pub tts_voice: String,
    pub tts_speed: f32,
    pub capabilities: ProviderCapabilities,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OAuthConfiguration {
    pub authorize_url: Url,
    pub token_url: Url,
    pub client_id: String,
    pub client_secret: Option<String>,
    pub redirect_uri: String,
    pub scopes: String,
    pub originator: String,
    pub allowed_hosts: HashSet<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProviderFailoverPolicy {
    pub allow_cross_provider_fallback: bool,
    pub max_attempts: u32,
    pub failure_threshold: u32,
    pub cooldown_seconds: u32,
    pub allowed_providers: Option<HashSet<String>>,
}

impl Default for ProviderFailoverPolicy {
    fn default() -> Self {
        Self {
            allow_cross_provider_fallback: true,
            max_attempts: 8,
            failure_threshold: 2,
            cooldown_seconds: 60,
            allowed_providers: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FeatureFlags {
    pub enable_global_hotkeys: bool,
    pub enable_dictation: bool,
    pub enable_read_aloud: bool,
}

impl Default for FeatureFlags {
    fn default() -> Self {
        Self {
            enable_global_hotkeys: true,
            enable_dictation: true,
            enable_read_aloud: true,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FloConfiguration {
    pub provider: String,
    pub provider_order: Vec<String>,
    pub provider_configurations: HashMap<String, ProviderRuntimeConfiguration>,
    pub provider_credential_pool: HashMap<String, Vec<String>>,
    pub max_tts_characters_per_chunk: usize,
    pub retain_audio_debug_artifacts: bool,
    pub host_allowlist: HashSet<String>,
    pub feature_flags: FeatureFlags,
    pub manual_update_url: Option<Url>,
    pub oauth: Option<OAuthConfiguration>,
    pub failover_policy: ProviderFailoverPolicy,
}

impl FloConfiguration {
    pub fn from_process_env() -> Result<Self> {
        let map = std::env::vars().collect::<HashMap<_, _>>();
        Self::from_env_map(&map)
    }

    pub fn from_env_map(env: &HashMap<String, String>) -> Result<Self> {
        let provider = env
            .get("FLO_AI_PROVIDER")
            .map(|v| normalize_provider(v))
            .unwrap_or_else(|| "openai".to_string());

        let mut provider_order = parse_csv_list(env.get("FLO_PROVIDER_ORDER"));
        if provider_order.is_empty() {
            provider_order.push(provider.clone());
        }
        if !provider_order.iter().any(|it| it == &provider) {
            provider_order.insert(0, provider.clone());
        }
        provider_order = dedupe_preserve_order(provider_order);

        let mut provider_credential_pool = HashMap::new();
        if let Some(openai) = non_empty(env.get("FLO_OPENAI_API_KEY")) {
            provider_credential_pool.insert("openai".to_string(), vec![openai.to_string()]);
        }
        if let Some(gemini) = non_empty(env.get("FLO_GEMINI_API_KEY")) {
            provider_credential_pool.insert("gemini".to_string(), vec![gemini.to_string()]);
        }

        for candidate in &provider_order {
            let list_key = format!("FLO_{}_API_KEYS", env_token(candidate));
            let values = parse_csv_list(env.get(&list_key));
            if !values.is_empty() {
                provider_credential_pool
                    .entry(candidate.clone())
                    .or_insert_with(Vec::new)
                    .extend(values);
            }
        }

        for values in provider_credential_pool.values_mut() {
            *values = dedupe_preserve_order(values.clone());
        }

        let active = ProviderRuntimeConfiguration {
            provider: provider.clone(),
            transcription_url: parse_url(
                env,
                "FLO_TRANSCRIPTION_URL",
                "https://api.openai.com/v1/audio/transcriptions",
            )?,
            tts_url: parse_url(env, "FLO_TTS_URL", "https://api.openai.com/v1/audio/speech")?,
            rewrite_url: parse_url(
                env,
                "FLO_REWRITE_URL",
                "https://api.openai.com/v1/responses",
            )?,
            transcription_model: env
                .get("FLO_TRANSCRIPTION_MODEL")
                .cloned()
                .unwrap_or_else(|| "gpt-4o-mini-transcribe".to_string()),
            tts_model: env
                .get("FLO_TTS_MODEL")
                .cloned()
                .unwrap_or_else(|| "gpt-4o-mini-tts".to_string()),
            rewrite_model: env
                .get("FLO_REWRITE_MODEL")
                .cloned()
                .unwrap_or_else(|| "gpt-4.1-mini".to_string()),
            tts_voice: env
                .get("FLO_TTS_VOICE")
                .cloned()
                .unwrap_or_else(|| "alloy".to_string()),
            tts_speed: env
                .get("FLO_TTS_SPEED")
                .and_then(|v| v.parse::<f32>().ok())
                .unwrap_or(1.0),
            capabilities: ProviderCapabilities::default(),
        };

        let provider_configurations = HashMap::from([(provider.clone(), active)]);
        let host_allowlist = parse_csv_list(env.get("FLO_HOST_ALLOWLIST"))
            .into_iter()
            .collect::<HashSet<_>>();

        let feature_flags = FeatureFlags {
            enable_global_hotkeys: parse_bool(env.get("FLO_ENABLE_GLOBAL_HOTKEYS"), true),
            enable_dictation: parse_bool(env.get("FLO_ENABLE_DICTATION"), true),
            enable_read_aloud: parse_bool(env.get("FLO_ENABLE_READ_ALOUD"), true),
        };

        let manual_update_url = env
            .get("FLO_MANUAL_UPDATE_URL")
            .and_then(|raw| Url::parse(raw).ok());

        let oauth = build_oauth_configuration(env)?;

        let failover_policy = ProviderFailoverPolicy {
            allow_cross_provider_fallback: parse_bool(
                env.get("FLO_FAILOVER_ALLOW_CROSS_PROVIDER_FALLBACK"),
                true,
            ),
            max_attempts: env
                .get("FLO_FAILOVER_MAX_ATTEMPTS")
                .and_then(|v| v.parse::<u32>().ok())
                .unwrap_or(8)
                .max(1),
            failure_threshold: env
                .get("FLO_FAILOVER_FAILURE_THRESHOLD")
                .and_then(|v| v.parse::<u32>().ok())
                .unwrap_or(2)
                .max(1),
            cooldown_seconds: env
                .get("FLO_FAILOVER_COOLDOWN_SECONDS")
                .and_then(|v| v.parse::<u32>().ok())
                .unwrap_or(60),
            allowed_providers: {
                let parsed = parse_csv_list(env.get("FLO_FAILOVER_ALLOWED_PROVIDERS"));
                if parsed.is_empty() {
                    None
                } else {
                    Some(parsed.into_iter().collect())
                }
            },
        };

        Ok(Self {
            provider,
            provider_order,
            provider_configurations,
            provider_credential_pool,
            max_tts_characters_per_chunk: env
                .get("FLO_MAX_TTS_CHARACTERS_PER_CHUNK")
                .and_then(|v| v.parse::<usize>().ok())
                .unwrap_or(2_000),
            retain_audio_debug_artifacts: parse_bool(
                env.get("FLO_RETAIN_AUDIO_DEBUG_ARTIFACTS"),
                false,
            ),
            host_allowlist,
            feature_flags,
            manual_update_url,
            oauth,
            failover_policy,
        })
    }

    pub fn credentials_for(&self, provider: &str) -> &[String] {
        self.provider_credential_pool
            .get(provider)
            .map(Vec::as_slice)
            .unwrap_or(&[])
    }

    pub fn runtime_configuration_for(
        &self,
        provider: &str,
    ) -> Option<&ProviderRuntimeConfiguration> {
        self.provider_configurations.get(provider)
    }
}

fn parse_url(env: &HashMap<String, String>, key: &str, default: &str) -> Result<Url> {
    let raw = env.get(key).map(String::as_str).unwrap_or(default);
    Url::parse(raw).map_err(|_| ConfigError::InvalidUrl {
        key: key.to_string(),
        value: raw.to_string(),
    })
}

fn parse_bool(value: Option<&String>, default: bool) -> bool {
    match value.map(|v| v.trim().to_ascii_lowercase()) {
        Some(v) if v == "1" || v == "true" || v == "yes" || v == "on" => true,
        Some(v) if v == "0" || v == "false" || v == "no" || v == "off" => false,
        _ => default,
    }
}

fn parse_csv_list(value: Option<&String>) -> Vec<String> {
    value
        .map(|v| {
            v.split(',')
                .map(str::trim)
                .filter(|it| !it.is_empty())
                .map(normalize_provider)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn normalize_provider(value: &str) -> String {
    value.trim().to_ascii_lowercase()
}

fn non_empty(value: Option<&String>) -> Option<&str> {
    match value.map(String::as_str).map(str::trim) {
        Some("") | None => None,
        Some(v) => Some(v),
    }
}

fn dedupe_preserve_order(values: Vec<String>) -> Vec<String> {
    let mut out = Vec::new();
    for value in values {
        if !out.contains(&value) {
            out.push(value);
        }
    }
    out
}

fn env_token(provider: &str) -> String {
    provider
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() {
                ch.to_ascii_uppercase()
            } else {
                '_'
            }
        })
        .collect()
}

fn build_oauth_configuration(env: &HashMap<String, String>) -> Result<Option<OAuthConfiguration>> {
    let enabled = parse_bool(env.get("FLO_OAUTH_ENABLED"), false);
    if !enabled {
        return Ok(None);
    }

    let authorize_url = parse_url(
        env,
        "FLO_OAUTH_AUTHORIZE_URL",
        "https://auth.openai.com/oauth/authorize",
    )?;
    let token_url = parse_url(
        env,
        "FLO_OAUTH_TOKEN_URL",
        "https://auth.openai.com/oauth/token",
    )?;
    let client_id = env
        .get("FLO_OAUTH_CLIENT_ID")
        .cloned()
        .unwrap_or_else(|| "app_EMoamEEZ73f0CkXaXp7hrann".to_string());
    let redirect_uri = env
        .get("FLO_OAUTH_REDIRECT_URI")
        .cloned()
        .unwrap_or_else(|| "http://localhost:1455/auth/callback".to_string());
    let scopes = env
        .get("FLO_OAUTH_SCOPES")
        .cloned()
        .unwrap_or_else(|| "openid profile email offline_access".to_string());
    let originator = env
        .get("FLO_OAUTH_ORIGINATOR")
        .cloned()
        .unwrap_or_else(|| "pi".to_string());

    let allowed_hosts = {
        let parsed = parse_csv_list(env.get("FLO_OAUTH_ALLOWED_HOSTS"));
        if parsed.is_empty() {
            let mut set = HashSet::new();
            if let Some(host) = authorize_url.host_str() {
                set.insert(host.to_string());
            }
            if let Some(host) = token_url.host_str() {
                set.insert(host.to_string());
            }
            if let Ok(redirect_url) = Url::parse(&redirect_uri) {
                if let Some(host) = redirect_url.host_str() {
                    set.insert(host.to_string());
                }
            }
            set
        } else {
            parsed.into_iter().collect()
        }
    };

    Ok(Some(OAuthConfiguration {
        authorize_url,
        token_url,
        client_id,
        client_secret: env.get("FLO_OAUTH_CLIENT_SECRET").cloned(),
        redirect_uri,
        scopes,
        originator,
        allowed_hosts,
    }))
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use super::FloConfiguration;

    #[test]
    fn defaults_to_openai_when_provider_missing() {
        let env = HashMap::new();
        let config = FloConfiguration::from_env_map(&env).expect("valid config");
        assert_eq!(config.provider, "openai");
        assert_eq!(config.provider_order, vec!["openai"]);
    }

    #[test]
    fn reads_provider_order_and_credentials() {
        let mut env = HashMap::new();
        env.insert("FLO_AI_PROVIDER".to_string(), "gemini".to_string());
        env.insert(
            "FLO_PROVIDER_ORDER".to_string(),
            "gemini,openai,openai".to_string(),
        );
        env.insert("FLO_OPENAI_API_KEY".to_string(), "k-openai".to_string());
        env.insert("FLO_GEMINI_API_KEYS".to_string(), "g-1,g-2,g-2".to_string());

        let config = FloConfiguration::from_env_map(&env).expect("valid config");

        assert_eq!(config.provider, "gemini");
        assert_eq!(config.provider_order, vec!["gemini", "openai"]);
        assert_eq!(
            config.credentials_for("gemini"),
            &["g-1".to_string(), "g-2".to_string()]
        );
        assert_eq!(config.credentials_for("openai"), &["k-openai".to_string()]);
    }
}
