# Phase 1 — Test harness + CI (v0.6.0)

Goal: `bundle exec rake test` passes locally and in a GitHub Actions matrix.
Current state: the suite crashes at load — `lib/shakha/engine.rb` needs `Rails`
which is never required, and `test/test_helper.rb` sets `Shakha.config.service_secret`,
which no longer exists. Strategy: no `test/dummy` directory; boot a minimal in-process
Rails app inside `test_helper.rb` (the engine is small enough for this).

---

## Task 1.1 — Commit the pending working-tree changes

`git status` shows two real modifications that belong together:

- `app/controllers/shakha/application_controller.rb` — CSRF now skipped for JSON
- `Gemfile.lock` — version/bundler bump

Commit them as-is: `P1.1: Skip CSRF for JSON requests; refresh lockfile`.
Do NOT commit the untracked `.omo/*` / `.sisyphus/*` files (Phase 3 handles them).

## Task 1.2 — Remove forced middleware; make views render without an asset pipeline

**Why**: the engine currently force-inserts `ActionDispatch::Cookies` and a
`CookieStore` into every host app (`lib/shakha/engine.rb`) — this double-installs
session middleware in full Rails apps and will fight the dummy app. And the layout
uses `stylesheet_link_tag "shakha"`, which requires Sprockets/Propshaft that API
hosts (and our dummy app) don't have.

**Edit `lib/shakha/engine.rb`** — delete the entire
`initializer "shakha.add_middleware"` block (lines 7–10). Nothing replaces it here;
Phase 2 Task 2.5 makes the install generator handle API-mode hosts.

**Edit `app/views/shakha/layouts/shakha.html.erb`** — replace the line

```erb
<%= stylesheet_link_tag "shakha", "data-turbo-track": "reload" %>
```

with

```erb
<style><%= Shakha::Engine.root.join("app/assets/stylesheets/shakha.css").read.html_safe %></style>
```

Keep `app/assets/stylesheets/shakha.css` where it is (it's now just a data file the
layout inlines).

## Task 1.3 — Development dependencies + version-matrix Gemfiles

**Replace `Gemfile`** (full contents):

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

gemspec

gem "rake"
gem "minitest"

gem "rails", "~> 8.1.0"
gem "sqlite3", ">= 2.1"
gem "webmock"
gem "rubocop-rails-omakase", require: false
```

**Create `gemfiles/rails_71.gemfile`**:

```ruby
# frozen_string_literal: true

source "https://rubygems.org"

gemspec path: ".."

