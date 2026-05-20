# frozen_string_literal: true

require "shakha/providers/base"
require "shakha/providers/google"
require "shakha/providers/github"

module Shakha
  module Providers
    PROVIDER_MAP = {
      google: "Shakha::Providers::Google",
      github: "Shakha::Providers::GitHub"
    }.freeze

    def self.resolve(name)
      class_name = PROVIDER_MAP[name.to_sym] || raise(ConfigurationError, "Unknown provider: #{name}")
      class_name.constantize.new
    end
  end
end
