# frozen_string_literal: true

require "active_support/concern"

module Shakha
  module ErrorHandler
    extend ActiveSupport::Concern

    included do
      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from Shakha::ProviderNotFound, with: :provider_not_found
      rescue_from Shakha::PKCEError, with: :bad_request
      rescue_from Shakha::OAuthError, with: :bad_gateway
    end

    private

    def not_found(exception)
      render json: { error: exception.message }, status: :not_found
    end

    def provider_not_found(_exception)
      render json: { error: "Unknown provider" }, status: :not_found
    end

    def unauthorized(exception)
      render json: { error: "Unauthorized" }, status: :unauthorized
    end

    def bad_request(exception)
      render json: { error: "Bad request" }, status: :bad_request
    end

    def bad_gateway(exception)
      Rails.logger.error("[Shakha] OAuth error: #{exception.message}")
      render json: { error: "Authentication service unavailable" }, status: :bad_gateway
    end
  end
end
