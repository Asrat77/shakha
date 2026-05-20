# frozen_string_literal: true

require "active_support/concern"

module Shakha
  module ControllerHelpers
    extend ActiveSupport::Concern

    included do
      helper_method :current_session, :current_user, :signed_in? if respond_to?(:helper_method)
    end

    private

    def current_session
      return @current_session if defined?(@current_session)
      @current_session = find_session_from_cookie || find_session_from_bearer
    end

    def current_user
      current_session&.user
    end

    def signed_in?
      current_session.present?
    end

    def authenticate!
      return if signed_in?

      if request.format.json?
        render json: { error: "Authentication required" }, status: :unauthorized
      else
        redirect_to "/auth/shakha?return_to=#{CGI.escape(request.fullpath)}"
      end
    end

    def find_session_from_cookie
      return unless respond_to?(:cookies)
      token = cookies.encrypted[:shakha_session_token]
      return unless token
      Shakha::Session.active.find_by(token: token)
    end

    def find_session_from_bearer
      header = request.headers["Authorization"]
      return unless header&.start_with?("Bearer ")

      token = header.delete_prefix("Bearer ")
      Shakha::Session.active.find_by(token: token)
    end
  end
end
