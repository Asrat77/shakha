# Shakha Roadmap — from working prototype to public open-source project

Shakha is a headless OAuth broker engine for Rails: your SPA (or monolith) does one
redirect, Shakha handles the OAuth dance (PKCE, state, nonce), and hands back a
database-backed session token usable as a cookie or `Authorization: Bearer` header.

This roadmap picks up where the `.omo/plans` rework (Phases 0–5, shipped as v0.2.0 →
v0.5.0) left off. **Executable, file-by-file implementation specs for Milestones 1–4
live in `plans/` — start at `plans/00-execution-guide.md`.** Those phases fixed the fatal bugs, deleted the JWT/pairwise/service
infrastructure, added the provider system (Google + GitHub), the SPA token flow, and
the `rails generate shakha:install` generator. This document is about what comes next.

---

## Where the project actually stands (July 2026 review)

**Working** (verified in end-to-end testing against a Rails 8.1 API app):

- Session management: Bearer + cookie auth, `authenticate!`, `current_user`, sign-out,
  revocation — all confirmed working.
- Install generator produces correct migration + initializer.
- Provider abstraction (`Providers::Base`, registry, Google, GitHub) is clean and small.

**Broken or unfinished** (found in this review — these gate everything else):

1. **The test suite does not run.** `bundle exec rake test` fails at load:
   `lib/shakha/engine.rb` references `::Rails::Engine` but the test helper never loads
   Rails, and `test_helper.rb` still sets `Shakha.config.service_secret`, an attribute
   deleted in Phase 2. The integration tests need a real (dummy) Rails app to host the
   engine. Until CI is green, nothing else on this list is trustworthy.
2. **Nonce is generated but never used.** `PKCEMixin#create_pkce_bundle` stores a nonce
   in the encrypted cookie, but `AuthController#authorize` never passes it to the
   provider — `Providers::Google#authorize_url` generates a *different* random nonce
   internally, and `identity_from_response` never verifies the ID token's nonce claim.
   Security fix #3 from the Phase 1 plan is effectively unimplemented.
