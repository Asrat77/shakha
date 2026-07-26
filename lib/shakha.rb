# frozen_string_literal: true

require "shakha/version"
require "shakha/config"
require "shakha/config_validator"
require "shakha/pkce"
require "shakha/rate_limiter"
require "shakha/error_handler"
require "shakha/controller_helpers"
require "shakha/providers"
require "shakha/engine"

module Shakha
  class << self
    def setup
      yield(config)
    end

    def config
      @config ||= Config.new
    end
  end

  class ConfigurationError < StandardError; end
  class PKCEError < StandardError; end
  class OAuthError < StandardError; end
end
