# Phase 3 — Open-source hygiene + first public release (v0.8.0)

Prereq: Phases 1–2 complete. This phase is mostly writing; every claim in the docs
must match the post-Phase-2 code (exchange-code flow, no clients table, nonce
verified). Where a GitHub URL is needed: run `git remote get-url origin` and use it;
if there is no remote, use `https://github.com/OWNER/shakha`, and list "create the
GitHub repo and replace OWNER" in the final user-action report.

---

## Task 3.1 — Repo cleanup

- `git rm --cached *.gem` (six built gems are committed) — `.gitignore` from Phase 1
  already ignores them; also delete the files from disk.
- Remove the superseded planning/scratch dirs from the repo:
  `git rm -r .omo` (tracked) and delete the untracked `.omo/browser-test-guide.md`,
  `.omo/test-results.md`, `.sisyphus/` from disk. Their content is preserved in git
  history; `ROADMAP.md` and `plans/` are the living documents.
- Add `.omo/` and `.sisyphus/` to `.gitignore` so local tooling can recreate them
  without polluting `git status`.

## Task 3.2 — Rewrite the gemspec

Replace `shakha.gemspec` contents (keep the existing VERSION-reading preamble):

```ruby
Gem::Specification.new do |spec|
  spec.name = "shakha"
  spec.version = VERSION
  spec.authors = ["Asrat"]
  spec.email = ["dev@podrwa.com"]

  spec.summary = "SPA-first OAuth session broker for Rails — one redirect, one token, done"
  spec.description = <<~DESC
    Shakha is a headless OAuth broker engine for Rails APIs and monoliths.
    Your frontend does a single redirect; Shakha runs the OAuth dance
    (PKCE, state, nonce) against Google or GitHub, stores a revocable
    database-backed session, and hands the frontend a one-time code to
    exchange for a session token. Auth works via encrypted cookie or
    Authorization: Bearer — no JWTs, no Redis, no frontend SDK.
  DESC
  spec.homepage = "<GITHUB_URL>"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/master/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*", "app/**/*", "README.md", "CHANGELOG.md", "SECURITY.md", "LICENSE.txt"]

  spec.add_dependency "jwt", "~> 2.7"
  spec.add_dependency "activesupport", ">= 7.1", "< 10"
  spec.add_dependency "railties", ">= 7.1", "< 10"
end
```

Note the `spec.files` change: the old `Dir["*.md"]` glob would have shipped
`ROADMAP.md` (and previously the plans) inside the gem — enumerate explicitly.
Verify packaging: `gem build shakha.gemspec` succeeds and
`tar -tzf` / `gem contents` shows no plans, no tests, no `.omo`. Delete the built
gem afterward.

## Task 3.3 — Rewrite README.md

Full rewrite; the current README describes deleted architecture (pairwise subjects,
ES256 JWTs, JWKS, service mode). Structure, in order:

1. **Title + one-liner**: "SPA-first OAuth for Rails. One redirect. One token. Done."
   CI badge (`.github/workflows/ci.yml` on master), gem-version badge, MIT badge.
2. **The flow** — the 7-step diagram, updated for the exchange-code flow:

   ```
   1. React:   window.location = "https://api.yourapp.com/auth/shakha/google?return_to=https://app.yourapp.com/login"
   2. Shakha:  redirects to accounts.google.com (PKCE, state, nonce — handled)
   3. Google:  redirects back to /auth/shakha/google/callback?code=...
   4. Shakha:  exchanges the code, verifies the ID token, creates User + Session
   5. Shakha:  redirects to https://app.yourapp.com/login?code=<one-time-code>
   6. React:   POST /auth/shakha/session/exchange {code} → {token, expires_at}
   7. React:   Authorization: Bearer <token> on every API call
   ```

3. **Quickstart** (Rails API + React): `gem "shakha"`, mount the engine in
   `config/routes.rb` (`mount Shakha::Engine => "/auth/shakha"`),
   `rails generate shakha:install`, `rails db:migrate`, env vars table
   (`APP_ORIGIN`, `GOOGLE_CLIENT_ID/SECRET`, `GITHUB_CLIENT_ID/SECRET`,
   `ALLOWED_REDIRECT_ORIGINS`), Google/GitHub console redirect URIs.
4. **Frontend example** — a ~20-line React snippet: login link, `useEffect` that
   reads `?code=` on the return page, POSTs to `/session/exchange`, stores the
   token, calls `/auth/shakha/session` to hydrate the user.
