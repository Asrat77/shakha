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

    @registry = PROVIDER_MAP.dup

    class << self
      # Registers a provider under +name+. +klass+ is a Providers::Base
      # subclass or its name as a String (a String survives code reloading in
      # development). Registering an existing name replaces it.
      def register(name, klass)
        @registry[name.to_sym] = klass
      end

      def registered
        @registry.keys
      end

      def resolve(name)
        klass = @registry[name.to_sym] || raise(ConfigurationError, "Unknown provider: #{name}")
        klass = klass.constantize if klass.is_a?(String)
        klass.new
      end

      def reset!
        @registry = PROVIDER_MAP.dup
      end
    end
  end
end
