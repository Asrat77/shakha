# frozen_string_literal: true

require "net/http"
require "uri"

module Shakha
  module Providers
    class GitHub < Base
      AUTHORIZE_URL = "https://github.com/login/oauth/authorize"
      TOKEN_URL = "https://github.com/login/oauth/access_token"
      USER_API_URL = "https://api.github.com/user"

      def provider_name
        :github
      end

      # GitHub OAuth has no nonce concept; the keyword is accepted for a
      # uniform provider interface and ignored.
      def authorize_url(state:, code_challenge:, redirect_uri:, nonce: nil)
        params = {
          client_id: Shakha.config.github_client_id,
          redirect_uri: redirect_uri,
          scope: scopes.join(" "),
          state: state
        }

        "#{AUTHORIZE_URL}?#{URI.encode_www_form(params)}"
      end

      def exchange_code(code:, code_verifier:, redirect_uri:)
        response = http_post(TOKEN_URL, {
          code: code,
          client_id: Shakha.config.github_client_id,
          client_secret: Shakha.config.github_client_secret,
          redirect_uri: redirect_uri
        }, accept: :json)

        JSON.parse(response.body)
      end

      def identity_from_response(token_response, expected_nonce: nil)
        access_token = token_response["access_token"]
        raise OAuthError, "No access_token received" unless access_token

        user_data = fetch_user(access_token)

        {
          provider: :github,
          uid: user_data["id"].to_s,
          email: user_data["email"],
          name: user_data["name"] || user_data["login"],
          picture: user_data["avatar_url"]
        }
      end

      def scopes
        %w[user:email]
      end

      private

      def fetch_user(access_token)
        uri = URI.parse(USER_API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 5
        http.read_timeout = 10

        request = Net::HTTP::Get.new(uri.request_uri)
        request["Authorization"] = "Bearer #{access_token}"
        request["Accept"] = "application/json"

        response = http.request(request)
        JSON.parse(response.body)
      end

      def http_post(url, body, accept: :json)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 5
        http.read_timeout = 10

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Accept"] = "application/json" if accept == :json
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = URI.encode_www_form(body)

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise OAuthError, "GitHub returned HTTP #{response.code}"
        end

        response
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, SocketError => e
        raise OAuthError, "Unable to reach GitHub: #{e.message}"
      end
    end
  end
end
