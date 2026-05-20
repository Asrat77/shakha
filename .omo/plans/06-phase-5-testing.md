# Phase 5: Testing — SPA Flow + Multi-Provider

End-to-end testing of the SPA token redirect flow and both providers.

---

## Test: SPA OAuth Flow (Google)

```ruby
module Shakha
  class SPAOAuthFlowTest < ActionDispatch::IntegrationTest
    setup do
      Shakha.config.app_origin = "https://api.yourapp.com"
      Shakha.config.google_client_id = "test_client_id"
      Shakha.config.google_client_secret = "test_client_secret"
      Shakha.config.providers = [:google]
    end

    test "authorize redirects to Google with correct params" do
      get "/auth/shakha/google/authorize?return_to=https://app.yourapp.com/login"

      assert_response :redirect
      redirect_url = response.redirect_url

      assert_includes redirect_url, "accounts.google.com"
      assert_includes redirect_url, "client_id=test_client_id"
      assert_includes redirect_url, "code_challenge="
      assert_includes redirect_url, "code_challenge_method=S256"
      assert_includes redirect_url, "state="
    end

    test "callback returns token in redirect URL for SPA" do
      # Mock Google's token endpoint
      id_token = generate_test_id_token(sub: "google_123", email: "test@example.com")
      stub_google_token_endpoint(id_token: id_token)

      # First authorize to set PKCE cookie
      get "/auth/shakha/google/authorize?return_to=https://app.yourapp.com/login"
      state = extract_state_from_cookie

      # Simulate Google callback
      get "/auth/shakha/google/callback", params: { code: "auth_code_123", state: state }

      assert_response :redirect
      redirect_url = response.redirect_url

      # Should redirect to the return_to URL with token
      assert_includes redirect_url, "app.yourapp.com/login"
      assert_includes redirect_url, "token="
      assert_includes redirect_url, "expires_at="

      # Extract token from URL
      uri = URI.parse(redirect_url)
      params = URI.decode_www_form(uri.query).to_h
      token = params["token"]
      assert token.present?

      # Token should work for Bearer auth
      get "/auth/shakha/session", headers: { "Authorization" => "Bearer #{token}" }
      assert_response :success

      body = JSON.parse(response.body)
      assert_equal "test@example.com", body["user"]["email"]
      assert_equal "Test User", body["user"]["name"]
      assert_equal "google", body["user"]["provider"]
    end

    test "session check returns active for valid token" do
      user = create_test_user
      session_record = Shakha::Session.create!(user: user, client: Shakha::Client.first!)

      get "/auth/shakha/session/check",
          headers: { "Authorization" => "Bearer #{session_record.token}" }

      assert_response :success
      assert_equal "active", JSON.parse(response.body)["status"]
    end

    test "session check returns expired for invalid token" do
      get "/auth/shakha/session/check",
          headers: { "Authorization" => "Bearer invalid_token" }

      assert_response :unauthorized
    end

    test "authenticate! returns 401 JSON for API requests" do
      get "/protected",
          headers: { "Accept" => "application/json" }

      assert_response :unauthorized
      assert_equal "Authentication required", JSON.parse(response.body)["error"]
    end

    test "authenticate! returns 302 redirect for HTML requests" do
      get "/protected"

      assert_response :redirect
      assert_includes response.redirect_url, "/auth/shakha"
    end

    test "sign out destroys session and cookie" do
      user = create_test_user
      session_record = Shakha::Session.create!(user: user, client: Shakha::Client.first!)
      cookies["shakha_session_token"] = session_record.token

      delete "/auth/shakha/session"

      assert_response :success
      assert_equal "signed_out", JSON.parse(response.body)["status"]
      assert_raises(ActiveRecord::RecordNotFound) { session_record.reload }
    end

    private

    def create_test_user(provider: "google", uid: "google_123")
      client = Shakha::Client.find_or_create_by!(origin: "https://api.yourapp.com") { |c| c.name = "Test" }
      Shakha::User.create!(provider: provider, uid: uid, client: client, email: "test@example.com")
    end

    def extract_state_from_cookie
      pkce_cookie = cookies["shakha_pkce"]
      JSON.parse(pkce_cookie)["state"]
    end

    def stub_google_token_endpoint(id_token:)
      stub_request(:post, "https://oauth2.googleapis.com/token")
        .to_return(status: 200, body: {
          access_token: "ya29.test",
          id_token: id_token,
          token_type: "Bearer",
          expires_in: 3600
        }.to_json, headers: { "Content-Type" => "application/json" })
    end

    def generate_test_id_token(sub:, email:)
      JWT.encode({
        iss: "https://accounts.google.com",
        sub: sub,
        email: email,
        email_verified: true,
        name: "Test User",
        picture: "https://example.com/photo.jpg",
        aud: "test_client_id",
        iat: Time.now.to_i,
        exp: Time.now.to_i + 3600
      }, nil, "none")
    end
  end
end
```