5. **Rails monolith usage** — sign-in link to the built-in page, `authenticate!`
   before_action, `current_user`/`signed_in?`, sign-out link
   (`DELETE /auth/shakha/sign_out`).
6. **Endpoints table** — every engine route with method, purpose, auth requirement.
7. **Configuration reference** — every `Shakha::Config` attribute: name, default,
   description (generate this from `lib/shakha/config.rb`, don't guess).
8. **Security** — three sentences (PKCE + state + nonce; DB-backed revocable
   tokens; one-time exchange codes) linking to `SECURITY.md`.
9. **Comparison** — one honest paragraph each vs OmniAuth (Rack middleware,
   sessions are your problem), Devise (password-era, monolith-first), Rodauth
   (broader scope, own conventions). Shakha's lane: OAuth-only session broker for
   the API + SPA era.
10. **Writing a provider** — the 5-method `Providers::Base` contract with a
    skeleton subclass, pointing to `docs/providers.md` (Phase 4).
11. Contributing / License footers.

Every code sample in the README must be checked against the actual code (routes,
config attribute names, JSON shapes). The JSON shapes come from
`SessionController#show` and `#exchange`.

## Task 3.4 — CHANGELOG.md

Keep-a-Changelog format, newest first. Backfill from git history (`git log
--oneline`) — one entry per released version with 3–6 bullet summaries:

- `0.8.0` — this release: first public release; README/gemspec/community files.
- `0.7.0` — security: nonce verification, ID-token claim validation, one-time
  exchange codes (BREAKING: redirect now carries `code=` not `token=`; set
  `config.redirect_token_delivery = :token` for old behavior), clients table
  removed (BREAKING), generator handles API-mode cookies, unknown provider → 404.
- `0.6.0` — test harness + CI matrix, RuboCop, middleware no longer force-inserted
  (BREAKING for API apps: rerun the generator or add `ActionDispatch::Cookies`).
- `0.5.0` back to `0.1.x` — summarize from the existing git history honestly
  (rework phases, provider system, generator, original prototype).

## Task 3.5 — Community files

- **`CONTRIBUTING.md`**: dev setup (`bundle install`, `bundle exec rake test`,
  `bundle exec rubocop`), matrix testing via `BUNDLE_GEMFILE=gemfiles/...`, how the
  test harness works (in-process dummy app in `test/test_helper.rb` — schema must
  mirror the generator template), how to add a provider (link to the Base
  contract), PR expectations (tests required, one concern per PR), and a note that
  security issues go through `SECURITY.md`, never public issues.
- **`CODE_OF_CONDUCT.md`**: Contributor Covenant v2.1 verbatim (fetch from
  https://www.contributor-covenant.org/version/2/1/code_of_conduct/code_of_conduct.md),
  contact = dev@podrwa.com.
- **`.github/ISSUE_TEMPLATE/bug_report.md`** (repro steps, Rails/Ruby/Shakha
  versions, API-mode or monolith) and **`feature_request.md`**;
  **`.github/pull_request_template.md`** (what/why, test coverage checklist).
- **`.github/dependabot.yml`**: bundler + github-actions ecosystems, weekly.

## Task 3.6 — Release prep (STOP for the user at the push)

1. Bump version to `0.8.0`, refresh lockfile, full suite + rubocop + audit green.
2. `gem build shakha.gemspec` and smoke-test the artifact in a throwaway dir:
   `gem unpack shakha-0.8.0.gem` and confirm contents.
3. Commit `P3.6: v0.8.0 — first public release prep`. Delete the local `.gem`.
4. **Stop and report to the user** with exact commands they must run:
   - create the GitHub repo + `git push -u origin master` (if no remote),
   - `gem signin` (rubygems.org account with MFA),
   - `gem build shakha.gemspec && gem push shakha-0.8.0.gem`,
   - create a GitHub Release for `v0.8.0` (tag first: `git tag v0.8.0 && git push --tags`),
   - replace `<GITHUB_URL>` placeholders if the remote didn't exist earlier
     (then rebuild before pushing the gem).

**Phase exit criteria**: docs match reality; `gem build` produces a clean artifact;
nothing left in-repo that describes the deleted architecture
(`grep -ri "pairwise\|jwks\|service mode" README.md CHANGELOG.md` → empty).
