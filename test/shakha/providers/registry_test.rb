# frozen_string_literal: true

require_relative "../../test_helper"

module Shakha
  module Providers
    class RegistryTest < ActiveSupport::TestCase
      test "resolves the google provider" do
        assert_instance_of Google, Providers.resolve(:google)
      end

      test "resolves the github provider" do
        assert_instance_of GitHub, Providers.resolve(:github)
      end

      test "accepts a string name" do
        assert_instance_of Google, Providers.resolve("google")
      end

      test "raises a configuration error for an unknown provider" do
        assert_raises(Shakha::ConfigurationError) { Providers.resolve(:unknown) }
      end
    end
  end
end
