# frozen_string_literal: true

require "net/http"
require "uri"

module Shakha
  class AuthController < ApplicationController
    include PKCEMixin

    skip_before_action :verify_authenticity_token, only: [:callback, :token]

    def new
      @client = find_or_create_client
      @return_to = params[:return_to] || "/"
    end

    def authorize
      pkce = create_pkce_bundle
      @client = find_or_create_client

      google_auth_url = build_google_auth_url(pkce)

      redirect_to google_auth_url
    end

    def callback
      verifier = verify_pkce!(params[:code])

      exchange_code_for_tokens(params[:code], verifier)
    rescue PKCEError, GoogleOAuthError => e
      redirect_to shakha.error_path(message: e.message)
    end

    def token
      code = params[:code]
      verifier = params[:code_verifier]

      raise PKCEError, "Missing code" unless code
      raise PKCEError, "Missing code_verifier" unless verifier

      id_token = exchange_code_for_id_token(code, verifier)

      render json: {
        id_token: id_token,
        pairwise_sub: id_token_payload(id_token)[:sub],
        expires_in: 24.hours.to_i
      }
    rescue PKCEError, JWTError, GoogleOAuthError => e
      render json: { error: e.message }, status: :unauthorized
    end

    def error
      @message = params[:message] || "Authentication failed"
    end

    private

    def find_or_create_client
      origin = URI.parse(request.origin).origin

      Shakha::Client.find_or_create_by!(origin: origin) do |client|
        client.name = URI.parse(request.origin).host
      end
    end

    def build_google_auth_url(pkce)
      client_id = Shakha.config.google_client_id || ENV["GOOGLE_CLIENT_ID"]
      redirect_uri = "#{Shakha.config.service_base_url}/auth/shakha/callback"

      scopes = ["openid", "email", "profile"].join(" ")
      scopes += " https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile" if params[:request_pii]

      params = {
        client_id: client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: scopes,
        code_challenge: pkce[:challenge],
        code_challenge_method: "S256",
        state: pkce[:state],
        access_type: "offline",
        prompt: "consent"
      }

      URI.parse("https://accounts.google.com/o/oauth2/v2/auth").tap do |uri|
        uri.query = URI.encode_www_form(params)
      end.to_s
    end

    def exchange_code_for_tokens(code, verifier)
      client_id = Shakha.config.google_client_id || ENV["GOOGLE_CLIENT_ID"]
      client_secret = Shakha.config.google_client_secret || ENV["GOOGLE_CLIENT_SECRET"]
      redirect_uri = "#{Shakha.config.service_base_url}/auth/shakha/callback"

      response = http_post(
        "https://oauth2.googleapis.com/token",
        {
          code: code,
          client_id: client_id,
          client_secret: client_secret,
          redirect_uri: redirect_uri,
          grant_type: "authorization_code",
          code_verifier: verifier
        }
      )

      tokens = JSON.parse(response.body)
      id_token = tokens["id_token"]
      access_token = tokens["access_token"]

      raise GoogleOAuthError, "No id_token received" unless id_token

      payload = decode_id_token(id_token)
      google_sub = payload["sub"]
      pairwise_sub = Shakha.derive_pairwise_sub(google_sub)

      client = find_or_create_client
      user = Shakha::User.find_or_initialize_by(pairwise_sub: pairwise_sub)

      if params[:request_pii] && payload["email"]
        user.assign_attributes(
          email: payload["email"],
          name: payload["name"],
          picture: payload["picture"]
        )
      end
      user.save!

      session_record = Shakha::Session.create!(
        user: user,
        client: client,
        jti: SecureRandom.uuid
      )

      cookies.encrypted[:shakha_session_token] = {
        value: session_record.token,
        httponly: true,
        secure: Rails.env.production?,
        same_site: :lax,
        expires: Shakha.config.session_lifetime.from_now
      }

      return_to = pkce_state&.dig(:return_to) || "/"

      redirect_to return_to
    end

    def exchange_code_for_id_token(code, verifier)
      client_id = Shakha.config.google_client_id || ENV["GOOGLE_CLIENT_ID"]
      client_secret = Shakha.config.google_client_secret || ENV["GOOGLE_CLIENT_SECRET"]
      redirect_uri = "#{Shakha.config.service_base_url}/auth/shakha/callback"

      response = http_post(
        "https://oauth2.googleapis.com/token",
        {
          code: code,
          client_id: client_id,
          client_secret: client_secret,
          redirect_uri: redirect_uri,
          grant_type: "authorization_code",
          code_verifier: verifier
        }
      )

      tokens = JSON.parse(response.body)
      tokens["id_token"] || raise(GoogleOAuthError, "No id_token in response")
    end

    def id_token_payload(id_token)
      JWT.decode(id_token, nil, false)[0]
    end

    def decode_id_token(id_token)
      JWT.decode(id_token, nil, false)[0]
    end

    def http_post(url, body)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = URI.encode_www_form(body)

      http.request(request)
    end
  end
end