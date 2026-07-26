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

      Shakha.config.allowed_redirect_origins = [ "https://myfrontend.com" ]
      auth = start_google_authorize(return_to: "https://myfrontend.com/login")
      stub_google_token(id_token: google_id_token(nonce: auth[:nonce]))

      get "/auth/shakha/google/callback", params: { code: "auth_code", state: auth[:state] }
      assert_response :redirect
      assert_equal "myfrontend.com", URI.parse(response.redirect_url).host
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

      get "/protected", headers: { "Authorization" => "Bearer #{session_record.token}",
                                   "Accept" => "application/json" }
      assert_response :unauthorized
    end

    private

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
