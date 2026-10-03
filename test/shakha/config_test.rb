# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class ConfigTest < ActiveSupport::TestCase
    test "defaults" do
      config = Config.new
      assert_equal 30.days, config.session_lifetime
      assert_equal false, config.rate_limiting_enabled
      assert_equal [ :google ], config.providers
    end

    test "setup yields the singleton config" do
      original = Shakha.config.session_lifetime
      Shakha.setup { |c| c.session_lifetime = 1.day }
      assert_equal 1.day, Shakha.config.session_lifetime
    ensure
      Shakha.config.session_lifetime = original
    end

    test "validator passes when required values present" do
      assert ConfigValidator.validate!(Shakha.config)
    end

    test "validator requires credentials only for enabled built-in providers" do
      config = Config.new
      config.app_origin = "http://localhost:3000"
      config.providers = [ :github, :gitlab ]
      config.github_client_id = "id"
      config.github_client_secret = "secret"

      in_production { assert ConfigValidator.validate!(config) }

      config.github_client_secret = nil
      error = assert_raises(ConfigurationError) do
        in_production { ConfigValidator.validate!(config) }
      end
      assert_equal "Shakha: missing required configuration: GITHUB_CLIENT_SECRET", error.message
    end

    private

    def in_production
      original = Rails.env
      Rails.env = "production"
      yield
    ensure
      Rails.env = original
    end
  end
end
