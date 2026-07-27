# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Until 1.0.0, minor
versions may include breaking changes; these are called out below.

## [Unreleased]

## [0.7.0] — 2026-07-26

Security hardening. Several changes are breaking; there are no production
installs of the intermediate 0.6.0 to migrate.

### Security
- Verify the Google ID token: the OIDC `nonce` is now threaded through the
  authorize step and checked on callback, and the `iss`, `aud`, and `exp` claims
  are validated. The `aud` check rejects tokens minted for other clients.
- Deliver the session token via a single-use, 60-second exchange code by default
  instead of placing it in the redirect URL, where it could leak into history,
  `Referer` headers, and logs.
- Validate `return_to` against the app origin and `allowed_redirect_origins`
  before it is stored, closing an open-redirect path in the OAuth flow.
- Run `bundler-audit` in CI; raise the `jwt` floor to `>= 2.10.3` and patch
  `rails-html-sanitizer`, `json`, and `concurrent-ruby`.
- Add `SECURITY.md` with a private disclosure process and threat model.

### Changed
- **Breaking:** the OAuth callback now redirects with `?code=` (a one-time
  exchange code). Set `config.redirect_token_delivery = :token` to restore the
  previous `?token=` behavior for one release.
- **Breaking:** removed the `shakha_clients` table and the `Shakha::Client`
  model. Users and sessions no longer belong to a client. The sign-in page shows
  `config.app_name` (default `"Shakha"`).
- Returning users' `email`/`name`/`picture` are refreshed on each sign-in.
- The OAuth `redirect_uri` is derived from the engine's actual mount point, so
  Shakha works when mounted anywhere.
- An unknown or disabled provider returns `404` instead of raising a `500`.

### Added
- `config.redirect_token_delivery`, `config.app_name`.
- `POST /auth/shakha/session/exchange` — swap a one-time code for the token.
- The install generator injects `ActionDispatch::Cookies` into API-only hosts.

## [0.6.0] — 2026-07-26

### Added
- A real test suite: an in-process dummy Rails app harness with full coverage of
  the OAuth flow, session/bearer auth, providers, PKCE, models, and the
  generator. Previously the suite could not load.
- GitHub Actions CI across Ruby 3.1–3.4 × Rails 7.1/8.0/8.1, plus RuboCop
  (`rubocop-rails-omakase`).

### Fixed
- PKCE code verifier no longer carries base64 padding (`SecureRandom.urlsafe_base64`
  takes `padding` positionally, so `padding: false` had passed a truthy hash).
- The OAuth callback no longer trips Rails' open-redirect protection.
- The install generator injects into `ApplicationController` using the
  generator's `destination_root` rather than a CWD-relative path.

### Changed
- **Breaking (API-mode hosts):** the engine no longer force-inserts cookie and
  session middleware into the host app. Re-run `rails generate shakha:install`,
  or add `ActionDispatch::Cookies` to your middleware stack.

## [0.5.0] — 2026-05-20
- End-to-end verification of the SPA flow in a Rails 8.1 API app; runtime fixes
  found during that testing; API-mode cookie/session compatibility.

## [0.3.0] — 2026-05-19
- Multi-provider system (Google and GitHub) wired into the engine; simplified
  provider-scoped URLs; `rails generate shakha:install` generator.

## [0.2.0] — 2026-05-19
- Rework toward an SPA-first broker: fixed six fatal bugs and several security
  issues; rewrote the auth flow and controllers; simplified models and config;
  removed the JWT/JWKS/OIDC and pairwise-subject service infrastructure.

## [0.1.0] — 2026-05
- Initial prototype: Google OAuth broker with PKCE, database sessions, and a
  sign-in page.

[Unreleased]: https://github.com/Asrat77/shakha/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/Asrat77/shakha/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/Asrat77/shakha/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/Asrat77/shakha/compare/v0.3.0...v0.5.0
[0.3.0]: https://github.com/Asrat77/shakha/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Asrat77/shakha/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Asrat77/shakha/releases/tag/v0.1.0
