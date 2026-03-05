use std::collections::HashMap;

use flo_domain::ProviderRoutingOverrides;
use flo_provider::{
    config::FloConfiguration,
    oauth::parse_oauth_callback_input,
    routing::{build_attempt_plan, merge_routing_overrides},
};

#[test]
fn oauth_callback_validation_and_allowlist_flow() {
    let mut env = HashMap::new();
    env.insert("FLO_OAUTH_ENABLED".to_string(), "true".to_string());
    env.insert(
        "FLO_OAUTH_ALLOWED_HOSTS".to_string(),
        "localhost,auth.openai.com".to_string(),
    );
    env.insert("FLO_OAUTH_ORIGINATOR".to_string(), "pi".to_string());

    let config = FloConfiguration::from_env_map(&env)
        .expect("valid config")
        .oauth
        .expect("oauth enabled");

    let parsed = parse_oauth_callback_input(
        "http://localhost:1455/auth/callback?code=ok123&state=st-1&originator=pi",
        "st-1",
        &config,
    )
    .expect("callback should parse");

    assert_eq!(parsed.code, "ok123");
    assert_eq!(parsed.state, "st-1");
}

#[test]
fn routing_override_precedence_matches_contract() {
    let mut env = HashMap::new();
    env.insert("FLO_AI_PROVIDER".to_string(), "openai".to_string());
    env.insert(
        "FLO_PROVIDER_ORDER".to_string(),
        "openai,gemini".to_string(),
    );
    env.insert("FLO_FAILOVER_MAX_ATTEMPTS".to_string(), "9".to_string());

    let base = FloConfiguration::from_env_map(&env).expect("valid base config");
    let overrides = ProviderRoutingOverrides {
        provider_order: vec!["gemini".to_string(), "openai".to_string()],
        allow_cross_provider_fallback: Some(false),
        max_attempts: Some(3),
        failure_threshold: Some(2),
        cooldown_seconds: Some(5),
        allowed_providers: Some(vec!["gemini".to_string()]),
        rewrite_models_by_provider: None,
        rewrite_models_by_provider_credential_index: None,
    };

    let merged = merge_routing_overrides(&base, &overrides);

    assert_eq!(merged.provider_order, vec!["gemini"]);
    assert_eq!(merged.max_attempts, 3);
    assert!(!merged.allow_cross_provider_fallback);
}

#[test]
fn failover_attempt_plan_is_deterministic_integration() {
    let base = FloConfiguration::from_env_map(&HashMap::new()).expect("valid base config");

    let overrides = ProviderRoutingOverrides {
        provider_order: vec!["openai".to_string(), "gemini".to_string()],
        allow_cross_provider_fallback: Some(true),
        max_attempts: Some(6),
        failure_threshold: Some(2),
        cooldown_seconds: Some(60),
        allowed_providers: None,
        rewrite_models_by_provider: None,
        rewrite_models_by_provider_credential_index: None,
    };

    let merged = merge_routing_overrides(&base, &overrides);
    let credentials = HashMap::from([
        (
            "openai".to_string(),
            vec!["oa-1".to_string(), "oa-2".to_string()],
        ),
        (
            "gemini".to_string(),
            vec!["gm-1".to_string(), "gm-2".to_string()],
        ),
    ]);

    let plan = build_attempt_plan(&merged, &credentials);
    let compact = plan
        .iter()
        .map(|attempt| {
            (
                attempt.attempt_number,
                attempt.provider.as_str(),
                attempt.credential_index,
            )
        })
        .collect::<Vec<_>>();

    assert_eq!(
        compact,
        vec![
            (1, "openai", 0),
            (2, "openai", 1),
            (3, "gemini", 0),
            (4, "gemini", 1),
            (5, "openai", 0),
            (6, "openai", 1),
        ]
    );
}
