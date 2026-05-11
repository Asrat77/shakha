# frozen_string_literal: true

require "net/http"
require "uri"

module Shakha
  class AuthController < ApplicationController
    include PKCEMixin

    skip_before_action :verify_authenticity_token, only: [:callback, :token]

    def new
      @client = find_or_create_client
      @return_to = sanitize_return_to(params[:return_to])
    end

    def authorize
      params[:return_to] = sanitize_return_to(params[:return_to])
      pkce = create_pkce_bundle
      @client = find_or_create_client

      google_auth_url = build_google_auth_url(pkce)

      redirect_to google_auth_url, allow_other_host: true
    end

    def callback
      pkce_result = verify_pkce!(params[:code], params[:state])
      exchange_code_for_tokens(params[:code], pkce_result[:verifier], pkce_result[:return_to])
    rescue PKCEError, GoogleOAuthError => e
      ActiveSupport::Notifications.instrument("shakha.sign_in_failed", {
        reason: e.class.name,
        ip: request.remote_ip
      })
      Rails.logger.warn("[Shakha] Auth error: #{e.class}: #{e.message}")
      redirect_to "/auth/shakha/error?message=#{URI.encode_www_form_component(user_facing_error(e))}"
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

    def sanitize_return_to(raw)
      return "/" if raw.blank?

      uri = URI.parse(raw)
      return "/" if uri.host.present? && ![app_origin_host, client_origin_host].include?(uri.host)
      return "/" unless uri.path.present? && uri.path.start_with?("/")

      uri.path
    rescue URI::InvalidURIError
      "/"
    end

    def app_origin_host
      URI.parse(Shakha.config.app_origin).host
    end

    def client_origin_host
      URI.parse(Shakha.config.service_base_url).host
    rescue URI::InvalidURIError
      nil
    end

    def user_facing_error(exception)
      case exception
      when PKCEError
        "Authentication failed. Please try again."
      when GoogleOAuthError
        "Unable to sign in with Google. Please try again later."
      else
        "An unexpected error occurred. Please try again."
      end
    end

    def find_or_create_client
      origin = request.origin || Shakha.config.app_origin
      origin_uri = URI.parse(origin).origin

      if Shakha.config.embedded?
        Shakha::Client.find_or_create_by!(origin: origin_uri) do |client|
          client.name = URI.parse(origin).host
        end
      else
        Shakha::Client.find_by!(origin: origin_uri)
      end
    rescue ActiveRecord::RecordNotFound
      raise ConfigurationError, "Unknown client origin: #{origin_uri}. Register this origin in shakha_clients first."
    end

    def build_google_auth_url(pkce)
      client_id = Shakha.config.google_client_id || ENV["GOOGLE_CLIENT_ID"]
      base_url = Shakha.config.service_base_url || "http://localhost:3000"
      redirect_uri = "#{base_url}/auth/shakha/callback"

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

    def exchange_code_for_tokens(code, verifier, return_to = "/")
      client_id = Shakha.config.google_client_id || ENV["GOOGLE_CLIENT_ID"]
      client_secret = Shakha.config.google_client_secret || ENV["GOOGLE_CLIENT_SECRET"]
      base_url = Shakha.config.service_base_url || "http://localhost:3000"
      redirect_uri = "#{base_url}/auth/shakha/callback"

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

      client = find_or_create_client
      pairwise_sub = Shakha.derive_pairwise_sub(google_sub, client.client_id)

      user = Shakha::User.find_or_initialize_by(pairwise_sub: pairwise_sub, client: client)

      if payload["email"]
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

      redirect_to sanitize_return_to(return_to)
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