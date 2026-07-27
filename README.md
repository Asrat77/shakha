# Shakha

**SPA-first OAuth for Rails. One redirect. One token. Done.**

[![CI](https://github.com/Asrat77/shakha/actions/workflows/ci.yml/badge.svg)](https://github.com/Asrat77/shakha/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/shakha.svg)](https://rubygems.org/gems/shakha)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)

Shakha is a headless OAuth broker engine for Rails APIs and monoliths. Your
frontend does a single redirect; Shakha runs the OAuth dance — PKCE, `state`,
and (for Google) `nonce` — against Google or GitHub, stores a revocable
database-backed session, and hands your frontend a session token it uses as a
cookie or `Authorization: Bearer` header.

No JWTs to issue or rotate. No Redis. No frontend SDK.

## The flow

```
1. Frontend:  window.location = "https://api.example.com/auth/shakha/google?return_to=https://app.example.com/login"
2. Shakha:    redirects to accounts.google.com (PKCE, state, nonce — handled)
3. Google:    redirects back to /auth/shakha/google/callback?code=...
4. Shakha:    exchanges the code, verifies the ID token, creates the User + Session
5. Shakha:    redirects to https://app.example.com/login?code=<one-time-code>
6. Frontend:  POST /auth/shakha/session/exchange { code }  ->  { token, expires_at }
7. Frontend:  send "Authorization: Bearer <token>" on every API call
```

The one-time code in step 5 keeps the session token out of the redirect URL (and
therefore out of browser history, `Referer` headers, and logs). It is single-use
and expires in 60 seconds.

## Installation

Add the gem:

```ruby
gem "shakha"
```

Mount the engine in `config/routes.rb`:

```ruby
mount Shakha::Engine => "/auth/shakha"
```

Run the installer and migrate:

```bash
bin/rails generate shakha:install
bin/rails db:migrate
```

The generator writes a migration and `config/initializers/shakha.rb`, includes
`Shakha::ControllerHelpers` in your `ApplicationController`, and — for API-only
apps — adds the cookie middleware Shakha needs.

### Configuration

Set these environment variables (the generated initializer reads them):

| Variable | Required | Purpose |
|---|---|---|
| `APP_ORIGIN` | yes | Your Rails app's origin, e.g. `https://api.example.com` |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | for Google | Google OAuth credentials |
| `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET` | for GitHub | GitHub OAuth credentials |
| `ALLOWED_REDIRECT_ORIGINS` | for a cross-origin SPA | Comma-separated frontend origins allowed as `return_to`, e.g. `https://app.example.com` |

Provider console redirect URIs (derived from `APP_ORIGIN` and the mount point):

- Google: `https://api.example.com/auth/shakha/google/callback`
- GitHub: `https://api.example.com/auth/shakha/github/callback`

## Frontend (React) example

```jsx
// Start sign-in
const signIn = () => {
  const returnTo = "https://app.example.com/login";
  window.location =
    `https://api.example.com/auth/shakha/google?return_to=${encodeURIComponent(returnTo)}`;
};

// On the return page (/login), swap the one-time code for a token
useEffect(() => {
  const code = new URLSearchParams(window.location.search).get("code");
  if (!code) return;

  fetch("https://api.example.com/auth/shakha/session/exchange", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ code }),
  })
    .then((r) => r.json())
    .then(({ token }) => {
      localStorage.setItem("token", token);
      return fetch("https://api.example.com/auth/shakha/session", {
        headers: { Authorization: `Bearer ${token}` },
      });
    })
    .then((r) => r.json())
    .then(({ user }) => setUser(user));
}, []);
```

## Rails monolith usage

Shakha ships a minimal sign-in page and sets an encrypted session cookie, so a
classic server-rendered app needs no JavaScript.

```erb
<%= link_to "Sign in", "/auth/shakha/google" %>
```

```ruby
class ApplicationController < ActionController::Base
  include Shakha::ControllerHelpers
  before_action :authenticate!
end
```

```ruby
current_user      # Shakha::User or nil
current_session   # Shakha::Session or nil
signed_in?        # boolean
authenticate!     # 401 JSON for API requests, redirect to sign-in for HTML
```

Sign out:

```erb
<%= button_to "Sign out", "/auth/shakha/sign_out", method: :delete %>
```

## Endpoints

All paths are relative to the mount point (`/auth/shakha` above).

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/` | — | Built-in sign-in page (monolith) |
| GET | `/:provider` | — | Start OAuth (`google`, `github`) |
| GET | `/:provider/callback` | — | OAuth callback (provider redirects here) |
| POST | `/session/exchange` | one-time code | Swap the code for `{ token, expires_at }` |
| GET | `/session` | cookie or bearer | Current user: `{ user: {...}, session: {...} }` |
| GET | `/session/check` | cookie or bearer | Lightweight `{ status: "active" }` / `401 { status: "expired" }` |
| DELETE | `/sign_out` | cookie or bearer | Destroy the session |

## Configuration reference

Set in `config/initializers/shakha.rb` via `Shakha.setup { |config| ... }`.

| Option | Default | Description |
|---|---|---|
| `app_origin` | — | Your Rails app's origin; used to build the OAuth `redirect_uri` |
| `app_name` | `"Shakha"` | Name shown on the built-in sign-in page |
| `google_client_id` / `google_client_secret` | — | Google OAuth credentials |
| `github_client_id` / `github_client_secret` | — | GitHub OAuth credentials |
| `providers` | `[:google]` | Enabled providers |
| `allowed_redirect_origins` | `nil` | Extra origins permitted as `return_to` targets |
| `redirect_token_delivery` | `:exchange_code` | `:exchange_code` (one-time code) or `:token` (token in the URL) |
| `session_lifetime` | `30.days` | How long a session stays valid |
| `rate_limiting_enabled` | `false` | Rate-limit `authorize` (20/min) and `callback` (10/min) |

## Security

Shakha uses PKCE (S256), a timing-safe `state` check, and Google `nonce` +
ID-token claim (`iss`/`aud`/`exp`) verification. Session tokens are random
strings in the database — deleting the row revokes access immediately. See
[SECURITY.md](SECURITY.md) for the full threat model and how to report a
vulnerability.

## How it compares

- **OmniAuth** — a Rack middleware for the OAuth handshake; you still build
  sessions, endpoints, and the SPA token hand-off yourself. Shakha ships the
  whole path.
- **Devise** — excellent for password auth in a monolith; OAuth and API/SPA
  token flows are add-ons. Shakha is OAuth-only and API-first.
- **Rodauth** — broader and more configurable, with its own conventions. Shakha
  does one thing: an OAuth session broker for the API + SPA era.

## Writing your own provider

A provider implements five methods (`provider_name`, `scopes`, `authorize_url`,
`exchange_code`, `identity_from_response`) returning an identity hash of
`{ provider:, uid:, email:, name:, picture: }`. See
[`Shakha::Providers::Base`](lib/shakha/providers/base.rb) and the Google/GitHub
implementations alongside it.

## Development

```bash
bundle install
bundle exec rake test
bundle exec rubocop
```

Test against another Rails version with `BUNDLE_GEMFILE=gemfiles/rails_71.gemfile`.
See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE.txt](LICENSE.txt).
