# P03 Auth Gate and OAuth Spec

## Requirement
Core app functionality is blocked unless ChatGPT OAuth login succeeds.

## Architecture
- `AuthService` protocol provides OAuth lifecycle.
- `ChatGPTOAuthService` concrete implementation.
- `AuthStore` publishes `AuthState` for route gating.

## Auth States
- `loggedOut`
- `authenticating`
- `loggedIn(session)`
- `authError(message)`

## Flow
1. App launches in `loggedOut` or previously persisted session.
2. If no valid session, show login window only.
3. Start OAuth through browser/session-based auth.
4. Handle callback URL.
5. Exchange code for tokens.
6. Persist tokens in keychain.
7. Unlock app routes.

## Token Policy
- Store access/refresh token only in keychain.
- Refresh proactively before expiry.
- Logout removes keychain artifacts and history linkage.

## Blocker Tracking
- Direct third-party ChatGPT OAuth may be externally constrained.
- Implement adapter with compile-time/runtime support for endpoint configuration.
- If unsupported: surface explicit blocker state.
