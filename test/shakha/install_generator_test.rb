# frozen_string_literal: true

require_relative "../test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/shakha/install/install_generator"

module Shakha
  class InstallGeneratorTest < Rails::Generators::TestCase
    tests Shakha::Generators::InstallGenerator
    destination File.expand_path("../../tmp/generator_test", __dir__)
    setup :prepare_destination

    test "creates the migration and initializer" do
      run_generator

      assert_migration "db/migrate/create_shakha_tables.rb" do |content|
        assert_match(/create_table :shakha_users/, content)
        assert_match(/create_table :shakha_sessions/, content)
      end

      assert_file "config/initializers/shakha.rb" do |content|
        assert_match(/Shakha\.setup/, content)
        assert_match(/GOOGLE_CLIENT_ID/, content)
      end
    end

    test "injects ControllerHelpers into an existing ApplicationController" do
      FileUtils.mkdir_p(File.join(destination_root, "app/controllers"))
      File.write(File.join(destination_root, "app/controllers/application_controller.rb"),
                 "class ApplicationController < ActionController::API\nend\n")

      run_generator

      assert_file "app/controllers/application_controller.rb" do |content|
        assert_match(/include Shakha::ControllerHelpers/, content)
      end
    end

    test "enables the cookies middleware for an API-only app" do
      write_application_rb("config.api_only = true")

      run_generator

      assert_file "config/application.rb" do |content|
        assert_match(/config\.middleware\.use ActionDispatch::Cookies/, content)
      end
    end

    test "does not touch middleware for a full-stack app" do
      write_application_rb("config.load_defaults 8.0")

      run_generator

      assert_file "config/application.rb" do |content|
        refute_match(/ActionDispatch::Cookies/, content)
      end
    end

    private

    def write_application_rb(body_line)
      FileUtils.mkdir_p(File.join(destination_root, "config"))
      File.write(File.join(destination_root, "config/application.rb"), <<~RB)
        module Dummy
          class Application < Rails::Application
            #{body_line}
          end
        end
      RB
    end
  end
end
