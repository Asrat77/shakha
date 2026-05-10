# frozen_string_literal: true

module Shakha
  class ApplicationController < ActionController::Base
    include ErrorHandler
    include ControllerHelpers

    protect_from_forgery with: :exception

    layout -> { false if request.format == :json }

    rescue_from ActiveSupport::ActionController::InvalidAuthenticityToken, with: :invalid_csrf_token

    private

    def invalid_csrf_token(exception)
      render json: { error: "Invalid CSRF token" }, status: :unprocessable_entity
    end
  end
end