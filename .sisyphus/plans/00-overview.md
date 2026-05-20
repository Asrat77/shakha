# Shakha Path A — SPA-First OAuth Broker

**Goal**: A headless OAuth broker gem for Rails APIs. Your React/Vue/Turbo frontend does a single redirect. Shakha handles the OAuth dance. You get back a session token. That's it.

## The Flow (React + Rails API)

```
1. React:   <a href="https://api.yourapp.com/auth/shakha/google/authorize?return_to=https://app.yourapp.com/login">
2. Shakha:  Redirects to accounts.google.com (PKCE, state, nonce — all handled)
3. Google:  Redirects to https://api.yourapp.com/auth/shakha/google/callback?code=...
4. Shakha:  Exchanges code, creates User + Session
5. Shakha:  Redirects to https://app.yourapp.com/login?token=abc123&expires_at=...
6. React:   Stores token, sends as Authorization: Bearer abc123
7. React:   GET https://api.yourapp.com/auth/shakha/session → { email, name, picture }
```

## What Ships

| Component | Purpose |
|---|---|
| `AuthController` (authorize, callback, destroy) | OAuth flow endpoints |
| `SessionController` (show, check) | Session introspection (JSON) |
| `ControllerHelpers` | `authenticate!`, `current_user` — cookie + bearer |
| `Providers::Google`, `Providers::GitHub` | Multi-provider from day one |
| `PKCEMixin` | PKCE security (fixed) |
| `RateLimiter` | Protect auth endpoints |
| `Config` | Minimal ENV vars |
| Generator | `rails generate shakha:install` |
| Views | Optional — nice sign-in page for Rails monoliths, ignored by SPAs |

## What Gets Cut

| Module | Reason |
|---|---|
| `JwtHandler` (ES256, JWKS, OIDC) | Session tokens are random strings. No JWT needed. |
| `Pairwise` module | Domain-scoped IDs — clever, nobody asked |
| `Middleware` (token verification) | `ControllerHelpers` handles this in-controller |
| `Auditable` | Broken, adds zero value |
| Standalone service mode | Embedded only. One Rails app = one Shakha instance. |

## Phases

1. [Phase 0: Bug Fixes](./01-phase-0-bugs.md) — 6 fatal bugs (unchanged)
2. [Phase 1: Security](./02-phase-1-security.md) — 4 security fixes (minor updates for SPA flow)
3. [Phase 2: Architecture](./03-phase-2-architecture.md) — Strip service infra, add SPA flow
4. [Phase 3: Multi-Provider](./04-phase-3-multi-provider.md) — Google + GitHub from the start
5. [Phase 4: Generator](./05-phase-4-generator.md) — `rails generate shakha:install`
6. [Phase 5: Testing](./06-phase-5-testing.md) — End-to-end OAuth + SPA token flow

## Success Criteria

- [ ] `rails generate shakha:install` on fresh Rails 7.1+ API app
- [ ] Full Google OAuth → redirect with token → Bearer auth works
- [ ] GitHub OAuth works the same way
- [ ] React app can: redirect → get token → call `/auth/shakha/session` → get user
- [ ] `current_user` works from Bearer token (React) AND cookie (Rails monolith)
- [ ] `authenticate!` returns `401 JSON` for API requests, `302 redirect` for HTML
- [ ] All 6 bugs from Phase 0 fixed with regression tests
- [ ] Rate limiter protects `/authorize` and `/callback`
