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
  end
end