3. **Google ID token claims are not validated.** `JWT.decode(id_token, nil, false)`
   skips signature verification (defensible when the token arrives directly from
   Google's token endpoint over TLS), but `iss`, `aud`, and `exp` are not checked
   either. `aud` must equal our client ID; without that check a token minted for
   another app is accepted.
4. **Session token travels in the redirect URL** (`?token=...`). URLs leak into browser
   history, `Referer` headers, and server logs. The Phase 1 plan already named the
   fix: a short-lived one-time exchange code in the URL, swapped for the real token
   via a `POST /auth/shakha/session/exchange` call.
5. **The engine force-inserts middleware into host apps.**
   `engine.rb` unconditionally inserts `ActionDispatch::Cookies` and a `CookieStore`
   (with a hardcoded key) before `HostAuthorization` in *every* host app. In a full
   Rails app this double-installs session middleware; in an API app it silently
   changes the middleware stack. This should be opt-in, documented, and idempotent.
6. **README and gemspec describe the deleted architecture.** Pairwise subjects, ES256
   JWTs, JWKS, standalone service mode, `shakha.dev` homepage, a hand-written
   migration that's now generated — all stale. The gemspec still depends on `jwt`
   solely for one unverified decode, ships a placeholder email, and lacks
   `source_code_uri` / `changelog_uri` metadata.
7. **Smaller correctness items:**
   - `find_or_create_user` never refreshes `email`/`name`/`picture` on returning users.
   - `redirect_uri` hardcodes the `/auth/shakha` mount path; breaks if the engine is
     mounted elsewhere.
   - `GoogleOAuthError` still defined in `pkce.rb` but nothing raises it.
   - Rate limiting exists but is off by default and untested.
   - The `shakha_clients` table is a vestige of multi-tenant service mode; one row is
     auto-created per origin and adds a join for no current benefit. Decide: cut it
     or give it a purpose.

---

## Milestone 1 — v0.6.0: A test suite that actually runs (the credibility milestone)

Nothing about an auth library is believable without green CI. Do this first.

- [ ] Rebuild the test harness around a **dummy Rails app** (`test/dummy`) that mounts
      the engine — the standard Rails-engine pattern (or use the `combustion` gem).
      SQLite in-memory, migrations from the generator template so the template itself
      is tested.
- [ ] Fix `test_helper.rb`: remove `service_secret`, load the dummy app, add `webmock`
      to stub Google/GitHub token endpoints.
- [ ] Port the Phase 5 test plan for real: full authorize → callback → token → Bearer
      flow with stubbed providers; PKCE cookie round-trip; state mismatch; expired
      session; `authenticate!` JSON-vs-HTML behavior; generator test via
      `Rails::Generators::TestCase`.
- [ ] **GitHub Actions CI**: matrix over Ruby (3.1–3.4) × Rails (7.1, 7.2, 8.0, 8.1),
      running tests + RuboCop. Badge in README.
- [ ] Add `rubocop-rails-omakase` (the Rails-default style) — zero-bikeshed linting.

Exit criteria: `bundle exec rake test` passes locally and in CI on every matrix cell.

## Milestone 2 — v0.7.0: Security hardening (the trust milestone)

An auth gem gets one chance at a first impression with security-minded reviewers.
Fix the known gaps *before* publicizing, and document the threat model honestly.

- [ ] **Wire the nonce through**: `authorize` passes the stored nonce to
      `provider.authorize_url`; Google provider accepts `nonce:` as a param;
      `identity_from_response(token_response, expected_nonce:)` rejects mismatches.
- [ ] **Validate ID token claims**: `iss` ∈ Google's issuers, `aud` == our client ID,
      `exp` in the future. Document why full signature verification is skipped for
      the direct token-endpoint response (or add optional JWKS verification and drop
      the `jwt` gem question entirely).
- [ ] **One-time exchange code flow**: callback redirects with `?code=<one-time>`
      (60-second TTL, single use, stored on the session row); new
      `POST session/exchange` endpoint swaps it for the session token. Keep
      `?token=` as a deprecated opt-in for one release.
- [ ] **Remove the forced middleware insertion**; replace with a documented
      initializer option (`config.install_cookie_middleware = true` for API-mode
      apps) or a generator-injected snippet in `config/application.rb` so the host
      app owns its middleware stack.
- [ ] Update returning users' profile fields on sign-in.
- [ ] Derive `redirect_uri` from the engine's actual mount point.
- [ ] Enable and test rate limiting on `authorize`/`callback`; document backend
      requirements (atomic increment needs Redis/Memcached, not `MemoryStore`, in
      multi-process deployments).
- [ ] Decide the fate of `shakha_clients` (recommendation: remove; re-adding a
      tenancy concept later is easier than carrying a dead table to v1.0).
- [ ] Write `SECURITY.md`: supported versions, private disclosure contact, and an
      explicit threat-model section (what Shakha protects against, what it delegates
      to the host app).
- [ ] Run Brakeman + `bundle-audit` in CI.

## Milestone 3 — v0.8.0: Open-source hygiene (the adoption-readiness milestone)

- [ ] **Rewrite README** for what the gem is now: the 7-step SPA flow diagram from
      `.omo/plans/00-overview.md` front and center, quickstart via the generator,
      a React example snippet, a monolith example, configuration reference table.
      Delete every mention of pairwise/JWT/service mode.
- [ ] **Fix the gemspec**: accurate summary/description, real author email, GitHub
      homepage, `source_code_uri`, `changelog_uri`, `bug_tracker_uri`,
      `rubygems_mfa_required = true`.
- [ ] `CHANGELOG.md` (Keep a Changelog format) — backfill 0.2.0–0.5.0 from git
      history, maintain going forward.
- [ ] `CONTRIBUTING.md` (dev setup, running tests, how to add a provider),
      `CODE_OF_CONDUCT.md` (Contributor Covenant), issue + PR templates,
      `.github/dependabot.yml`.
- [ ] Clean the repo: remove committed `.gem` files (add to `.gitignore`), remove or
      relocate `.omo`/`.sisyphus` scratch dirs, commit the pending
      `application_controller.rb` / `Gemfile.lock` changes.
- [ ] YARD docs on the public API (`ControllerHelpers`, `Config`, `Providers::Base`).
- [ ] **Publish to rubygems.org** — this is the moment the project becomes real.
      Reserve the name early; `gem push` v0.8.0 as the first public release.

## Milestone 4 — v0.9.0: Developer experience & ecosystem

- [ ] **Example apps** in `examples/` (or sibling repos): `rails-api-react` (Vite +
      React, full login flow) and `rails-monolith` (Turbo, zero JS). These double as
      living integration tests and the first thing evaluators clone.
- [ ] **"Write your own provider" guide** — the `Providers::Base` contract is 5
      methods; a documented recipe turns every "please add provider X" issue into a
      contributor opportunity. Good first issues: Apple, Microsoft Entra, GitLab,
      Discord providers.
- [ ] Generator polish: `--providers=google,github` flag, API-mode detection,
      idempotent re-runs.
- [ ] Session management niceties: `Shakha::Session.for(user)` listing, per-session
      revocation endpoint, optional sliding expiration.
- [ ] Structured instrumentation via `ActiveSupport::Notifications`
      (`shakha.sign_in`, `shakha.sign_out`, `shakha.auth_failure`) so host apps can
      hook audit logging without Shakha owning it.
- [ ] Documentation site (GitHub Pages, or just excellent README + `docs/` guides:
      SPA integration, monolith integration, testing your app with Shakha, threat
      model).

## Milestone 5 — v1.0.0: Stability contract

- [ ] Freeze the public API surface and document it (what's covered by semver).
- [ ] Upgrade guide from 0.x.
- [ ] Deprecation policy (one minor version of warnings before removal).
- [ ] Announce: writeups for r/rails, Ruby Weekly, Rails discourse, Hacker News
      (Show HN). The pitch that differentiates Shakha from OmniAuth/Rodauth/Devise:
      **"SPA-first OAuth for Rails APIs with zero frontend SDK — one redirect, one
      token, done."** Lead with the honest comparison table (OmniAuth = rack
      middleware + you build sessions yourself; Rodauth = full-featured but its own
      world; Devise = password-era, monolith-first; Shakha = OAuth-only session
      broker for the API + SPA era).

## Ongoing — Community & the Anthropic "Claude for Open Source" program

Anthropic's program (launched Feb 2026, expanded July 8, 2026) gives qualifying
maintainers **6 months of Claude Max 20x free (~$1,200 value)**. Eligibility as
published: primary maintainer or core-team member of a public repo with **5,000+
GitHub stars or 1M+ monthly package downloads**, with commits/releases/PR reviews in
the last 3 months — plus an explicit invitation for **"critical infrastructure"
projects below those metrics to apply anyway**. Applications:
`claude.com/contact-sales/claude-for-oss`.

Honest read: Shakha won't hit 5k stars soon, but authentication infrastructure is a
plausible "critical infrastructure / apply anyway" story **once the project has real
users** — published gem, green CI, security policy, a few external contributors, and
visible download numbers. The path to eligibility is exactly Milestones 1–5 plus:

- [ ] Ship consistently (small releases monthly beat a big drop yearly — the program
      requires activity within the last 3 months).
- [ ] Make contribution cheap: provider recipes, `good first issue` labels, fast PR
      review turnaround.
- [ ] Track adoption signals: rubygems download stats, GitHub stars/dependents.
- [ ] Apply once v1.0 is out and downloads show a real user base; re-apply as the
      program expands (it grew in July 2026 and is likely to keep widening).

---

## Suggested sequence

Milestones 1 and 2 are the critical path and worth doing back-to-back — a broken test
suite and known security gaps are disqualifying for an auth library. Milestone 3 is
mostly writing and can overlap. Publish (end of M3) *before* M4 so early feedback
shapes the DX work. Target: v0.8.0 on rubygems within the first push of work, v1.0.0
after the example apps have soaked and at least one external bug report has been
fixed.