gem "rake"
gem "minitest"
gem "rails", "~> 7.1.0"
gem "sqlite3", "~> 1.7"
gem "webmock"
gem "rubocop-rails-omakase", require: false
```

**Create `gemfiles/rails_80.gemfile`** — same but `gem "rails", "~> 8.0.0"` and
`gem "sqlite3", ">= 2.1"`.

**Create `gemfiles/rails_81.gemfile`** — same but `gem "rails", "~> 8.1.0"` and
`gem "sqlite3", ">= 2.1"`.

Add to `.gitignore` (create the file if missing):

```
*.gem
gemfiles/*.lock
tmp/
```

Run `bundle install` and commit (including the updated `Gemfile.lock`).

## Task 1.4 — Rewrite the test helper around an in-process dummy app

**Delete** `test/fixtures/` entirely (all three YAML files). Records are created by
helpers instead — fixtures need a schema-managed DB and add nothing here.

**Replace `test/test_helper.rb`** (full contents):

```ruby
# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

require_relative "../lib/shakha"

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class DummyApp < Rails::Application
  config.load_defaults Rails::VERSION::STRING.to_f
  config.eager_load = false
  config.secret_key_base = "shakha-test-secret-key-base-not-for-production"
  config.hosts.clear
  config.logger = ActiveSupport::Logger.new(File::NULL)
  config.action_dispatch.show_exceptions = :none
end

Shakha.setup do |config|
  config.app_origin = "http://localhost:3000"
  config.google_client_id = "test_client_id"
  config.google_client_secret = "test_client_secret"
  config.github_client_id = "gh_test_id"
  config.github_client_secret = "gh_test_secret"
  config.providers = [:google, :github]
end

Rails.application.initialize!

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :shakha_clients do |t|
    t.string :name, null: false
    t.string :origin, null: false
    t.timestamps
    t.index :origin, unique: true
  end

  create_table :shakha_users do |t|
    t.references :client, null: false
    t.string :provider, null: false
    t.string :uid, null: false
    t.string :email
    t.string :name
    t.string :picture
    t.timestamps
    t.index %i[provider uid], unique: true
    t.index :email
  end

  create_table :shakha_sessions do |t|
    t.references :user
    t.references :client, null: false
    t.string :token, null: false
    t.string :ip_address
    t.string :user_agent
    t.timestamps
    t.index :token, unique: true
    t.index :created_at
  end
end

class ProtectedController < ActionController::Base
  include Shakha::ControllerHelpers

  before_action :authenticate!

  def show
    render json: { id: current_user.id, email: current_user.email }
  end
end

Rails.application.routes.draw do
  mount Shakha::Engine => "/auth/shakha"
  get "/protected", to: "protected#show"
end

require "minitest/autorun"
require "webmock/minitest"

module ShakhaTestHelpers
  def create_client(origin: "http://localhost:3000")
    Shakha::Client.find_or_create_by!(origin: origin) { |c| c.name = "Test App" }
  end

  def create_user(provider: "google", uid: "uid_123", email: "test@example.com")
    Shakha::User.create!(
      client: create_client, provider: provider, uid: uid,
      email: email, name: "Test User", picture: "https://example.com/p.jpg"
    )
  end

  def create_session_record(user: create_user)
    Shakha::Session.create!(user: user, client: create_client)
  end
end

class ActiveSupport::TestCase
  include ShakhaTestHelpers

  setup do
    Shakha::Session.delete_all
    Shakha::User.delete_all
    Shakha::Client.delete_all
    Shakha.config.allowed_redirect_origins = nil
    Shakha.config.rate_limiting_enabled = false
  end
end
```

Notes for the implementer:

- `ApplicationRecord` must be defined **before** any `Shakha::*` model is referenced
  — the engine models inherit from `::ApplicationRecord`, which the host app
  normally provides.
- `Shakha.setup` must run **before** `Rails.application.initialize!` because the
  engine validates config in `after_initialize`.
- The schema block mirrors `lib/generators/shakha/install/templates/create_shakha_tables.rb.erb`
  minus foreign-key constraints (SQLite in-memory doesn't need them). Whenever that
  template changes (Phase 2 changes it twice), update this block in the same commit.

**Verify**: `bundle exec rake test` now *loads* (it will fail on the old test files —
that's the next tasks). Run a single known-good file to confirm the harness:
`bundle exec ruby -Itest test/shakha/pkce_test.rb` → all pass (this file is
pure-unit and needs no changes).

## Task 1.5 — Rewrite the unit tests

Keep `test/shakha/pkce_test.rb` unchanged.

**Replace `test/shakha/config_test.rb`** (full contents):

```ruby
# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class ConfigTest < ActiveSupport::TestCase
    test "defaults" do
      config = Config.new
      assert_equal 30.days, config.session_lifetime
      assert_equal false, config.rate_limiting_enabled
      assert_equal [:google], config.providers
    end

    test "setup yields the singleton config" do
      original = Shakha.config.session_lifetime
      Shakha.setup { |c| c.session_lifetime = 1.day }
      assert_equal 1.day, Shakha.config.session_lifetime
    ensure
      Shakha.config.session_lifetime = original
    end

    test "validator passes when required values present" do
      assert ConfigValidator.validate!(Shakha.config)
    end
  end
end
```

**Replace `test/shakha/session_test.rb`** (full contents):

```ruby
# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class SessionTest < ActiveSupport::TestCase
    test "generates a token on create" do
      session = create_session_record
      assert session.token.present?
      assert_operator session.token.length, :>=, 43
    end

    test "does not overwrite an explicit token" do
      session = Shakha::Session.create!(user: create_user, client: create_client, token: "explicit")
      assert_equal "explicit", session.token
    end

    test "active scope excludes expired sessions" do
      fresh = create_session_record
      stale = create_session_record(user: create_user(uid: "other"))
      stale.update_columns(created_at: (Shakha.config.session_lifetime + 1.day).ago)

      assert_includes Shakha::Session.active, fresh
      refute_includes Shakha::Session.active, stale
      assert stale.expired?
      refute fresh.expired?
    end

    test "expires_at is created_at plus lifetime" do
      session = create_session_record
      assert_in_delta (session.created_at + Shakha.config.session_lifetime).to_f,
                      session.expires_at.to_f, 1.0
    end
  end
end
```

**Replace `test/shakha/user_test.rb`** (full contents):

```ruby
# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class UserTest < ActiveSupport::TestCase
    test "requires provider and uid" do
      user = Shakha::User.new(client: create_client)
      refute user.valid?
      assert user.errors[:provider].any?
      assert user.errors[:uid].any?
    end

    test "uid is unique per provider" do
      create_user(provider: "google", uid: "dup")
      dup = Shakha::User.new(client: create_client, provider: "google", uid: "dup")
      refute dup.valid?

      other_provider = Shakha::User.new(client: create_client, provider: "github", uid: "dup")
      assert other_provider.valid?
    end

    test "destroying a user destroys its sessions" do
      user = create_user
      create_session_record(user: user)
      assert_difference -> { Shakha::Session.count }, -1 { user.destroy }
    end
  end
end
```

## Task 1.6 — Integration tests for the full OAuth + session flow

**Replace `test/shakha/auth_flow_test.rb`** (full contents):

```ruby
# frozen_string_literal: true

require_relative "../test_helper"
require "jwt"

module Shakha
  class AuthFlowTest < ActionDispatch::IntegrationTest
    test "sign-in page renders a button per configured provider" do
      get "/auth/shakha"
      assert_response :success
      assert_select "a[href='/auth/shakha/google']"
      assert_select "a[href='/auth/shakha/github']"
    end

    test "authorize redirects to Google with PKCE params" do
      get "/auth/shakha/google"
      assert_response :redirect

      uri = URI.parse(response.redirect_url)
      params = URI.decode_www_form(uri.query).to_h

      assert_equal "accounts.google.com", uri.host
      assert_equal "test_client_id", params["client_id"]
      assert_equal "S256", params["code_challenge_method"]
      assert params["code_challenge"].present?
      assert params["state"].present?
      assert params["nonce"].present?
      assert_equal "http://localhost:3000/auth/shakha/google/callback", params["redirect_uri"]
    end

    test "unknown provider raises a configuration error response" do
      get "/auth/shakha/nonexistent"
      assert_response :bad_gateway
    rescue Shakha::ConfigurationError
      pass # acceptable until Phase 2 maps this to a 4xx
    end

    test "full google flow: authorize, callback, bearer session" do
      auth = start_google_authorize(return_to: "http://localhost:3000/done")
      stub_google_token(id_token: google_id_token(nonce: auth[:nonce]))

      get "/auth/shakha/google/callback", params: { code: "auth_code", state: auth[:state] }
      assert_response :redirect

      redirect = URI.parse(response.redirect_url)
      assert_equal "/done", redirect.path
      params = URI.decode_www_form(redirect.query).to_h
      token = params["token"]
      assert token.present?
      assert params["expires_at"].present?

      get "/auth/shakha/session", headers: { "Authorization" => "Bearer #{token}" }
      assert_response :success
      body = JSON.parse(response.body)
      assert_equal "user@example.com", body["user"]["email"]
      assert_equal "google", body["user"]["provider"]
    end

    test "callback with mismatched state fails without creating a session" do
      start_google_authorize

      assert_no_difference -> { Shakha::Session.count } do
        get "/auth/shakha/google/callback", params: { code: "auth_code", state: "forged" }
      end
      assert_response :redirect
      assert_includes response.redirect_url, "error="
    end

    test "callback without a PKCE cookie fails" do
      assert_no_difference -> { Shakha::Session.count } do
        get "/auth/shakha/google/callback", params: { code: "auth_code", state: "whatever" }
      end
      assert_response :redirect
      assert_includes response.redirect_url, "error="
    end

    test "return_to on a foreign origin is rejected unless allowlisted" do
      get "/auth/shakha", params: { return_to: "https://evil.com/steal" }
      assert_response :success

      Shakha.config.allowed_redirect_origins = ["https://myfrontend.com"]
      auth = start_google_authorize(return_to: "https://myfrontend.com/login")
      stub_google_token(id_token: google_id_token(nonce: auth[:nonce]))

      get "/auth/shakha/google/callback", params: { code: "auth_code", state: auth[:state] }
      assert_response :redirect
      assert URI.parse(response.redirect_url).host == "myfrontend.com"
    end

    test "session endpoints require auth" do
      get "/auth/shakha/session"
      assert_response :unauthorized

      get "/auth/shakha/session/check"
      assert_response :unauthorized
      assert_equal "expired", JSON.parse(response.body)["status"]
    end

    test "session check returns active for a valid bearer token" do
      session_record = create_session_record
      get "/auth/shakha/session/check",
          headers: { "Authorization" => "Bearer #{session_record.token}" }
      assert_response :success
      assert_equal "active", JSON.parse(response.body)["status"]
    end

    test "sign out destroys the session" do
      session_record = create_session_record

      delete "/auth/shakha/sign_out",
             headers: { "Authorization" => "Bearer #{session_record.token}", "Accept" => "application/json" }
      assert_response :success
      assert_nil Shakha::Session.find_by(id: session_record.id)

      get "/auth/shakha/session",
          headers: { "Authorization" => "Bearer #{session_record.token}" }
      assert_response :unauthorized
    end

    test "authenticate! in a host controller: 401 JSON, 302 HTML" do
      get "/protected", headers: { "Accept" => "application/json" }
      assert_response :unauthorized

      get "/protected"
      assert_response :redirect
      assert_includes response.redirect_url, "/auth/shakha"
    end

    test "authenticate! passes with a valid bearer token" do
      session_record = create_session_record
      get "/protected", headers: { "Authorization" => "Bearer #{session_record.token}" }
      assert_response :success
      assert_equal session_record.user.email, JSON.parse(response.body)["email"]
    end

    test "expired session token is rejected" do
      session_record = create_session_record
      session_record.update_columns(created_at: (Shakha.config.session_lifetime + 1.day).ago)

      get "/protected", headers: { "Authorization" => "Bearer #{session_record.token}" }
      assert_response :unauthorized
    end

    private

    # Drives the authorize step and extracts state + nonce from the URL Shakha
    # sends the browser to (they also live in the encrypted PKCE cookie, which the
    # integration session carries to the callback automatically).
    def start_google_authorize(return_to: nil)
      path = "/auth/shakha/google"
      path += "?return_to=#{CGI.escape(return_to)}" if return_to
      get path
      assert_response :redirect

      params = URI.decode_www_form(URI.parse(response.redirect_url).query).to_h
      { state: params["state"], nonce: params["nonce"] }
    end

    def stub_google_token(id_token:)
      stub_request(:post, "https://oauth2.googleapis.com/token")
        .to_return(
          status: 200,
          body: { access_token: "ya29.test", id_token: id_token,
                  token_type: "Bearer", expires_in: 3600 }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    def google_id_token(nonce:, sub: "google_123", email: "user@example.com")
      JWT.encode({
        iss: "https://accounts.google.com",
        aud: "test_client_id",
        sub: sub,
        email: email,
        email_verified: true,
        name: "Test User",
        picture: "https://example.com/photo.jpg",
        nonce: nonce,
        iat: Time.now.to_i,
        exp: Time.now.to_i + 3600
      }, nil, "none")
    end
  end
end
```

Note: in Phase 1 the app doesn't yet verify the nonce (that's Phase 2), but the test
tokens already carry the correct one so these tests survive Phase 2 unchanged.

## Task 1.7 — Provider + generator tests

**Create `test/shakha/providers/google_test.rb`**, **`github_test.rb`**, and
**`registry_test.rb`** — port them verbatim from `.omo/plans/06-phase-5-testing.md`
(sections "Test: GitHub Provider" and "Test: Provider Registry"), with these
adjustments:

- `require_relative "../../test_helper"` at the top of each.
- In `github_test.rb`, the setup values are already set globally in the test helper;
  keep the per-test file setup anyway (it's harmless and documents intent).
- Add a `google_test.rb` mirroring the GitHub one: assert `authorize_url` contains
  `code_challenge`, `code_challenge_method=S256`, `access_type=offline`; assert
  `exchange_code` posts `code_verifier` to `https://oauth2.googleapis.com/token`
  (use `stub_request(...).with(body: hash_including("code_verifier" => "v"))`);
  assert `identity_from_response` extracts uid/email/name/picture from an unsigned
  test ID token (reuse the `google_id_token` pattern from Task 1.6 — put a copy in
  the file; do not share helpers across files yet).

**Create `test/shakha/install_generator_test.rb`** (full contents):

```ruby
# frozen_string_literal: true

require_relative "../test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/shakha/install/install_generator"

module Shakha
  class InstallGeneratorTest < Rails::Generators::TestCase
    tests Shakha::Generators::InstallGenerator
    destination File.expand_path("../../tmp/generator_test", __dir__)
    setup :prepare_destination

    test "creates the migration and initializer" do
      run_generator

      assert_migration "db/migrate/create_shakha_tables.rb" do |content|
        assert_match(/create_table :shakha_users/, content)
        assert_match(/create_table :shakha_sessions/, content)
      end

      assert_file "config/initializers/shakha.rb" do |content|
        assert_match(/Shakha\.setup/, content)
        assert_match(/GOOGLE_CLIENT_ID/, content)
      end
    end

    test "injects ControllerHelpers into an existing ApplicationController" do
      FileUtils.mkdir_p(File.join(destination_root, "app/controllers"))
      File.write(File.join(destination_root, "app/controllers/application_controller.rb"),
                 "class ApplicationController < ActionController::API\nend\n")

      run_generator

      assert_file "app/controllers/application_controller.rb" do |content|
        assert_match(/include Shakha::ControllerHelpers/, content)
      end
    end
  end
end
```

**Verify**: `bundle exec rake test` — entire suite green.

## Task 1.8 — RuboCop

**Create `.rubocop.yml`**:

```yaml
inherit_gem:
  rubocop-rails-omakase: rubocop.yml

AllCops:
  TargetRubyVersion: 3.1
  SuggestExtensions: false
  Exclude:
    - "gemfiles/**/*"
    - "tmp/**/*"
    - "vendor/**/*"
