# frozen_string_literal: true

module Shakha
  class InstallGenerator < Rails::Generators::Base
    source_root File.expand_path("templates", __dir__)

    class_option :skip_migration, type: :boolean, default: false, desc: "Skip migration generation"

    def copy_initializer
      template "initializer.rb.erb", "config/initializers/shakha.rb"
    end

    def create_migration
      return if options[:skip_migration]

      sleep 1
      migration_number = Time.now.strftime("%Y%m%d%H%M%S")
      template "migration.rb.erb", "db/migrate/#{migration_number}_create_shakha_tables.rb"
    end

    def add_routes
      route 'mount Shakha::Engine => "/auth/shakha", as: :shakha'
    end
  end
end