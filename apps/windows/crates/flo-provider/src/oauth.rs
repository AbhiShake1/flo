use std::collections::HashSet;

use flo_domain::UserSession;
use thiserror::Error;
use url::{form_urlencoded, Url};

use crate::config::OAuthConfiguration;

pub type OAuthCallbackResult<T> = Result<T, OAuthCallbackParseError>;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum OAuthCallbackParseError {
    #[error("authorization input is required")]
    EmptyInput,
    #[error("invalid callback url")]
    InvalidUrl,
    #[error("unsupported callback scheme: {0}")]
    UnsupportedScheme(String),
    #[error("oauth callback host not in allowlist: {0}")]
    HostNotAllowed(String),
    #[error("state missing")]
    MissingState,
    #[error("state mismatch")]
    StateMismatch,
    #[error("authorization code missing")]
    AuthorizationCodeMissing,
    #[error("originator mismatch")]
    OriginatorMismatch,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedOAuthCallback {
    pub code: String,
    pub state: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionRefreshDecision {
    SessionValid,
    RefreshRequired,
    ReauthenticateRequired,
}

pub fn evaluate_session_refresh(
    session: Option<&UserSession>,
    now_unix_ms: i64,
    refresh_skew_ms: i64,
) -> SessionRefreshDecision {
    let Some(session) = session else {
        return SessionRefreshDecision::ReauthenticateRequired;
    };

    let expires_in_ms = session.expires_at_unix_ms.saturating_sub(now_unix_ms);
    if expires_in_ms > refresh_skew_ms {
        return SessionRefreshDecision::SessionValid;
    }

    if session
        .refresh_token
        .as_deref()
        .is_some_and(|token| !token.trim().is_empty())
    {
        SessionRefreshDecision::RefreshRequired
    } else {
        SessionRefreshDecision::ReauthenticateRequired
    }
}

pub fn parse_oauth_callback_input(
    input: &str,
    expected_state: &str,
    config: &OAuthConfiguration,
) -> OAuthCallbackResult<ParsedOAuthCallback> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return Err(OAuthCallbackParseError::EmptyInput);
    }

    let parsed = if let Ok(url) = Url::parse(trimmed) {
        validate_url_host_and_scheme(&url, &config.allowed_hosts)?;
        parse_from_pairs(url.query_pairs(), expected_state, config)?
    } else if trimmed.contains('#') {
        let mut parts = trimmed.splitn(2, '#');
        let code = parts.next().unwrap_or_default().trim().to_string();
        let state = parts.next().unwrap_or_default().trim().to_string();
        ParsedOAuthCallback { code, state }
    } else if trimmed.contains("code=") {
        let query_only = format!("http://localhost?{trimmed}");
        let url = Url::parse(&query_only).map_err(|_| OAuthCallbackParseError::InvalidUrl)?;
        parse_from_pairs(url.query_pairs(), expected_state, config)?
    } else {
        return Err(OAuthCallbackParseError::InvalidUrl);
    };

    if parsed.state.is_empty() {
        return Err(OAuthCallbackParseError::MissingState);
    }
    if parsed.state != expected_state {
        return Err(OAuthCallbackParseError::StateMismatch);
    }
    if parsed.code.is_empty() {
        return Err(OAuthCallbackParseError::AuthorizationCodeMissing);
    }

    Ok(parsed)
}

fn validate_url_host_and_scheme(url: &Url, allowlist: &HashSet<String>) -> OAuthCallbackResult<()> {
    match url.scheme() {
        "http" | "https" => {}
        other => {
            return Err(OAuthCallbackParseError::UnsupportedScheme(
                other.to_string(),
            ))
        }
    }

    let host = url
        .host_str()
        .ok_or(OAuthCallbackParseError::InvalidUrl)?
        .to_ascii_lowercase();

    let normalized_allowlist: HashSet<String> = allowlist
        .iter()
        .map(|host| host.to_ascii_lowercase())
        .collect();
    if !normalized_allowlist.contains(&host) {
        return Err(OAuthCallbackParseError::HostNotAllowed(host));
    }

    Ok(())
}

fn parse_from_pairs(
    pairs: form_urlencoded::Parse<'_>,
    _expected_state: &str,
    config: &OAuthConfiguration,
) -> OAuthCallbackResult<ParsedOAuthCallback> {
    let mut code: Option<String> = None;
    let mut state: Option<String> = None;
    let mut originator: Option<String> = None;

    for (key, value) in pairs {
        match key.as_ref() {
            "code" => code = Some(value.to_string()),
            "state" => state = Some(value.to_string()),
            "originator" => originator = Some(value.to_string()),
            _ => {}
        }
    }

    if let Some(originator) = originator {
        if originator != config.originator {
            return Err(OAuthCallbackParseError::OriginatorMismatch);
        }
    }

    Ok(ParsedOAuthCallback {
        code: code.unwrap_or_default(),
        state: state.unwrap_or_default(),
    })
}

#[cfg(test)]
mod tests {
    use std::collections::{HashMap, HashSet};

