# frozen_string_literal: true

require_relative "../lib/shakha"

ENV["RAILS_ENV"] = "test"
ENV["SHAKHA_APP_ORIGIN"] = "https://test.app.com"
ENV["SHAKHA_SERVICE_SECRET"] = "test_secret_key_for_testing_only"

require "active_support/all"
require "active_support/test_case"
require "action_controller/test_case"
require "action_dispatch/test_process"
require "minitest/autorun"

class ActiveSupport::TestCase
  fixtures :all
end

module Shakha
  class TestCase < ActiveSupport::TestCase
    setup do
      Shakha.config.service_secret = "test_secret_key_for_testing_only"
    end
  end
end