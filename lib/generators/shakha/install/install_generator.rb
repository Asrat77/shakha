# frozen_string_literal: true

require "rails/generators/active_record"

module Shakha
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration
      source_root File.expand_path("templates", __dir__)

      desc "Installs Shakha — headless OAuth broker for Rails"

      def copy_migration
        migration_template "create_shakha_tables.rb.erb", "db/migrate/create_shakha_tables.rb"
      end

      def copy_initializer
        template "shakha.rb.erb", "config/initializers/shakha.rb"
      end

      def inject_application_controller
        path = "app/controllers/application_controller.rb"
        return unless File.exist?(path)

        content = File.read(path)
        return if content.include?("Shakha::ControllerHelpers")

        inject_into_class path, "ApplicationController", "  include Shakha::ControllerHelpers\n"
        say_status :insert, "ApplicationController -> include Shakha::ControllerHelpers", :green
      end

      def print_post_install
        origin = Shakha.config.app_origin || "http://localhost:3000"

        say ""
        say "  Shakha installed!", :green
        say "  #{'─' * 50}", :green
        say ""
        say "  1. Set environment variables:", :yellow
        say "     GOOGLE_CLIENT_ID", :cyan
        say "     GOOGLE_CLIENT_SECRET", :cyan
        say ""
        say "  2. (Optional) GitHub:", :yellow
        say "     GITHUB_CLIENT_ID / GITHUB_CLIENT_SECRET", :cyan
        say ""
        say "  3. For SPA: set ALLOWED_REDIRECT_ORIGINS", :yellow
        say ""
        say "  4. Run migrations:", :yellow
        say "     bin/rails db:migrate", :cyan
        say ""
        say "  5. Google Cloud Console redirect URI:", :yellow
        say "     #{origin}/auth/shakha/google/callback", :cyan
        say ""
        say "  6. GitHub OAuth App callback URL:", :yellow
        say "     #{origin}/auth/shakha/github/callback", :cyan
        say "  #{'─' * 50}", :green
        say ""
        say "  Tell your frontend dev:", :cyan
        say "    Sign in:  #{origin}/auth/shakha/google"
        say "    Session:  GET #{origin}/auth/shakha/session"
        say "    Auth:     Authorization: Bearer <token>"
        say "    Sign out: DELETE #{origin}/auth/shakha/sign_out"
        say ""
      end

      private

      def migration_version
        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end
    end
  end
end