```

Run `bundle exec rubocop -a`, then fix remaining offenses by hand. Do not disable
cops in code comments; if a cop is genuinely wrong for this repo, exclude it in
`.rubocop.yml` with a one-line reason comment. Re-run the tests.

## Task 1.9 — GitHub Actions CI

**Create `.github/workflows/ci.yml`** (full contents):

```yaml
name: CI

on:
  push:
    branches: [master]
  pull_request:

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.4"
          bundler-cache: true
      - run: bundle exec rubocop

  test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - { ruby: "3.1", gemfile: gemfiles/rails_71.gemfile }
          - { ruby: "3.2", gemfile: gemfiles/rails_71.gemfile }
          - { ruby: "3.2", gemfile: gemfiles/rails_80.gemfile }
          - { ruby: "3.3", gemfile: gemfiles/rails_81.gemfile }
          - { ruby: "3.4", gemfile: gemfiles/rails_80.gemfile }
          - { ruby: "3.4", gemfile: gemfiles/rails_81.gemfile }
    env:
      BUNDLE_GEMFILE: ${{ github.workspace }}/${{ matrix.gemfile }}
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true
      - run: bundle exec rake test
```

Verify the matrix locally for at least one alternate cell:
`BUNDLE_GEMFILE=gemfiles/rails_71.gemfile bundle install && BUNDLE_GEMFILE=gemfiles/rails_71.gemfile bundle exec rake test`.
If Rails 7.1 fails on something Rails-8-specific (e.g. `show_exceptions = :none`
symbol form is 7.1+, fine; `cache.increment expires_in` differences don't matter —
rate limiting is off in tests), fix forward in the library, not with version
branches in tests.

## Task 1.10 — Ship v0.6.0

- `lib/shakha/version.rb` → `0.6.0`; run `bundle install` to refresh the lockfile.
- Full suite + rubocop green.
- Commit: `P1.10: v0.6.0 — test harness and CI`.

**Phase exit criteria**: fresh clone + `bundle install && bundle exec rake test`
passes; CI workflow file present; rubocop clean.
