# frozen_string_literal: true

module Shakha
  class Config
    attr_accessor :app_origin,
                  :service_url,
                  :service_secret,
                  :google_client_id,
                  :google_client_secret,
                  :issuer,
                  :session_lifetime,
                  :signing_key,
                  :verification_key,
                  :key_id,
                  :rate_limiting_enabled

    def initialize
      @session_lifetime = 30.days
      @issuer = "https://shakha.dev"
      @rate_limiting_enabled = false
    end

    def embedded?
      service_url.blank?
    end

    def service_base_url
      return app_origin if embedded?

      service_url.chomp("/")
    end

    def client_id
      return @client_id if defined?(@client_id)

      origin = URI.parse(app_origin).origin
      @client_id = "origin:#{origin}"
    end

    def audience
      client_id
    end
  end
end