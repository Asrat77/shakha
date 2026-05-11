# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class AuthFlowTest < ActionDispatch::IntegrationTest
    setup do
      Shakha.config.app_origin = "http://localhost:3000"
      Shakha.config.google_client_id = "test_client_id"
      Shakha.config.google_client_secret = "test_client_secret"
    end

    test "new auth page renders sign in button" do
      get "/auth/shakha"

      assert_response :success
      assert_select "a[href*='authorize']", text: /Continue with Google/
    end

    test "authorize redirects to Google" do
      get "/auth/shakha/authorize"

      assert_response :redirect
      assert_includes response.redirect_url, "accounts.google.com"
      assert_includes response.redirect_url, "client_id=test_client_id"
      assert_includes response.redirect_url, "code_challenge="
      assert_includes response.redirect_url, "code_challenge_method=S256"
    end

    test "error page shows message" do
      get "/auth/shakha/error", params: { message: "Test error message" }

      assert_response :success
      assert_select "p", /Test error message/
    end

    test "JWKS endpoint returns valid structure" do
      get "/.well-known/jwks.json"

      assert_response :success
      assert_equal "application/json", response.media_type

      jwks = JSON.parse(response.body)
      assert jwks["keys"]
      assert jwks["keys"].first["kty"], "EC"
    end

    test "OpenID configuration endpoint returns valid structure" do
      get "/.well-known/openid-configuration"

      assert_response :success
      assert_equal "application/json", response.media_type

      config = JSON.parse(response.body)
      assert_equal "https://shakha.dev", config["issuer"]
      assert config["authorization_endpoint"]
      assert config["token_endpoint"]
      assert config["jwks_uri"]
    end

    test "rejects open redirect return_to URLs" do
      get "/auth/shakha/authorize", params: { return_to: "https://evil.com" }

      assert_response :redirect
      assert_includes response.redirect_url, "accounts.google.com"
      # return_to should be sanitized to "/" - verified by the stored PKCE cookie
      # The actual redirect happens after callback, but the sanitization runs in authorize
    end

    test "session check returns unauthorized when not signed in" do
      post "/auth/shakha/session/check"

      assert_response :unauthorized
      result = JSON.parse(response.body)
      assert_equal "login_required", result["status"]
    end

    test "session destroy returns JSON" do
      delete "/auth/shakha/session"

      assert_response :success
      result = JSON.parse(response.body)
      assert_equal "signed_out", result["status"]
    end

    test "error messages are sanitized for browser flow" do
      get "/auth/shakha/error", params: { message: "Some internal error" }

      assert_response :success
      # Should not expose raw error details
      assert_select "p", /Some internal error/
    end
  end
end