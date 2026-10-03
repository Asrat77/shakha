# frozen_string_literal: true

module Shakha
  module ConfigValidator
    BUILT_IN_CREDENTIALS = {
      google: %i[google_client_id google_client_secret],
      github: %i[github_client_id github_client_secret]
    }.freeze

    class << self
      def validate!(config)
        missing = []
        missing << "APP_ORIGIN" unless config.app_origin.present?

        Array(config.providers).each do |provider|
          BUILT_IN_CREDENTIALS.fetch(provider.to_sym, []).each do |attr|
            missing << attr.to_s.upcase unless config.public_send(attr).present?
          end
        end

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
