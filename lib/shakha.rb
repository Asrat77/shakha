# frozen_string_literal: true

require "shakha/version"
require "shakha/config"
require "shakha/engine"

module Shakha
  class << self
    def setup
      yield(config)
    end

    def config
      @config ||= Config.new
    end

    def verify_token(id_token, audience: nil)
      JwtHandler.verify(id_token, audience: audience || default_audience)
    end

    def sign_token(payload, exp: 24.hours.from_now)
      JwtHandler.encode(payload, exp: exp)
    end

    def derive_pairwise_sub(google_sub, client_id = nil)
      Pairwise.derive(google_sub, client_id || default_client_id)
    end

    private

    def default_audience
      "origin:#{config.app_origin&.then { |url| URI.parse(url).origin }}"
    end

    def default_client_id
      "origin:#{URI.parse(config.app_origin).origin}"
    end
  end

  class ConfigurationError < StandardError; end
  class JWTError < StandardError; end
  class PKCEError < StandardError; end
  class GoogleOAuthError < StandardError; end
end