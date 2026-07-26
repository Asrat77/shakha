# frozen_string_literal: true

require_relative "../test_helper"

module Shakha
  class RateLimiterTest < ActionDispatch::IntegrationTest
    setup do
      Shakha.config.rate_limiting_enabled = true
      Rails.cache.clear
    end

    teardown do
      Shakha.config.rate_limiting_enabled = false
    end

    test "authorize allows up to the limit then returns 429" do
      20.times do
        get "/auth/shakha/google"
        assert_response :redirect
      end

      get "/auth/shakha/google"
      assert_response :too_many_requests
      assert_match(/Too many requests/, JSON.parse(response.body)["error"])
    end

    test "callback is limited independently" do
      10.times do
        get "/auth/shakha/google/callback", params: { code: "c", state: "s" }
        assert_response :redirect
      end

      get "/auth/shakha/google/callback", params: { code: "c", state: "s" }
      assert_response :too_many_requests
    end

    test "no limiting when disabled" do
      Shakha.config.rate_limiting_enabled = false
      25.times do
        get "/auth/shakha/google"
        assert_response :redirect
      end
    end
  end
end
