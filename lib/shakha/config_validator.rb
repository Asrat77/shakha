# frozen_string_literal: true

module Shakha
  module ConfigValidator
    class << self
      def validate!(config)
        missing = []
        missing << "APP_ORIGIN" unless config.app_origin.present?
        missing << "GOOGLE_CLIENT_ID" unless config.google_client_id.present?
        missing << "GOOGLE_CLIENT_SECRET" unless config.google_client_secret.present?

        unless missing.empty?
          message = "Shakha: missing required configuration: #{missing.join(', ')}"
          if Rails.env.production?
            raise ConfigurationError, message
          else
            Rails.logger.warn(message)
          end
        end

        true
      end
    end
  end
end