    use flo_domain::UserSession;

    use super::{
        evaluate_session_refresh, parse_oauth_callback_input, OAuthCallbackParseError,
        SessionRefreshDecision,
    };
    use crate::config::FloConfiguration;

    fn oauth_config() -> crate::config::OAuthConfiguration {
        let mut env = HashMap::new();
        env.insert("FLO_OAUTH_ENABLED".to_string(), "true".to_string());
        env.insert(
            "FLO_OAUTH_ALLOWED_HOSTS".to_string(),
            "localhost,auth.openai.com".to_string(),
        );

        FloConfiguration::from_env_map(&env)
            .expect("valid config")
            .oauth
            .expect("oauth config")
    }

    #[test]
    fn parses_callback_url_when_host_is_allowed() {
        let config = oauth_config();
        let parsed = parse_oauth_callback_input(
            "http://localhost:1455/auth/callback?code=abc123&state=s1",
            "s1",
            &config,
        )
        .expect("valid callback");

        assert_eq!(parsed.code, "abc123");
        assert_eq!(parsed.state, "s1");
    }

    #[test]
    fn rejects_disallowed_host() {
        let mut config = oauth_config();
        config.allowed_hosts = HashSet::from(["localhost".to_string()]);

        let err = parse_oauth_callback_input(
            "https://evil.example.com/auth/callback?code=abc&state=s1",
            "s1",
            &config,
        )
        .expect_err("expected allowlist rejection");

        assert!(matches!(err, OAuthCallbackParseError::HostNotAllowed(_)));
    }

    #[test]
    fn rejects_state_mismatch() {
        let config = oauth_config();

        let err = parse_oauth_callback_input(
            "http://localhost:1455/auth/callback?code=abc123&state=s2",
            "s1",
            &config,
        )
        .expect_err("expected state mismatch");

        assert_eq!(err, OAuthCallbackParseError::StateMismatch);
    }

    #[test]
    fn supports_code_hash_state_input() {
        let config = oauth_config();

        let parsed = parse_oauth_callback_input("abc123#s1", "s1", &config)
            .expect("hash input should parse");

        assert_eq!(parsed.code, "abc123");
        assert_eq!(parsed.state, "s1");
    }

    #[test]
    fn rejects_missing_code() {
        let config = oauth_config();

        let err = parse_oauth_callback_input(
            "http://localhost:1455/auth/callback?state=s1",
            "s1",
            &config,
        )
        .expect_err("expected missing code");

        assert_eq!(err, OAuthCallbackParseError::AuthorizationCodeMissing);
    }

    #[test]
    fn rejects_empty_oauth_input() {
        let config = oauth_config();
        let err = parse_oauth_callback_input("  ", "s1", &config)
            .expect_err("empty callback input must fail");
        assert_eq!(err, OAuthCallbackParseError::EmptyInput);
    }

    #[test]
    fn rejects_unsupported_callback_scheme() {
        let config = oauth_config();
        let err = parse_oauth_callback_input(
            "ftp://localhost/auth/callback?code=a&state=s1",
            "s1",
            &config,
        )
        .expect_err("unsupported scheme should fail");
        assert!(matches!(err, OAuthCallbackParseError::UnsupportedScheme(_)));
    }

    #[test]
    fn rejects_originator_mismatch() {
        let config = oauth_config();
        let err = parse_oauth_callback_input(
            "http://localhost:1455/auth/callback?code=a&state=s1&originator=bad",
            "s1",
            &config,
        )
        .expect_err("originator mismatch should fail");
        assert_eq!(err, OAuthCallbackParseError::OriginatorMismatch);
    }

    #[test]
    fn refresh_decision_requires_refresh_for_expired_session_with_refresh_token() {
        let session = UserSession {
            access_token: "a".to_string(),
            refresh_token: Some("r".to_string()),
            token_type: "Bearer".to_string(),
            expires_at_unix_ms: 1_000,
            account_id: None,
        };

        let decision = evaluate_session_refresh(Some(&session), 1_500, 60_000);
        assert_eq!(decision, SessionRefreshDecision::RefreshRequired);
    }

    #[test]
    fn refresh_decision_requires_reauth_when_refresh_token_missing() {
        let session = UserSession {
            access_token: "a".to_string(),
            refresh_token: None,
            token_type: "Bearer".to_string(),
            expires_at_unix_ms: 1_000,
            account_id: None,
        };

        let decision = evaluate_session_refresh(Some(&session), 1_500, 60_000);
        assert_eq!(decision, SessionRefreshDecision::ReauthenticateRequired);
    }

    #[test]
    fn refresh_decision_stays_valid_when_not_near_expiry() {
        let session = UserSession {
            access_token: "a".to_string(),
            refresh_token: Some("r".to_string()),
            token_type: "Bearer".to_string(),
            expires_at_unix_ms: 200_000,
            account_id: None,
        };

        let decision = evaluate_session_refresh(Some(&session), 1_500, 60_000);
        assert_eq!(decision, SessionRefreshDecision::SessionValid);
    }
}
