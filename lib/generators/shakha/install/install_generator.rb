# frozen_string_literal: true

require "rails/generators/active_record"

module Shakha
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration
      source_root File.expand_path("templates", __dir__)

      BUILT_IN_PROVIDERS = %w[google github].freeze

      desc "Installs Shakha — headless OAuth broker for Rails"

      class_option :providers, type: :string, default: "google,github",
                               desc: "Comma-separated providers to configure (#{BUILT_IN_PROVIDERS.join(', ')})"

      def validate_providers
        unknown = providers - BUILT_IN_PROVIDERS
        raise Thor::Error, "Unknown provider(s): #{unknown.join(', ')}. Choose from: #{BUILT_IN_PROVIDERS.join(', ')}" if unknown.any?
        raise Thor::Error, "--providers must name at least one provider" if providers.empty?
      end

      def copy_migration
        migration_template "create_shakha_tables.rb.erb", "db/migrate/create_shakha_tables.rb"
      end

      def copy_initializer
        path = "config/initializers/shakha.rb"
        if File.exist?(File.join(destination_root, path)) && !options[:force]
          say_status :exist, path, :blue
          return
        end

        template "shakha.rb.erb", path
      end

      def inject_application_controller
        path = "app/controllers/application_controller.rb"
        full_path = File.join(destination_root, path)
        return unless File.exist?(full_path)
        return if File.read(full_path).include?("Shakha::ControllerHelpers")

        inject_into_class path, "ApplicationController", "  include Shakha::ControllerHelpers\n"
        say_status :insert, "ApplicationController -> include Shakha::ControllerHelpers", :green
      end

      def enable_cookies_for_api_mode
        return unless api_only_app?
        return if File.read(File.join(destination_root, "config/application.rb")).include?("ActionDispatch::Cookies")

        application "config.middleware.use ActionDispatch::Cookies"
        say_status :insert, "config/application.rb -> ActionDispatch::Cookies (API mode)", :green
      end

      def print_post_install
        origin = Shakha.config.app_origin || "http://localhost:3000"

        say ""
        say "  Shakha installed!", :green
        say "  #{'─' * 50}", :green
        say ""
        say "  1. Set environment variables:", :yellow
        providers.each do |provider|
          say "     #{provider.upcase}_CLIENT_ID / #{provider.upcase}_CLIENT_SECRET", :cyan
        end
        say ""
        say "  2. For SPA: set ALLOWED_REDIRECT_ORIGINS", :yellow
        say ""
        say "  3. Run migrations:", :yellow
        say "     bin/rails db:migrate", :cyan
        say ""
        say "  4. OAuth app redirect / callback URLs:", :yellow
        providers.each do |provider|
          say "     #{origin}/auth/shakha/#{provider}/callback", :cyan
        end
        say "  #{'─' * 50}", :green
        say ""
        say "  Tell your frontend dev:", :cyan
        say "    Sign in:  #{origin}/auth/shakha/#{providers.first}"
        say "    Session:  GET #{origin}/auth/shakha/session"
        say "    Auth:     Authorization: Bearer <token>"
        say "    Sign out: DELETE #{origin}/auth/shakha/sign_out"
        say ""
      end

      private

      def providers
        @providers ||= options[:providers].to_s.split(",").map { |p| p.strip.downcase }.reject(&:empty?).uniq
      end

      def migration_version
        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end

      def api_only_app?
        path = File.join(destination_root, "config/application.rb")
        File.exist?(path) && File.read(path).include?("config.api_only = true")
      end
    end
  end
end
