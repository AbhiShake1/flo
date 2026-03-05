use std::collections::{HashMap, HashSet};

use flo_domain::ProviderRoutingOverrides;

use crate::config::FloConfiguration;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EffectiveRoutingPolicy {
    pub provider_order: Vec<String>,
    pub allow_cross_provider_fallback: bool,
    pub max_attempts: u32,
    pub failure_threshold: u32,
    pub cooldown_seconds: u32,
    pub allowed_providers: Option<HashSet<String>>,
    pub rewrite_models_by_provider: Option<HashMap<String, String>>,
    pub rewrite_models_by_provider_credential_index:
        Option<HashMap<String, HashMap<String, String>>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoutingAttempt {
    pub attempt_number: u32,
    pub provider: String,
    pub credential_index: usize,
}

pub fn merge_routing_overrides(
    base: &FloConfiguration,
    overrides: &ProviderRoutingOverrides,
) -> EffectiveRoutingPolicy {
    let override_order = normalize_provider_list(&overrides.provider_order);
    let mut provider_order = if override_order.is_empty() {
        normalize_provider_list(&base.provider_order)
    } else {
        override_order
    };
    if provider_order.is_empty() {
        provider_order.push(normalize_provider_id(&base.provider));
    }

    let allowed_providers = if let Some(raw) = overrides.allowed_providers.as_ref() {
        normalize_optional_provider_set(raw.iter().map(String::as_str))
    } else if let Some(raw) = base.failover_policy.allowed_providers.as_ref() {
        normalize_optional_provider_set(raw.iter().map(String::as_str))
    } else {
        None
    };

    if let Some(allowed) = &allowed_providers {
        provider_order.retain(|provider| allowed.contains(provider));
        if provider_order.is_empty() {
            provider_order = normalize_provider_list(&base.provider_order)
                .into_iter()
                .filter(|provider| allowed.contains(provider))
                .collect();
        }
    }

    if provider_order.is_empty() {
        provider_order.push(normalize_provider_id(&base.provider));
    }

    EffectiveRoutingPolicy {
        provider_order,
        allow_cross_provider_fallback: overrides
            .allow_cross_provider_fallback
            .unwrap_or(base.failover_policy.allow_cross_provider_fallback),
        max_attempts: overrides
            .max_attempts
            .unwrap_or(base.failover_policy.max_attempts)
            .max(1),
        failure_threshold: overrides
            .failure_threshold
            .unwrap_or(base.failover_policy.failure_threshold)
            .max(1),
        cooldown_seconds: overrides
            .cooldown_seconds
            .unwrap_or(base.failover_policy.cooldown_seconds),
        allowed_providers,
        rewrite_models_by_provider: normalize_model_overrides(
            overrides.rewrite_models_by_provider.as_ref(),
        ),
        rewrite_models_by_provider_credential_index: normalize_credential_model_overrides(
            overrides
                .rewrite_models_by_provider_credential_index
                .as_ref(),
        ),
    }
}

pub fn build_attempt_plan(
    policy: &EffectiveRoutingPolicy,
    credential_pool: &HashMap<String, Vec<String>>,
) -> Vec<RoutingAttempt> {
    let providers: Vec<String> = if policy.allow_cross_provider_fallback {
        policy.provider_order.clone()
    } else {
        policy.provider_order.first().cloned().into_iter().collect()
    };

    let mut base_sequence = Vec::new();
    for provider in providers {
        let credentials = credential_pool.get(&provider).cloned().unwrap_or_default();
        if credentials.is_empty() {
            base_sequence.push((provider, 0_usize));
            continue;
        }

        for index in 0..credentials.len() {
            base_sequence.push((provider.clone(), index));
        }
    }

    if base_sequence.is_empty() {
        return Vec::new();
    }

    let mut attempts = Vec::with_capacity(policy.max_attempts as usize);
    let mut next_attempt_number = 1_u32;

    while attempts.len() < policy.max_attempts as usize {
        for (provider, credential_index) in &base_sequence {
            if attempts.len() >= policy.max_attempts as usize {
                break;
            }
            attempts.push(RoutingAttempt {
                attempt_number: next_attempt_number,
                provider: provider.clone(),
                credential_index: *credential_index,
            });
            next_attempt_number += 1;
        }
    }

    attempts
}

fn normalize_provider_id(value: &str) -> String {
    value.trim().to_ascii_lowercase()
}

fn normalize_provider_list(raw: &[String]) -> Vec<String> {
    let mut out = Vec::new();
    for value in raw {
        let normalized = normalize_provider_id(value);
        if normalized.is_empty() || out.contains(&normalized) {
            continue;
        }
        out.push(normalized);
    }
    out
}

fn normalize_optional_provider_set<'a, I>(raw: I) -> Option<HashSet<String>>
where
    I: Iterator<Item = &'a str>,
{
    let set = raw
        .map(normalize_provider_id)
        .filter(|value| !value.is_empty())
        .collect::<HashSet<_>>();
    if set.is_empty() {
        None
    } else {
        Some(set)
    }
}

fn normalize_model_overrides(
    raw: Option<&HashMap<String, String>>,
) -> Option<HashMap<String, String>> {
    raw.and_then(|overrides| {
        let mut normalized = HashMap::new();
        for (provider, model) in overrides {
            let provider = normalize_provider_id(provider);
            let model = model.trim();
            if provider.is_empty() || model.is_empty() {
                continue;
            }
            normalized.insert(provider, model.to_string());
        }
        if normalized.is_empty() {
            None
        } else {
            Some(normalized)
        }
    })
}

fn normalize_credential_model_overrides(
    raw: Option<&HashMap<String, HashMap<String, String>>>,
) -> Option<HashMap<String, HashMap<String, String>>> {
    raw.and_then(|provider_map| {
        let mut normalized = HashMap::new();
        for (provider, index_map) in provider_map {
            let provider = normalize_provider_id(provider);
            if provider.is_empty() {
                continue;
            }

            let mut normalized_indexes = HashMap::new();
            for (index, model) in index_map {
                let model = model.trim();
                if index.parse::<usize>().ok().is_none() || model.is_empty() {
                    continue;
                }
                normalized_indexes.insert(index.clone(), model.to_string());
            }

            if !normalized_indexes.is_empty() {
                normalized.insert(provider, normalized_indexes);
            }
        }

        if normalized.is_empty() {
            None
        } else {
            Some(normalized)
        }
    })
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use flo_domain::ProviderRoutingOverrides;

    use super::{build_attempt_plan, merge_routing_overrides};
    use crate::config::FloConfiguration;

    #[test]
    fn override_fields_take_precedence_over_base_policy() {
        let base = FloConfiguration::from_env_map(&HashMap::new()).expect("valid base config");
        let overrides = ProviderRoutingOverrides {
            provider_order: vec!["gemini".to_string(), "openai".to_string()],
            allow_cross_provider_fallback: Some(false),
            max_attempts: Some(3),
            failure_threshold: Some(1),
            cooldown_seconds: Some(10),
            allowed_providers: Some(vec!["gemini".to_string()]),
            rewrite_models_by_provider: None,
            rewrite_models_by_provider_credential_index: None,
        };

        let merged = merge_routing_overrides(&base, &overrides);
        assert_eq!(merged.provider_order, vec!["gemini".to_string()]);
        assert!(!merged.allow_cross_provider_fallback);
        assert_eq!(merged.max_attempts, 3);
        assert_eq!(merged.failure_threshold, 1);
        assert_eq!(merged.cooldown_seconds, 10);
    }

    #[test]
    fn attempt_plan_is_deterministic_and_respects_max_attempts() {
        let base = FloConfiguration::from_env_map(&HashMap::new()).expect("valid base config");
        let overrides = ProviderRoutingOverrides {
            provider_order: vec!["openai".to_string(), "gemini".to_string()],
            allow_cross_provider_fallback: Some(true),
            max_attempts: Some(5),
            failure_threshold: None,
            cooldown_seconds: None,
            allowed_providers: None,
            rewrite_models_by_provider: None,
            rewrite_models_by_provider_credential_index: None,
        };

        let merged = merge_routing_overrides(&base, &overrides);
        let credentials = HashMap::from([
            (
                "openai".to_string(),
                vec!["o-1".to_string(), "o-2".to_string()],
            ),
            ("gemini".to_string(), vec!["g-1".to_string()]),
        ]);

        let plan = build_attempt_plan(&merged, &credentials);
        let sequence = plan
            .iter()
            .map(|attempt| (attempt.provider.as_str(), attempt.credential_index))
            .collect::<Vec<_>>();

        assert_eq!(plan.len(), 5);
        assert_eq!(
            sequence,
            vec![
                ("openai", 0),
                ("openai", 1),
                ("gemini", 0),
                ("openai", 0),
                ("openai", 1),
            ]
        );
    }

    #[test]
    fn cross_provider_disabled_restricts_attempts_to_first_provider() {
        let base = FloConfiguration::from_env_map(&HashMap::new()).expect("valid base config");
        let overrides = ProviderRoutingOverrides {
            provider_order: vec!["openai".to_string(), "gemini".to_string()],
            allow_cross_provider_fallback: Some(false),
            max_attempts: Some(4),
            failure_threshold: None,
            cooldown_seconds: None,
            allowed_providers: None,
            rewrite_models_by_provider: None,
            rewrite_models_by_provider_credential_index: None,
        };

        let merged = merge_routing_overrides(&base, &overrides);
        let credentials = HashMap::from([
            (
                "openai".to_string(),
                vec!["o-1".to_string(), "o-2".to_string()],
            ),
            ("gemini".to_string(), vec!["g-1".to_string()]),
        ]);

        let plan = build_attempt_plan(&merged, &credentials);
        assert!(plan.iter().all(|attempt| attempt.provider == "openai"));
    }
}
