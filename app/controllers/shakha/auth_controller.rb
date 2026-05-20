# frozen_string_literal: true

require "net/http"
require "uri"

module Shakha
  class AuthController < ApplicationController
    include PKCEMixin
    include RateLimiter

    skip_before_action :verify_authenticity_token, only: [:callback]

    def new
      @client = find_or_create_client
      @return_to = sanitize_return_to(params[:return_to])
      @providers = Shakha.config.providers
    end

    def authorize
      provider = resolve_provider
      pkce = create_pkce_bundle

      redirect_uri = "#{Shakha.config.app_origin}/auth/shakha/#{provider.provider_name}/callback"
      auth_url = provider.authorize_url(
        state: pkce[:state],
        code_challenge: pkce[:challenge],
        redirect_uri: redirect_uri
      )

      redirect_to auth_url, allow_other_host: true
    end

    def callback
      provider = resolve_provider
      pkce_result = verify_pkce!(params[:state])

      token_response = provider.exchange_code(
        code: params[:code],
        code_verifier: pkce_result[:verifier],
        redirect_uri: "#{Shakha.config.app_origin}/auth/shakha/#{provider.provider_name}/callback"
      )

      identity = provider.identity_from_response(token_response)
      user = find_or_create_user(provider.provider_name, identity)
      session_record = create_session(user)
      set_session_cookie(session_record)
      redirect_to build_return_url(pkce_result[:return_to], session_record)

    rescue PKCEError, OAuthError => e
      handle_auth_failure(e, pkce_result)
    end

    def destroy
      current_session&.destroy
      cookies.delete(:shakha_session_token)

      if request.format.json?
        render json: { status: "signed_out" }
      else
        redirect_to params[:return_to].presence || "/"
      end
    end

    def error
      @message = params[:message] || "Authentication failed"
    end

    private

    def resolve_provider
      provider_name = (params[:provider] || :google).to_sym
      Shakha::Providers.resolve(provider_name)
    end

    def find_or_create_user(provider_name, identity)
      Shakha::User.find_or_create_by!(
        provider: provider_name.to_s,
        uid: identity[:uid]
      ) do |user|
        user.client = find_or_create_client
        user.email = identity[:email]
        user.name = identity[:name]
        user.picture = identity[:picture]
      end
    end

    def create_session(user)
      Shakha::Session.create!(
        user: user,
        client: find_or_create_client,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    end

    def set_session_cookie(session_record)
      cookies.encrypted[:shakha_session_token] = {
        value: session_record.token,
        httponly: true,
        secure: Rails.env.production?,
        same_site: :lax,
        expires: Shakha.config.session_lifetime.from_now
      }
    end

    def build_return_url(return_to, session_record)
      uri = URI.parse(return_to || "/")
      existing = URI.decode_www_form(uri.query || "").to_h
      existing["token"] = session_record.token
      existing["expires_at"] = session_record.expires_at.iso8601
      uri.query = URI.encode_www_form(existing)
      uri.to_s
    end

    def handle_auth_failure(exception, pkce_result)
      return_to = pkce_result&.dig(:return_to) || "/"

      if request.format.json? || api_request?
        render json: { error: user_facing_error(exception) }, status: :unauthorized
      else
        redirect_to "#{return_to}?error=#{URI.encode_www_form_component(user_facing_error(exception))}"
      end
    end

    def api_request?
      request.headers["Accept"]&.include?("application/json")
    end

    def sanitize_return_to(raw)
      return "/" if raw.blank?

      uri = URI.parse(raw)
      app_host = URI.parse(Shakha.config.app_origin).host

      return "/" unless uri.path.present? && uri.path.start_with?("/")

      if uri.host.present? && uri.host != app_host && !allowed_origin?(uri.origin)
        return "/"
      end

      raw
    rescue URI::InvalidURIError
      "/"
    end

    def allowed_origin?(origin)
      Shakha.config.allowed_redirect_origins&.include?(origin) || false
    end

    def find_or_create_client
      origin = request.origin || Shakha.config.app_origin
      origin_uri = URI.parse(origin).origin
      Shakha::Client.find_or_create_by!(origin: origin_uri) do |client|
        client.name = URI.parse(origin).host
      end
    end

    def user_facing_error(exception)
      case exception
      when PKCEError then "Authentication failed. Please try again."
      when OAuthError then "Unable to sign in. Please try again later."
      else "An unexpected error occurred. Please try again."
      end
    end
  end
end
