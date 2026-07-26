# frozen_string_literal: true

require_relative "../../test_helper"
require "jwt"

module Shakha
  module Providers
    class GoogleTest < ActiveSupport::TestCase
      setup { @provider = Google.new }

      test "provider_name" do
        assert_equal :google, @provider.provider_name
      end

      test "builds an authorize URL with PKCE params" do
        url = @provider.authorize_url(
          state: "st", code_challenge: "ch",
          redirect_uri: "http://localhost:3000/auth/shakha/google/callback"
        )
        params = URI.decode_www_form(URI.parse(url).query).to_h

        assert_equal "test_client_id", params["client_id"]
        assert_equal "ch", params["code_challenge"]
        assert_equal "S256", params["code_challenge_method"]
        assert_equal "st", params["state"]
        assert_equal "offline", params["access_type"]
        assert_includes params["scope"], "openid"
      end

      test "exchanges the code, sending the verifier to Google's token endpoint" do
        stub = stub_request(:post, "https://oauth2.googleapis.com/token")
               .with(body: hash_including("code_verifier" => "v", "code" => "c"))
               .to_return(status: 200, body: { id_token: "x" }.to_json,
                          headers: { "Content-Type" => "application/json" })

        @provider.exchange_code(code: "c", code_verifier: "v",
                                redirect_uri: "http://localhost:3000/cb")
        assert_requested stub
      end

      test "extracts identity from the id_token" do
        id_token = JWT.encode({
          sub: "google_9", email: "e@example.com", name: "Ellen",
          picture: "https://example.com/e.jpg"
        }, nil, "none")

        identity = @provider.identity_from_response({ "id_token" => id_token })

        assert_equal :google, identity[:provider]
        assert_equal "google_9", identity[:uid]
        assert_equal "e@example.com", identity[:email]
        assert_equal "Ellen", identity[:name]
      end

      test "raises when no id_token is present" do
        assert_raises(Shakha::OAuthError) { @provider.identity_from_response({}) }
      end
    end
  end
end