---

## Test: GitHub Provider

```ruby
module Shakha
  module Providers
    class GitHubTest < ActiveSupport::TestCase
      setup do
        Shakha.config.github_client_id = "gh_test_id"
        Shakha.config.github_client_secret = "gh_test_secret"
        @provider = GitHub.new
      end

      test "builds authorize URL" do
        url = @provider.authorize_url(
          state: "test_state",
          code_challenge: "test_challenge",
          redirect_uri: "https://api.yourapp.com/auth/shakha/github/callback"
        )

        uri = URI.parse(url)
        params = URI.decode_www_form(uri.query).to_h

        assert_equal "gh_test_id", params["client_id"]
        assert_equal "test_state", params["state"]
        assert_includes params["scope"], "user:email"
      end

      test "exchanges code for access token" do
        stub_request(:post, "https://github.com/login/oauth/access_token")
          .to_return(
            status: 200,
            body: { access_token: "gho_test_token" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )

        response = @provider.exchange_code(
          code: "test_code",
          code_verifier: "test_verifier",
          redirect_uri: "https://api.yourapp.com/callback"
        )

        assert_equal "gho_test_token", response["access_token"]
      end

      test "fetches user identity" do
        stub_request(:get, "https://api.github.com/user")
          .with(headers: { "Authorization" => "Bearer gho_test_token" })
          .to_return(status: 200, body: {
            id: 12345,
            login: "testuser",
            name: "Test User",
            email: "test@github.com",
            avatar_url: "https://avatars.githubusercontent.com/u/12345"
          }.to_json, headers: { "Content-Type" => "application/json" })

        identity = @provider.identity_from_response({ "access_token" => "gho_test_token" })

        assert_equal :github, identity[:provider]
        assert_equal "12345", identity[:uid]
        assert_equal "test@github.com", identity[:email]
        assert_equal "Test User", identity[:name]
      end
    end
  end
end
```

---

## Test: Provider Registry

```ruby
module Shakha
  module Providers
    class RegistryTest < ActiveSupport::TestCase
      test "resolves google provider" do
        provider = Providers.resolve(:google)
        assert_instance_of Google, provider
      end

      test "resolves github provider" do
        provider = Providers.resolve(:github)
        assert_instance_of GitHub, provider
      end

      test "raises on unknown provider" do
        assert_raises(RuntimeError) { Providers.resolve(:unknown) }
      end
    end
  end
end
```

---

## Test Files After Phase 5

```
test/shakha/
├── sp_auth_flow_test.rb       # SPA token redirect + Bearer auth
├── pkce_test.rb               # PKCE verification (updated)
├── config_test.rb             # Config validation
├── session_test.rb            # Session model + active scope
├── user_test.rb               # User model validations
└── providers/
    ├── google_test.rb         # Google provider
    ├── github_test.rb         # GitHub provider
    └── registry_test.rb       # Provider registry
```

## Validation Checklist

- [ ] `bundle exec rake test` — all tests pass
- [ ] Real Google OAuth: redirect → callback → token in URL → Bearer auth → session endpoint
- [ ] Real GitHub OAuth: same flow works
- [ ] `rails generate shakha:install` on fresh Rails 7.1 API app
- [ ] React app can: redirect → get token from URL → store → call `/auth/shakha/session` → render user
- [ ] Token stored in cookie simultaneously (Rails monolith path still works)
- [ ] Rate limiter protects `/authorize` and `/callback`
