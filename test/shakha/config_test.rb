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
  end
end
