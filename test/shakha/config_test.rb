# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class ConfigTest < ActiveSupport::TestCase
    test "sets defaults" do
      config = Config.new

      assert_equal "https://shakha.dev", config.issuer
      assert_equal 30.days, config.session_lifetime
    end

    test "calculates client_id from origin" do
      config = Config.new
      config.app_origin = "https://myapp.com"

      assert_equal "origin:https://myapp.com", config.client_id
    end

    test "returns origin for embedded mode" do
      config = Config.new
      config.app_origin = "https://myapp.com"

      assert_nil config.service_url
      assert config.embedded?
      assert_equal "https://myapp.com", config.service_base_url
    end

    test "returns service_url when set" do
      config = Config.new
      config.app_origin = "https://myapp.com"
      config.service_url = "https://auth.shakha.dev/"

      refute config.embedded?
      assert_equal "https://auth.shakha.dev", config.service_base_url
    end
  end
end