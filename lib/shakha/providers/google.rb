# frozen_string_literal: true

require "net/http"
require "uri"

module Shakha
  module Providers
    class Google < Base
      AUTHORIZE_URL = "https://accounts.google.com/o/oauth2/v2/auth"
      TOKEN_URL = "https://oauth2.googleapis.com/token"

      def provider_name
        :google
      end

      def authorize_url(state:, code_challenge:, redirect_uri:, nonce: nil)
        params = {
          client_id: Shakha.config.google_client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: scopes.join(" "),
          code_challenge: code_challenge,
          code_challenge_method: "S256",
          state: state,
          access_type: "offline",
          prompt: "consent",
          nonce: nonce
        }

        "#{AUTHORIZE_URL}?#{URI.encode_www_form(params)}"
      end

      def exchange_code(code:, code_verifier:, redirect_uri:)
        response = http_post(TOKEN_URL, {
          code: code,
          client_id: Shakha.config.google_client_id,
          client_secret: Shakha.config.google_client_secret,
          redirect_uri: redirect_uri,
          grant_type: "authorization_code",
          code_verifier: code_verifier
        })

        JSON.parse(response.body)
      end

      def identity_from_response(token_response, expected_nonce: nil)
        id_token = token_response["id_token"]
        raise OAuthError, "No id_token received" unless id_token

        # Signature is not re-verified: the token comes directly from Google's
        # token endpoint over a TLS connection we initiated, so its provenance
        # is the transport. The claims below still need checking.
        payload = JWT.decode(id_token, nil, false)[0]
        verify_claims!(payload, expected_nonce)

        {
          provider: :google,
          uid: payload["sub"],
          email: payload["email"],
          name: payload["name"],
          picture: payload["picture"]
        }
      end

      def scopes
        %w[openid email profile]
      end

      private

      VALID_ISSUERS = [ "https://accounts.google.com", "accounts.google.com" ].freeze

      def verify_claims!(payload, expected_nonce)
        unless VALID_ISSUERS.include?(payload["iss"])
          raise OAuthError, "ID token issuer mismatch"
        end

        unless payload["aud"] == Shakha.config.google_client_id
          raise OAuthError, "ID token audience mismatch"
        end

        raise OAuthError, "ID token expired" if payload["exp"].to_i <= Time.now.to_i

        if expected_nonce.present? &&
           !ActiveSupport::SecurityUtils.secure_compare(payload["nonce"].to_s, expected_nonce)
          raise OAuthError, "ID token nonce mismatch"
        end
      end

      def http_post(url, body)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 5
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = URI.encode_www_form(body)

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise OAuthError, "Google returned HTTP #{response.code}"
        end

        response
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError => e
        raise OAuthError, "Unable to reach Google: #{e.message}"
      end
    end
  end
end
