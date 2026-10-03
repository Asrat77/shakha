# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../support/gitlab_provider"

# Mirrors the testing section of docs/providers.md.
class GitLabProviderTest < ActiveSupport::TestCase
  setup { @provider = GitLabProvider.new(client_id: "gl_id", client_secret: "gl_secret") }

  test "provider_name" do
    assert_equal :gitlab, @provider.provider_name
  end

  test "builds an authorize URL with PKCE" do
    url = @provider.authorize_url(
      state: "st", code_challenge: "ch",
      redirect_uri: "http://localhost:3000/auth/shakha/gitlab/callback"
    )
    params = URI.decode_www_form(URI.parse(url).query).to_h

    assert_equal "gl_id", params["client_id"]
    assert_equal "st", params["state"]
    assert_equal "ch", params["code_challenge"]
    assert_equal "S256", params["code_challenge_method"]
  end

  test "exchanges a code for an access token" do
    stub_request(:post, "https://gitlab.com/oauth/token")
      .to_return(status: 200, body: { access_token: "glpat" }.to_json,
                 headers: { "Content-Type" => "application/json" })

    response = @provider.exchange_code(code: "c", code_verifier: "v",
                                       redirect_uri: "http://localhost:3000/cb")
    assert_equal "glpat", response["access_token"]
  end

  test "fetches user identity from the GitLab API" do
    stub_request(:get, "https://gitlab.com/api/v4/user")
      .with(headers: { "Authorization" => "Bearer glpat" })
      .to_return(status: 200, body: {
        id: 7, username: "tanuki", name: "Tanuki",
        email: "tanuki@gitlab.com", avatar_url: "https://gitlab.example/7.png"
      }.to_json, headers: { "Content-Type" => "application/json" })

    identity = @provider.identity_from_response({ "access_token" => "glpat" })

    assert_equal :gitlab, identity[:provider]
    assert_equal "7", identity[:uid]
    assert_equal "tanuki@gitlab.com", identity[:email]
  end

  test "raises when no access_token is present" do
    assert_raises(Shakha::OAuthError) { @provider.identity_from_response({}) }
  end
end
