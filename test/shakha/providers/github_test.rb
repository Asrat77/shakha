# frozen_string_literal: true

require_relative "../../test_helper"

module Shakha
  module Providers
    class GitHubTest < ActiveSupport::TestCase
      setup { @provider = GitHub.new }

      test "provider_name" do
        assert_equal :github, @provider.provider_name
      end

      test "builds an authorize URL" do
        url = @provider.authorize_url(
          state: "st", code_challenge: "ch",
          redirect_uri: "http://localhost:3000/auth/shakha/github/callback"
        )
        params = URI.decode_www_form(URI.parse(url).query).to_h

        assert_equal "gh_test_id", params["client_id"]
        assert_equal "st", params["state"]
        assert_includes params["scope"], "user:email"
      end

      test "exchanges a code for an access token" do
        stub_request(:post, "https://github.com/login/oauth/access_token")
          .to_return(status: 200, body: { access_token: "gho_x" }.to_json,
                     headers: { "Content-Type" => "application/json" })

        response = @provider.exchange_code(code: "c", code_verifier: "v",
                                           redirect_uri: "http://localhost:3000/cb")
        assert_equal "gho_x", response["access_token"]
      end

      test "fetches user identity from the GitHub API" do
        stub_request(:get, "https://api.github.com/user")
          .with(headers: { "Authorization" => "Bearer gho_x" })
          .to_return(status: 200, body: {
            id: 42, login: "octo", name: "Octo Cat",
            email: "octo@github.com", avatar_url: "https://avatars.example/42"
          }.to_json, headers: { "Content-Type" => "application/json" })

        identity = @provider.identity_from_response({ "access_token" => "gho_x" })

        assert_equal :github, identity[:provider]
        assert_equal "42", identity[:uid]
        assert_equal "octo@github.com", identity[:email]
        assert_equal "Octo Cat", identity[:name]
      end

      test "raises when no access_token is present" do
        assert_raises(Shakha::OAuthError) { @provider.identity_from_response({}) }
      end
    end
  end
end
