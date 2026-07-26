# Phase 2 — Security hardening + schema simplification (v0.7.0)

Prereq: Phase 1 complete, suite green. Every task here ends with the full suite
green. Schema changes are safe — the gem has never been published, there are no
production installs to migrate.

---

## Task 2.1 — Remove the `shakha_clients` table

It's a vestige of the deleted multi-tenant service mode: one row auto-created per
origin, a join on every sign-in, zero behavior. Removing it touches many files —
do it before the security work so later tasks edit the final shape of the code.

1. **Config** (`lib/shakha/config.rb`): add `attr_accessor :app_name` and default
   `@app_name = "Shakha"` in `initialize` (the sign-in page currently shows the
   client's name; this replaces it).
2. **Delete** `app/models/shakha/client.rb`.
3. **`app/models/shakha/user.rb`**: remove `belongs_to :client`, remove the
   `validates :email, uniqueness: { scope: :client_id }` line (email is not an
   identity key — `provider`+`uid` is).
4. **`app/models/shakha/session.rb`**: remove `belongs_to :client`.
5. **`app/controllers/shakha/auth_controller.rb`**: delete `find_or_create_client`
   and every call to it; `create_session` and `find_or_create_user` no longer set
   `client:`; in `new`, replace `@client = find_or_create_client` with nothing.
6. **Views**: `grep -rn "client" app/views/` and replace every `@client&.name`
   with `Shakha.config.app_name`.
7. **Migration template**
   (`lib/generators/shakha/install/templates/create_shakha_tables.rb.erb`): remove
   the `create_table :shakha_clients` block and both `t.references :client` lines.
8. **`test/test_helper.rb`**: mirror the template — remove the clients table and
   `client` references from the schema block; delete `create_client` and its usages
   (`create_user` and `create_session_record` no longer pass `client:`).
9. Fix every test that referenced clients; run the suite.

## Task 2.2 — Wire the nonce through (currently generated but never used)

Today `PKCEMixin#create_pkce_bundle` stores a nonce in the cookie, but
`Providers::Google#authorize_url` generates a *different* random nonce, and nothing
ever verifies the ID token's `nonce` claim.

1. **`lib/shakha/providers/base.rb`**: change the signatures to

   ```ruby
   def authorize_url(state:, code_challenge:, redirect_uri:, nonce: nil)
     raise NotImplementedError
   end

   def identity_from_response(token_response, expected_nonce: nil)
     raise NotImplementedError
   end
   ```

2. **`lib/shakha/providers/google.rb`**: `authorize_url` gains `nonce:` and uses it
   in the params hash (delete the `SecureRandom.urlsafe_base64(32)` line);
   `identity_from_response` gains `expected_nonce:` (verification added in Task 2.3).
3. **`lib/shakha/providers/github.rb`**: accept both new keywords and ignore them
   (GitHub OAuth has no nonce).
4. **`app/controllers/shakha/auth_controller.rb`**:
   - `authorize` passes `nonce: pkce[:nonce]` to `provider.authorize_url`.
   - `callback` passes `expected_nonce: pkce_result[:nonce]` to
     `provider.identity_from_response`.

## Task 2.3 — Validate Google ID token claims

In `Providers::Google#identity_from_response`, after decoding the payload and before
building the identity hash:

```ruby
unless %w[https://accounts.google.com accounts.google.com].include?(payload["iss"])
  raise OAuthError, "ID token issuer mismatch"
end
raise OAuthError, "ID token audience mismatch" unless payload["aud"] == Shakha.config.google_client_id
raise OAuthError, "ID token expired" if payload["exp"].to_i <= Time.now.to_i
if expected_nonce.present? &&
   !ActiveSupport::SecurityUtils.secure_compare(payload["nonce"].to_s, expected_nonce)
  raise OAuthError, "ID token nonce mismatch"
end
```

Keep `JWT.decode(id_token, nil, false)` (no signature check) but add a comment with
the justification: the token arrives directly from Google's token endpoint over a
TLS connection we initiated, so its provenance is the transport, not the signature.

**Tests** (extend `test/shakha/providers/google_test.rb` and the integration test):
- wrong `aud` → `OAuthError`
- expired `exp` → `OAuthError`
- `expected_nonce` given, token nonce differs → `OAuthError`
- integration: callback where the stubbed token's nonce ≠ the authorize nonce →
  no session created, error redirect. (The Phase 1 helpers already thread the real
  nonce, so the happy path keeps passing.)

## Task 2.4 — One-time exchange code instead of token-in-URL

The session token currently rides in the redirect URL (`?token=...`), where it leaks
into browser history, `Referer` headers, and logs. Replace with a 60-second
single-use code the SPA swaps for the token via POST.

1. **Schema** — in the migration template AND the test-helper schema block, add to
   `shakha_sessions`:

   ```ruby
   t.string :exchange_code
   t.datetime :exchange_code_expires_at
   t.index :exchange_code, unique: true
   ```

2. **`app/models/shakha/session.rb`**:

   ```ruby
   EXCHANGE_CODE_TTL = 60.seconds

   def generate_exchange_code!
     update_columns(
       exchange_code: SecureRandom.urlsafe_base64(32),
       exchange_code_expires_at: EXCHANGE_CODE_TTL.from_now
     )
     exchange_code
   end

   def self.exchange(code)
     return nil if code.blank?

     session = active.where(exchange_code: code)
                     .where("exchange_code_expires_at > ?", Time.current).first
     return nil unless session

     claimed = where(id: session.id).where.not(exchange_code: nil)
               .update_all(exchange_code: nil, exchange_code_expires_at: nil)
     claimed == 1 ? session : nil
   end
   ```

   (The `update_all` guard makes redemption atomic — two racing exchanges can't
   both win.)

3. **Config** (`lib/shakha/config.rb`): `attr_accessor :redirect_token_delivery`,
   default `@redirect_token_delivery = :exchange_code`. `:token` is the legacy
   opt-out.
4. **`AuthController#build_return_url`**:

   ```ruby
   def build_return_url(return_to, session_record)
     uri = URI.parse(return_to || "/")
     existing = URI.decode_www_form(uri.query || "").to_h

     if Shakha.config.redirect_token_delivery == :token
       existing["token"] = session_record.token
       existing["expires_at"] = session_record.expires_at.iso8601
     else
       existing["code"] = session_record.generate_exchange_code!
     end

     uri.query = URI.encode_www_form(existing)
     uri.to_s
   end
   ```

5. **Route** (`lib/shakha/engine.rb`, in the static-routes block, before the
   dynamic `:provider` routes): `post "session/exchange" => "session#exchange"`.
6. **`SessionController`**:

   ```ruby
   skip_forgery_protection only: :exchange

   def exchange
     session_record = Shakha::Session.exchange(params[:code])
     if session_record
       render json: { token: session_record.token,
                      expires_at: session_record.expires_at.iso8601 }
     else
       render json: { error: "Invalid or expired code" }, status: :unauthorized
     end
   end
   ```

7. **Generator initializer template**: document both delivery modes with the
   `:exchange_code` default and the frontend contract
   (`POST /auth/shakha/session/exchange` with `code`).
8. **Tests**:
   - Update the full-flow integration test: redirect now carries `code=` (assert
     `token` is absent from the URL), then
     `post "/auth/shakha/session/exchange", params: { code: code }` → 200 with
     token → Bearer works.
   - New tests: reusing a redeemed code → 401; expired code (travel
     `exchange_code_expires_at` into the past via `update_columns`) → 401; blank
     code → 401.
   - Legacy mode test: set `Shakha.config.redirect_token_delivery = :token` (reset
     it in `ensure`), assert `token=` appears in the redirect.

## Task 2.5 — Install generator handles API-mode hosts

Phase 1 removed the engine's forced middleware. API-only Rails apps lack
`ActionDispatch::Cookies`, which `cookies.encrypted` (PKCE + session cookie) needs.
Make the generator inject it so the host app owns its middleware stack.

In `lib/generators/shakha/install/install_generator.rb`, add after
`inject_application_controller`:

```ruby
def enable_cookies_for_api_mode
  return unless api_only_app?

  application "config.middleware.use ActionDispatch::Cookies"
  say_status :insert, "config/application.rb -> ActionDispatch::Cookies (API mode)", :green
end
```

and a private predicate:

```ruby
def api_only_app?
  path = File.join(destination_root, "config/application.rb")
  File.exist?(path) && File.read(path).include?("config.api_only = true")
end
```

**Generator test**: write a `config/application.rb` containing
`config.api_only = true` into the destination, run the generator, assert the
middleware line was injected; and a second test asserting no injection for a
non-API app.

## Task 2.6 — Refresh profile fields for returning users

`find_or_create_user` only sets email/name/picture at creation. Replace with:

```ruby
def find_or_create_user(provider_name, identity)
  user = Shakha::User.find_or_initialize_by(
    provider: provider_name.to_s, uid: identity[:uid]
  )
  user.email = identity[:email]
  user.name = identity[:name]
  user.picture = identity[:picture]
  user.save!
  user
end
```

**Test**: create a user, run the callback flow with a token carrying a new name,
assert the record was updated and no duplicate user was created.

## Task 2.7 — Derive redirect_uri from the actual mount point

Both `authorize` and `callback` hardcode `"#{app_origin}/auth/shakha/..."`, breaking
any other mount path.

1. Name the engine routes (`lib/shakha/engine.rb`):

   ```ruby
   get ":provider"          => "auth#authorize", as: :authorize
   get ":provider/callback" => "auth#callback",  as: :callback
   ```

2. In `AuthController`, replace both hardcoded strings with a helper:

   ```ruby
   def callback_redirect_uri(provider)
     origin = URI.parse(Shakha.config.app_origin)
     callback_url(provider: provider.provider_name,
                  host: origin.host, port: origin.port, protocol: origin.scheme)
   end
   ```

   (Rails omits default ports for the scheme automatically.)

**Test**: the existing Task 1.6 assertion
(`redirect_uri == "http://localhost:3000/auth/shakha/google/callback"`) already
covers the default mount; it must still pass unchanged.

## Task 2.8 — Unknown/disabled provider returns 404, not a crash

1. `lib/shakha.rb`: add `class ProviderNotFound < StandardError; end` next to the
   other error classes.
2. `AuthController#resolve_provider`:

   ```ruby
   def resolve_provider
     name = params[:provider].to_s.to_sym
     raise ProviderNotFound, name.to_s unless Shakha.config.providers.include?(name)
     Shakha::Providers.resolve(name)
   end
   ```

3. `lib/shakha/error_handler.rb`: add
   `rescue_from Shakha::ProviderNotFound, with: :not_found` (reuse the existing
   `not_found` handler but don't echo the exception message — render
   `{ error: "Unknown provider" }`, status 404; adjust `not_found` to take a static
   message or add a dedicated handler).
4. Replace the Phase 1 placeholder test ("unknown provider raises...") with:
   `get "/auth/shakha/nonexistent"` → 404; and a disabled-provider test: set
   `Shakha.config.providers = [:google]` (restore in `ensure`), hit
   `/auth/shakha/github` → 404.

## Task 2.9 — Rate limiting: test it and make it safe

1. In `test/test_helper.rb` `DummyApp` config, add
   `config.cache_store = :memory_store`.
2. Harden `lib/shakha/rate_limiter.rb` against cache stores whose `increment`
   returns nil: `count = Rails.cache.increment(cache_key, 1, expires_in: period.seconds) || 1`.
3. **New `test/shakha/rate_limiter_test.rb`** (integration): enable
   `Shakha.config.rate_limiting_enabled = true` (helper resets it), clear
   `Rails.cache`, hit `/auth/shakha/google` 20 times expecting redirects, 21st
   request → 429 JSON. Second test: callback limit of 10.

## Task 2.10 — SECURITY.md + dependency audit in CI

**Create `SECURITY.md`**:

- Supported versions: latest minor only (pre-1.0).
- Report privately via GitHub Security Advisories ("Report a vulnerability" on the
  repo); no public issues for vulnerabilities; response target: 7 days.
- Threat-model section (write it out): Shakha handles OAuth redirect integrity
  (PKCE + state + nonce), session token storage/revocation, open-redirect
  prevention via `allowed_redirect_origins`. Out of scope / delegated to the host:
  TLS termination, CORS policy, XSS in the host frontend (which can steal any
  bearer token the SPA can read), secrets management. Document the design choices:
  DB-backed random tokens (revocable, no JWT), one-time exchange codes in redirect
  URLs, ID-token claims validated but signature trusted via TLS provenance.

Add `gem "bundler-audit", require: false` to `Gemfile` (and the three gemfiles),
and a CI job in `.github/workflows/ci.yml`:

```yaml
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.4"
          bundler-cache: true
      - run: bundle exec bundler-audit check --update
```

## Task 2.11 — Cleanup + ship v0.7.0

- Delete the dead `class GoogleOAuthError < StandardError; end` from
  `lib/shakha/pkce.rb` (grep first to confirm nothing references it).
- Full suite + rubocop + `bundler-audit` green on the default Gemfile and
  `gemfiles/rails_71.gemfile`.
- Bump version to `0.7.0`, refresh lockfile, commit
  `P2.11: v0.7.0 — security hardening`.

**Phase exit criteria**: nonce verified end-to-end; ID-token claims validated; no
session token ever appears in a URL by default; no forced middleware; clients table
gone; unknown provider → 404; SECURITY.md exists; CI includes audit job.
