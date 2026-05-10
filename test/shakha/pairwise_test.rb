# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class PairwiseTest < ActiveSupport::TestCase
    test "derives consistent pairwise_sub for same google_sub and client" do
      result1 = Pairwise.derive("google_123", "origin:https://myapp.com")
      result2 = Pairwise.derive("google_123", "origin:https://myapp.com")

      assert_equal result1, result2
      assert result1.start_with?("ps_")
    end

    test "different google_sub produces different pairwise_sub" do
      result1 = Pairwise.derive("google_123", "origin:https://myapp.com")
      result2 = Pairwise.derive("google_456", "origin:https://myapp.com")

      refute_equal result1, result2
    end

    test "different client_id produces different pairwise_sub" do
      result1 = Pairwise.derive("google_123", "origin:https://app1.com")
      result2 = Pairwise.derive("google_123", "origin:https://app2.com")

      refute_equal result1, result2
    end

    test "raises error when secret not configured" do
      original = Shakha.config.service_secret
      Shakha.config.service_secret = nil

      assert_raises(ConfigurationError) do
        Pairwise.derive("google_123", "origin:https://myapp.com")
      end
    ensure
      Shakha.config.service_secret = original
    end
  end
end