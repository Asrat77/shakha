# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class ConfigTest < ActiveSupport::TestCase
    test "sets defaults" do
      config = Config.new

      assert_equal 30.days, config.session_lifetime
      assert_equal [:google], config.providers
      assert_equal false, config.rate_limiting_enabled
    end

    test "accepts custom providers" do
      config = Config.new
      config.providers = [:google, :github]

      assert_equal [:google, :github], config.providers
    end
  end
end
