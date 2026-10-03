# frozen_string_literal: true

require_relative "../../test_helper"

module Shakha
  module Providers
    class RegistryTest < ActiveSupport::TestCase
      class FakeProvider < Base
        def provider_name
          :fake
        end
      end

      teardown { Providers.reset! }

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

      test "register adds a third-party provider" do
        Providers.register(:fake, FakeProvider)

        assert_instance_of FakeProvider, Providers.resolve(:fake)
        assert_includes Providers.registered, :fake
      end

      test "register accepts a class name string" do
        Providers.register("fake", "Shakha::Providers::RegistryTest::FakeProvider")

        assert_instance_of FakeProvider, Providers.resolve(:fake)
      end

      test "registering an existing name overwrites it" do
        Providers.register(:github, FakeProvider)

        assert_instance_of FakeProvider, Providers.resolve(:github)
      end

      test "reset! restores the built-ins" do
        Providers.register(:github, FakeProvider)
        Providers.reset!

        assert_instance_of GitHub, Providers.resolve(:github)
        assert_raises(Shakha::ConfigurationError) { Providers.resolve(:fake) }
      end
    end
  end
end
