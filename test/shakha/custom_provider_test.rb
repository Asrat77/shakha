# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../support/gitlab_provider"

module Shakha
  class CustomProviderTest < ActionDispatch::IntegrationTest
    setup do
      Providers.register(:gitlab, GitLabProvider)
      Shakha.config.providers = [ :google, :github, :gitlab ]
      ENV["GITLAB_CLIENT_ID"] = "gl_id"
      ENV["GITLAB_CLIENT_SECRET"] = "gl_secret"
    end

    teardown do
      Providers.reset!
      Shakha.config.providers = [ :google, :github ]
      ENV.delete("GITLAB_CLIENT_ID")
      ENV.delete("GITLAB_CLIENT_SECRET")
    end

    test "a registered provider runs the full flow with PKCE" do
      get "/auth/shakha/gitlab"
      assert_response :redirect
      uri = URI.parse(response.redirect_url)
      params = URI.decode_www_form(uri.query).to_h
      assert_equal "gitlab.com", uri.host
      assert_equal "gl_id", params["client_id"]
      assert_equal "S256", params["code_challenge_method"]
      assert_equal "http://localhost:3000/auth/shakha/gitlab/callback", params["redirect_uri"]

      token_stub = stub_request(:post, "https://gitlab.com/oauth/token")
        .with { |req| URI.decode_www_form(req.body).to_h["code_verifier"].present? }
        .to_return(status: 200, body: { access_token: "glpat" }.to_json,
                   headers: { "Content-Type" => "application/json" })
      stub_request(:get, "https://gitlab.com/api/v4/user")
        .with(headers: { "Authorization" => "Bearer glpat" })
        .to_return(status: 200, body: {
          id: 7, username: "tanuki", name: "Tanuki", email: "tanuki@gitlab.com",
          avatar_url: "https://gitlab.example/7.png"
        }.to_json, headers: { "Content-Type" => "application/json" })

      assert_difference -> { Shakha::Session.count }, 1 do
        get "/auth/shakha/gitlab/callback", params: { code: "c", state: params["state"] }
      end
      assert_requested token_stub
      user = Shakha::User.find_by(provider: "gitlab", uid: "7")
      assert_equal "tanuki@gitlab.com", user.email
    end

    test "the sign-in page lists the registered provider" do
      get "/auth/shakha"
      assert_select "a[href='/auth/shakha/gitlab']"
    end
  end
end
