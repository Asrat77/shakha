# Shakha Implementation Plan — Execution Guide

Read this file first. Then execute the phase files **in order**:

1. `01-test-harness.md` — make the test suite run; add CI. Ships as **v0.6.0**.
2. `02-security-hardening.md` — fix the nonce gap, validate ID tokens, exchange-code
   flow, remove forced middleware, drop the clients table. Ships as **v0.7.0**.
3. `03-oss-hygiene.md` — README rewrite, gemspec, CHANGELOG, community files,
   repo cleanup. Ships as **v0.8.0** (first public rubygems release).
4. `04-dx-adoption.md` — example app, provider guide, instrumentation. **v0.9.0**.

These plans supersede `.omo/plans/` (the Phase 0–5 rework, already shipped as
v0.2.0–v0.5.0). Do not re-execute anything in `.omo/plans/`.

## Ground rules

- **Never proceed on red.** Run `bundle exec rake test` after every task. From Task
  1.2 onward the suite must pass before you start the next task.
- **One commit per task**, message format: `P1.3: Port auth flow integration tests`.
  End every commit message with the Co-Authored-By line from your instructions.
- **Do not bump the version mid-phase.** Bump `lib/shakha/version.rb` once, in the
  final task of each phase.
- Code blocks in these plans marked "full contents" are exact file contents —
  write them verbatim. Blocks marked "edit" show the change against current code;
  apply surgically, keep the rest of the file intact.
- The current code state these plans were written against: commit `6c65cd9` plus
  two uncommitted changes (Gemfile.lock version bump, CSRF skip for JSON in
  `app/controllers/shakha/application_controller.rb`). Task 1.1 commits those first.
- Style: `frozen_string_literal: true` on every Ruby file, 2-space indent, no
  comments that narrate what code does.

## Things that require the user (do NOT attempt yourself)

- Pushing the gem to rubygems.org (needs their account + MFA) — Phase 3 prepares
  everything and stops.
- Creating the GitHub repository / pushing to a remote, if none is configured.
- Real-credential OAuth testing against Google/GitHub consoles. All automated tests
  stub the providers with WebMock.

When you hit one of these, finish everything around it, then report what the user
must do, with exact commands.

## Architecture invariants (do not violate)

- Shakha stays a **Rails engine**, mounted by the host; no standalone mode.
- Session tokens are **random strings in the DB**. No JWTs issued by Shakha. The
  `jwt` gem is used only to decode Google's ID token.
- Auth works via **encrypted cookie OR `Authorization: Bearer`** — both, always.
- Providers implement exactly the `Shakha::Providers::Base` contract; the
  controller never special-cases a provider.
- No new runtime gem dependencies without explicit instruction in a plan file.
