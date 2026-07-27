# Contributing to Shakha

Thanks for your interest in improving Shakha! This project aims to be a small,
sharp OAuth session broker for Rails, so contributions that keep it focused are
especially welcome.

## Development setup

```bash
git clone https://github.com/Asrat77/shakha.git
cd shakha
bundle install
bundle exec rake test
bundle exec rubocop
```

Test against another supported Rails version:

```bash
BUNDLE_GEMFILE=gemfiles/rails_71.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/rails_71.gemfile bundle exec rake test
```

## How the tests work

There is no `test/dummy` directory. `test/test_helper.rb` boots a minimal
in-process Rails application, mounts the engine, and defines the schema in an
in-memory SQLite database. The schema block **must mirror** the generator
migration template at
`lib/generators/shakha/install/templates/create_shakha_tables.rb.erb` — if you
change one, change the other in the same commit.

Provider HTTP calls are stubbed with WebMock; tests never hit the network.

## Adding a provider

A provider is a subclass of `Shakha::Providers::Base` implementing five methods
(`provider_name`, `scopes`, `authorize_url`, `exchange_code`,
`identity_from_response`). Register it in `Shakha::Providers::PROVIDER_MAP`. See
the Google and GitHub providers for reference, and model your tests on
`test/shakha/providers/github_test.rb`.

## Pull requests

- Keep each PR to one concern; write a clear description of what and why.
- Add or update tests — CI runs the suite across Ruby 3.1–3.4 and Rails
  7.1/8.0/8.1, plus RuboCop (`rubocop-rails-omakase`) and `bundler-audit`.
- Run `bundle exec rubocop -a` before pushing.
- Note any breaking change in `CHANGELOG.md` under `[Unreleased]`.

## Security

Please do **not** open public issues for vulnerabilities. Follow the private
disclosure process in [SECURITY.md](SECURITY.md).

## Code of conduct

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
