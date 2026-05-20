# Shakha Path A — SPA-First OAuth Broker

**Goal**: A headless OAuth broker gem for Rails APIs. Your React/Vue frontend does a single redirect. Shakha handles the OAuth dance. You get back a session token. Backend dev tells frontend dev 3 URLs. Done.

## The Flow

```
1. React:   <a href="https://api.yourapp.com/auth/shakha/google?return_to=https://app.yourapp.com/callback">
2. Shakha:  Redirects to accounts.google.com (PKCE, state, nonce — all handled)
3. Google:  Redirects to https://api.yourapp.com/auth/shakha/google/callback?code=...
4. Shakha:  Exchanges code, creates User + Session
5. Shakha:  Redirects to https://app.yourapp.com/callback?token=abc123&expires_at=...
6. React:   Stores token, sends as Authorization: Bearer abc123
7. React:   GET https://api.yourapp.com/auth/shakha/session → { email, name, picture }
```

## What the backend dev tells the frontend dev

> "API is at `https://api.yourapp.com`.
> Sign in: `https://api.yourapp.com/auth/shakha/google`
> Session: `GET https://api.yourapp.com/auth/shakha/session` with `Authorization: Bearer <token>`
> Sign out: `DELETE https://api.yourapp.com/auth/shakha/sign_out`"

No Shakha imports. No discovery fetches. No SDK. Just URLs.

## API Reference

| Purpose | Method | URL |
|---|---|---|
| Sign in with Google | GET | `/auth/shakha/google` |
| Sign in with GitHub | GET | `/auth/shakha/github` |
| Get current user | GET | `/auth/shakha/session` |
| Check session valid | GET | `/auth/shakha/session/check` |
| Sign out | DELETE | `/auth/shakha/sign_out` |

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

## What Got Cut

| Module | Reason |
|---|---|
| JwtHandler (ES256/JWKS/OIDC) | Session tokens are random strings |
| Pairwise | Domain-scoped IDs — nobody asked |
| Middleware | Handled in-controller |
| Auditable | Broken |
| Standalone service mode | Embedded only |
| `/:provider/authorize` | `/:provider` is cleaner |

## Phases

1. [Phase 0: Bug Fixes](./01-phase-0-bugs.md) — ✅ Done
2. [Phase 1: Security](./02-phase-1-security.md) — ✅ Done
3. [Phase 2: Architecture](./03-phase-2-architecture.md) — ✅ Done
4. [Phase 3: Multi-Provider](./04-phase-3-multi-provider.md) — ✅ Done
5. [Phase 4: Generator](./05-phase-4-generator.md) — `rails generate shakha:install`
6. [Phase 5: Testing](./06-phase-5-testing.md) — End-to-end

## Success Criteria

- [ ] `rails generate shakha:install` on fresh Rails 7.1+ API app
- [ ] Full Google OAuth → redirect with token → Bearer auth works
- [ ] GitHub OAuth works the same way
- [ ] React app can: redirect → get token → call `/auth/shakha/session` → get user
- [ ] `current_user` works from Bearer token (React) AND cookie (Rails monolith)
- [ ] `authenticate!` returns `401 JSON` for API, `302 redirect` for HTML
- [ ] Frontend dev writes zero Shakha-specific code
