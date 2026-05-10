# frozen_string_literal: true

require "active_support/concern"

module Shakha
  module ControllerHelpers
    extend ActiveSupport::Concern

    included do
      helper_method :current_session, :current_user, :signed_in?
    end

    private

    def current_session
      return @current_session if defined?(@current_session)

      @current_session = find_session || authenticate_from_bearer || authenticate_from_cookie
    end

    def current_user
      current_session&.user
    end

    def signed_in?
      current_session.present?
    end

    def authenticate!
      return if signed_in?

      redirect_to shakha.new_auth_path(return_to: request.fullpath)
    end

    def authenticate_from_bearer
      return unless (token = bearer_token)

      payload = Shakha.verify_token(token)
      find_session_by_jti(payload["jti"])
    end

    def authenticate_from_cookie
      find_session_by_token(session_token)
    end

    def bearer_token
      pattern = /^Bearer /
      header = request.headers["Authorization"]
      return unless header&.match?(pattern)

      header.gsub(pattern, "")
    end

    def session_token
      request.cookie_jar.encrypted[:shakha_session_token]
    end

    def find_session
      return unless (token = session_token)

      Shakha::Session.active.find_by(token: token)
    end

    def find_session_by_jti(jti)
      return unless jti

      Shakha::Session.active.find_by(jti: jti)
    end
  end
end