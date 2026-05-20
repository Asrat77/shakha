# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class AuthFlowTest < ActionDispatch::IntegrationTest
    setup do
      Shakha.config.app_origin = "http://localhost:3000"
      Shakha.config.google_client_id = "test_client_id"
      Shakha.config.google_client_secret = "test_client_secret"
    end

    test "sign-in page renders" do
      get "/auth/shakha"

      assert_response :success
      assert_select "a[href*='/auth/shakha/']"
    end

    test "google authorize redirects to Google with PKCE params" do
      get "/auth/shakha/google"

      assert_response :redirect
      assert_includes response.redirect_url, "accounts.google.com"
      assert_includes response.redirect_url, "code_challenge="
      assert_includes response.redirect_url, "code_challenge_method=S256"
      assert_includes response.redirect_url, "state="
    end

    test "rejects open redirect return_to URLs" do
      Shakha.config.allowed_redirect_origins = ["https://myfrontend.com"]

      get "/auth/shakha/google", params: { return_to: "https://evil.com/steal" }

      assert_response :redirect
    end

    test "session check returns expired when not signed in" do
      get "/auth/shakha/session/check"

      assert_response :unauthorized
      assert_equal "expired", JSON.parse(response.body)["status"]
    end

    test "session endpoint returns unauthorized when not signed in" do
      get "/auth/shakha/session"

      assert_response :unauthorized
    end

    test "sign out returns JSON" do
      delete "/auth/shakha/sign_out"

      assert_response :success
      assert_equal "signed_out", JSON.parse(response.body)["status"]
    end

    test "error page shows message" do
      get "/auth/shakha/error", params: { message: "Something went wrong" }

      assert_response :success
    end
  end
end