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

      test "extracts identity from a valid id_token" do
        response = { "id_token" => id_token(nonce: "n") }
        identity = @provider.identity_from_response(response, expected_nonce: "n")

        assert_equal :google, identity[:provider]
        assert_equal "google_9", identity[:uid]
        assert_equal "e@example.com", identity[:email]
        assert_equal "Ellen", identity[:name]
      end

      test "raises when no id_token is present" do
        assert_raises(Shakha::OAuthError) { @provider.identity_from_response({}) }
      end

      test "rejects a token with the wrong audience" do
        response = { "id_token" => id_token(aud: "someone_else") }
        error = assert_raises(Shakha::OAuthError) { @provider.identity_from_response(response) }
        assert_match(/audience/, error.message)
      end

      test "rejects a token with an untrusted issuer" do
        response = { "id_token" => id_token(iss: "https://evil.example") }
        error = assert_raises(Shakha::OAuthError) { @provider.identity_from_response(response) }
        assert_match(/issuer/, error.message)
      end

      test "rejects an expired token" do
        response = { "id_token" => id_token(exp: Time.now.to_i - 60) }
        error = assert_raises(Shakha::OAuthError) { @provider.identity_from_response(response) }
        assert_match(/expired/, error.message)
      end

      test "rejects a nonce mismatch" do
        response = { "id_token" => id_token(nonce: "real") }
        error = assert_raises(Shakha::OAuthError) do
          @provider.identity_from_response(response, expected_nonce: "forged")
        end
        assert_match(/nonce/, error.message)
      end

      private

      def id_token(sub: "google_9", email: "e@example.com", name: "Ellen",
                   iss: "https://accounts.google.com", aud: "test_client_id",
                   exp: Time.now.to_i + 3600, nonce: nil)
        JWT.encode({
          sub: sub, email: email, name: name, picture: "https://example.com/e.jpg",
          iss: iss, aud: aud, exp: exp, nonce: nonce
        }, nil, "none")
      end
    end
  end
end
