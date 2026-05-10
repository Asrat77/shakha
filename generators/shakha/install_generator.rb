# frozen_string_literal: true
# This generator creates a migration for the Shakha tables

require "rails/generators/active_record/migration"
require "rails/generators/active_record/migration/migration_generator"

module Shakha
  class InstallGenerator < Rails::Generators::Base
    source_root File.expand_path("templates", __dir__)

    class_option :skip_migration, type: :boolean, default: false, desc: "Skip migration generation"

    def copy_initializer
      template "initializer.rb.erb", "config/initializers/shakha.rb"
    end

    def create_migration
      return if options[:skip_migration]

      migration_template(
        "migration.rb.erb",
        "db/migrate/create_shakha_tables.rb",
        migration_version: migration_version
      )
    end

    def add_routes
      route 'mount Shakha::Engine => "/auth/shakha", as: :shakha'
    end

    private

    def migration_version
      ">= 7.1" ? "[7.1]" : ""
    end
  end
end