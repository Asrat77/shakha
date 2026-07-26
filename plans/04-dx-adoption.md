# Phase 4 — DX & adoption (v0.9.0)

Prereq: Phase 3 shipped and the gem is on rubygems.org. This phase is deliberately
specified one level lighter than Phases 1–3: by now the conventions are established
(test harness, provider contract, doc tone) — follow them. Anything ambiguous:
match the nearest existing pattern rather than inventing a new one.

---

## Task 4.1 — Instrumentation events

Emit `ActiveSupport::Notifications` so host apps can build audit logging without
Shakha owning it. In `AuthController`:

- `shakha.sign_in` — payload `{ user_id:, provider:, ip: request.remote_ip }`,
  after session creation in `callback`.
- `shakha.auth_failure` — payload `{ provider:, error: exception.class.name }`,
  inside `handle_auth_failure`.
- `shakha.sign_out` — payload `{ user_id: }`, in `destroy` (guard nil session).

Use `ActiveSupport::Notifications.instrument("shakha.sign_in", payload)`.
Tests: subscribe in the integration test, run the flow, assert the events fired
with the right payload keys. Document the events + payloads in a new
`docs/instrumentation.md` and link it from the README.

## Task 4.2 — "Write your own provider" guide

**Create `docs/providers.md`**: the `Providers::Base` contract method-by-method
(`provider_name`, `scopes`, `authorize_url`, `exchange_code`,
`identity_from_response` — exact signatures and the identity-hash shape
`{ provider:, uid:, email:, name:, picture: }`), a complete worked example
(GitLab: `https://gitlab.com/oauth/authorize`, `https://gitlab.com/oauth/token`,
supports PKCE), how to register it (`Shakha::Providers::PROVIDER_MAP` is currently
frozen — add a public `Shakha::Providers.register(name, klass)` API as part of this
task, with a test), and the WebMock testing pattern copied from
`test/shakha/providers/github_test.rb`.

`register` spec: maintain an internal mutable registry hash seeded from the
built-ins; `resolve` reads it; registering an existing name overwrites (documented).
Config note: third-party providers read their own credentials — recommend they
accept them via constructor args or read from `ENV`, since `Shakha::Config` only
carries google/github keys.

## Task 4.3 — Example app: Rails API + React

**Create `examples/rails-api-react/`** — the smallest complete demo:

- `api/`: a committed Rails API app (generated with
  `rails new api --api --minimal`, SQLite), gem via
  `gem "shakha", path: "../../.."`, generator ran, one `GET /me` protected
  endpoint, CORS configured for `http://localhost:5173`.
- `web/`: a Vite + React app (no TypeScript, keep it tiny): a login button, a
  `/login` return page that exchanges `?code=`, localStorage token, a fetch of
  `/me`, a sign-out button.
- `examples/rails-api-react/README.md`: env vars to set, Google console setup
  (redirect URI), `bin/rails s` + `npm run dev`, what you should see.

Exclude `examples/` from the gem package (already excluded by the Phase 3
`spec.files` enumeration — verify) and from RuboCop (`.rubocop.yml` Exclude).
Trim generated noise: delete unused Rails app directories the demo doesn't need.
Do not add the example's gems to the root `Gemfile.lock` — the example has its own
bundle. CI: add a workflow job that boots the example API and asserts
`GET /me` → 401 and `GET /auth/shakha/google` → 302 (with dummy env credentials) —
this keeps the example from rotting.

## Task 4.4 — Generator polish

- `--providers=google,github` option: class_option in the generator; the
  initializer template renders only the chosen providers' config blocks and sets
  `config.providers` accordingly. Default remains `google,github`.
- Idempotent re-runs: running `rails generate shakha:install` twice must not create
  a second migration (use `migration_template`'s built-in collision handling; test
  it) nor duplicate the initializer or injected lines.
- Generator tests for both.

## Task 4.5 — Session management niceties

- `Shakha::Session.for(user)` scope returning active sessions newest-first.
- `GET /auth/shakha/sessions` (authenticated): list the current user's active
  sessions — id, ip_address, user_agent, created_at, `current: true` flag for the
  requesting session.
- `DELETE /auth/shakha/sessions/:id` (authenticated): revoke one of your own
  sessions; 404 for other users' sessions.
- Routes go in the static block before `:provider`. Integration tests for both,
  including the cannot-revoke-others case.

## Task 4.6 — Ship v0.9.0

Version bump, CHANGELOG entry, suite green, `gem build` clean. Stop and hand the
push to the user as in Phase 3. Suggested announcement targets for the user (do not
post anything yourself): Ruby Weekly submission, r/rails, Rails Discourse
"gems" category — the pitch line from the README.

---

# Beyond (v1.0.0 — plan when 0.9 has real usage)

Not specced yet on purpose; re-plan with real feedback. Candidate scope: API-surface
freeze + semver commitment, upgrade guide, deprecation policy, sliding session
expiration, more first-party providers (Apple, Microsoft Entra) as `good first
issue` templates, docs site. Also: apply to Anthropic's Claude for Open Source
program once download/star numbers give the "critical infrastructure" application a
real story (see ROADMAP.md).
