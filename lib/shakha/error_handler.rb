# frozen_string_literal: true

require "active_support/concern"

module Shakha
  module ErrorHandler
    extend ActiveSupport::Concern

    included do
      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from Shakha::JWTError, with: :unauthorized
      rescue_from Shakha::PKCEError, with: :bad_request
      rescue_from Shakha::GoogleOAuthError, with: :bad_gateway
    end

    private

    def not_found(exception)
      render json: { error: exception.message }, status: :not_found
    end

    def unauthorized(exception)
      render json: { error: "Unauthorized" }, status: :unauthorized
    end

    def bad_request(exception)
      render json: { error: exception.message }, status: :bad_request
    end

    def bad_gateway(exception)
      render json: { error: exception.message }, status: :bad_gateway
    end
  end
end