# Shakha End-to-End Test Results

**Date**: 2026-05-20
**Gem version**: 0.5.0
**Rails version**: 8.1.3 (API mode)
**Ruby version**: 3.4.2

## Test Setup

- Rails API app at `test_shakha_app/`
- Shakha gem loaded via `path: "../shakha"`
- SQLite database
- CORS enabled (origins: *)
- Providers: Google + GitHub (credentials not set — only session management tested)

## Test Results

### 1. Public endpoint (no auth)
```
GET /public → 200 {"message":"This is public. No auth needed."}
```
✅ Works. Controllers without `before_action :authenticate!` are open.

### 2. Protected endpoint (no auth)
```
GET /me → 401 {"error":"Authentication required"}
```
✅ Works. `authenticate!` properly blocks unauthenticated API requests.

### 3. Session endpoint (with Bearer token)
```
GET /auth/shakha/session + Authorization: Bearer <token>
→ 200 {"user":{"id":1,"email":"test@example.com","name":"Test User",...}}
```
✅ Works. Returns user info and session expiry.

### 4. Session check (with Bearer token)
```
GET /auth/shakha/session/check + Authorization: Bearer <token>
→ 200 {"status":"active"}
```
✅ Works. Lightweight session validation.

### 5. Protected endpoint (with Bearer token)
```
GET /me + Authorization: Bearer <token>
→ 200 {"id":1,"email":"test@example.com","name":"Test User","provider":"google"}
```
✅ Works. `current_user` available in app controllers.

### 6. Sign out
```
DELETE /auth/shakha/sign_out + Authorization: Bearer <token>
→ 200 {"status":"signed_out"}
```
✅ Works. Session destroyed, token invalidated.

### 7. Session after sign out
```
GET /auth/shakha/session + Authorization: Bearer <revoked token>
→ 401 {"error":"Authentication required"}
```
✅ Works. Revoked tokens properly rejected.

## Bugs Found and Fixed During Testing

| Bug | Fix |
|---|---|
| Rate limiter crashed SessionController (missing `authorize` action) | Move RateLimiter to AuthController only |
| `respond_to` block not available in API mode | Replace with if/else on `request.format.json?` |
| `helper_method` not available in API controllers | Guard with `respond_to?(:helper_method)` |
| `shakha.new_auth_path` engine helper unavailable in app controllers | Use direct URL `/auth/shakha?return_to=...` |
| Route collision: `:provider` matched "session" | Move static routes before dynamic `:provider` |
| `cookies.encrypted` not available in API mode | Guard with `respond_to?(:cookies)` |

## What Was NOT Tested (requires Google Cloud Console)

- Full Google OAuth redirect flow
- PKCE code_verifier exchange with Google
- Nonce verification against real Google ID tokens
- GitHub OAuth flow
- Token-in-URL redirect to SPA
- Rate limiting (disabled by default)

## Generator Test

```
$ bin/rails generate shakha:install
```

✅ Migration created (`db/migrate/..._create_shakha_tables.rb`)
✅ Initializer created (`config/initializers/shakha.rb`)
✅ Post-install message prints correct URLs
✅ `bin/rails db:migrate` creates all 3 tables

## Route Test

| Route | Method | Status |
|---|---|---|
| `/auth/shakha/google` | GET | ✅ (redirects to Google) |
| `/auth/shakha/session` | GET | ✅ |
| `/auth/shakha/session/check` | GET | ✅ |
| `/auth/shakha/sign_out` | DELETE | ✅ |
| `/auth/shakha/error` | GET | ✅ |

## Conclusion

The Shakha gem works correctly in a Rails 8.1 API-mode application. All session management endpoints function properly. The gem handles cookies gracefully in API mode (falls back to Bearer-only when cookies unavailable). The install generator produces correct output.
